use crate::{
    codec::{realtime_codec_thread_num, EncoderApi, EncoderCfg},
    convert::{I444ToABGR, I444ToARGB},
    hwcodec::HwRamEncoder,
    CodecFormat, EncodeInput, EncodeYuvFormat, ImageFormat, ImageRgb, Pixfmt,
};
use base::message_proto::{EncodedVideoFrame, EncodedVideoFrames, VideoFrame};
use hbb_common::{
    anyhow::{anyhow, bail},
    bytes::Bytes,
    ResultType,
};
use std::{
    ffi::c_void,
    os::raw::c_char,
    ptr::NonNull,
    sync::{
        atomic::{AtomicBool, Ordering},
        OnceLock,
    },
    time::{Duration, Instant},
};

#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug)]
pub(super) enum Format {
    H264,
    H265,
}

#[derive(Clone, Copy, Debug)]
enum Backend {
    Nvidia,
    QuickSync,
}

impl Format {
    pub(super) fn from_codec(codec: CodecFormat) -> Option<Self> {
        match codec {
            CodecFormat::H264 => Some(Self::H264),
            CodecFormat::H265 => Some(Self::H265),
            _ => None,
        }
    }

    pub(super) fn from_config(config: &EncoderCfg) -> Option<Self> {
        #[cfg(feature = "vram")]
        use hwcodec::common::DataFormat;
        match config {
            EncoderCfg::HWRAM(cfg) if cfg.name.contains("h264") => Some(Self::H264),
            EncoderCfg::HWRAM(cfg) if cfg.name.contains("hevc") || cfg.name.contains("h265") => {
                Some(Self::H265)
            }
            #[cfg(feature = "vram")]
            EncoderCfg::VRAM(cfg) => match cfg.feature.data_format {
                DataFormat::H264 => Some(Self::H264),
                DataFormat::H265 => Some(Self::H265),
                _ => None,
            },
            _ => None,
        }
    }

    pub(super) fn peer_supports(self, caps: &base::message_proto::SupportedDecoding) -> bool {
        match self {
            Self::H264 => caps.ability_h264 > 0 && caps.i444.h264,
            Self::H265 => caps.ability_h265 > 0 && caps.i444.h265,
        }
    }

    fn is_hevc(self) -> bool {
        matches!(self, Self::H265)
    }

    fn name(self, backend: Backend) -> &'static [u8] {
        match (self, backend) {
            (Self::H264, _) => b"h264_nvenc\0",
            (Self::H265, Backend::Nvidia) => b"hevc_nvenc\0",
            (Self::H265, Backend::QuickSync) => b"hevc_qsv\0",
        }
    }

    pub(super) fn can_encode(self) -> bool {
        self.backend().is_some()
    }

    fn backend(self) -> Option<Backend> {
        static VENDORS: OnceLock<Vec<u32>> = OnceLock::new();
        static H264: OnceLock<Option<Backend>> = OnceLock::new();
        static H265: OnceLock<Option<Backend>> = OnceLock::new();
        if self.disabled().load(Ordering::Relaxed) {
            return None;
        }
        let capability = if self.is_hevc() { &H265 } else { &H264 };
        *capability.get_or_init(|| {
            let vendors =
                VENDORS.get_or_init(|| crate::dxgi::physical_adapter_vendors().unwrap_or_default());
            if vendors.contains(&0x10de) && self.probe(Backend::Nvidia).is_ok() {
                return Some(Backend::Nvidia);
            }
            if self.is_hevc() && vendors.contains(&0x8086) && self.probe(Backend::QuickSync).is_ok()
            {
                return Some(Backend::QuickSync);
            }
            None
        })
    }

    pub(super) fn can_decode(self) -> bool {
        static H264: OnceLock<bool> = OnceLock::new();
        static H265: OnceLock<bool> = OnceLock::new();
        let capability = if self.is_hevc() { &H265 } else { &H264 };
        *capability.get_or_init(|| Decoder::new(self).is_ok())
    }

    fn disabled(self) -> &'static AtomicBool {
        static H264: AtomicBool = AtomicBool::new(false);
        static H265: AtomicBool = AtomicBool::new(false);
        if self.is_hevc() {
            &H265
        } else {
            &H264
        }
    }

    fn probe(self, backend: Backend) -> ResultType<()> {
        let mut encoder = Encoder::open(self, backend, 128, 128, 1.0, None)?;
        let pixels = vec![128; encoder.layout.stride[0] * encoder.layout.h * 3];
        let mut decoder = Decoder::new(self)?;
        let mut rgb = ImageRgb::new(ImageFormat::ARGB, 1);
        for ms in [0, 17, 33] {
            let Ok(frame) = encoder.encode_to_message(EncodeInput::YUV(&pixels), ms) else {
                continue;
            };
            let frames = if self.is_hevc() {
                frame.h265s()
            } else {
                frame.h264s()
            };
            if decoder.decode(frames, &mut rgb)? && rgb.w == 128 && rgb.h == 128 {
                return Ok(());
            }
        }
        bail!("H.26x 4:4:4 probe produced no usable frame");
    }
}

type PacketCallback = unsafe extern "C" fn(*mut c_void, *const u8, i32, i64, i32);
type Convert444 = unsafe extern "C" fn(
    *const u8, i32, *const u8, i32, *const u8, i32, *mut u8, i32, i32, i32,
) -> i32;
type FrameCallback = unsafe extern "C" fn(
    *mut c_void,
    *const u8,
    i32,
    *const u8,
    i32,
    *const u8,
    i32,
    i32,
    i32,
) -> i32;

extern "C" {
    fn rd_i444_encoder(name: *const c_char, w: i32, h: i32, bitrate: i32, gop: i32) -> *mut c_void;
    fn rd_i444_decoder(hevc: i32, threads: i32) -> *mut c_void;
    fn rd_i444_d3d11_decoder(threads: i32) -> *mut c_void;
    fn rd_i444_free(codec: *mut c_void);
    fn rd_i444_convert(
        codec: *mut c_void,
        convert: Convert444,
        y: *const u8,
        y_stride: i32,
        u: *const u8,
        u_stride: i32,
        v: *const u8,
        v_stride: i32,
        rgb: *mut u8,
        rgb_stride: i32,
        width: i32,
        height: i32,
    ) -> i32;
    fn rd_i444_bitrate(codec: *mut c_void, bitrate: i64);
    fn rd_i444_encode(
        codec: *mut c_void,
        pixels: *const u8,
        stride: i32,
        pts: i64,
        output: *mut c_void,
        callback: PacketCallback,
    ) -> i32;
    fn rd_i444_decode(
        codec: *mut c_void,
        data: *const u8,
        size: i32,
        output: *mut c_void,
        callback: FrameCallback,
    ) -> i32;
}

struct Codec(NonNull<c_void>);

impl Drop for Codec {
    fn drop(&mut self) {
        unsafe { rd_i444_free(self.0.as_ptr()) };
    }
}

pub(super) struct Encoder {
    codec: Codec,
    format: Format,
    backend: Backend,
    layout: EncodeYuvFormat,
    bitrate: u32,
}

impl Encoder {
    pub(super) fn from_config(config: &EncoderCfg) -> ResultType<Self> {
        let format = Format::from_config(config)
            .ok_or_else(|| anyhow!("invalid H.26x 4:4:4 encoder format"))?;
        let backend = format
            .backend()
            .ok_or_else(|| anyhow!("no verified H.26x 4:4:4 encoder"))?;
        match config {
            EncoderCfg::HWRAM(cfg) => Self::open(
                format,
                backend,
                cfg.width,
                cfg.height,
                cfg.quality,
                cfg.keyframe_interval,
            ),
            #[cfg(feature = "vram")]
            EncoderCfg::VRAM(cfg) => Self::open(
                format,
                backend,
                cfg.width,
                cfg.height,
                cfg.quality,
                cfg.keyframe_interval,
            ),
            _ => bail!("invalid H.26x 4:4:4 encoder settings"),
        }
    }

    fn open(
        format: Format,
        backend: Backend,
        w: usize,
        h: usize,
        ratio: f32,
        keyframe_interval: Option<usize>,
    ) -> ResultType<Self> {
        use std::convert::TryFrom;
        let width = i32::try_from(w)?;
        let height = i32::try_from(h)?;
        let stride = w.next_multiple_of(64);
        let stride_i32 = i32::try_from(stride)?;
        let plane = stride
            .checked_mul(h)
            .filter(|n| *n > 0 && *n <= i32::MAX as usize / 3)
            .ok_or_else(|| anyhow!("invalid H.26x 4:4:4 picture size"))?;
        let bitrate = Self::target_bitrate(format, w, h, ratio);
        let gop = keyframe_interval
            .unwrap_or(i32::MAX as usize)
            .min(i32::MAX as usize) as i32;
        let codec = unsafe {
            rd_i444_encoder(
                format.name(backend).as_ptr().cast(),
                width,
                height,
                (bitrate * 1000) as i32,
                gop,
            )
        };
        let codec = NonNull::new(codec)
            .ok_or_else(|| anyhow!("{backend:?} could not open {format:?} 4:4:4"))?;
        Ok(Self {
            codec: Codec(codec),
            format,
            backend,
            bitrate,
            layout: EncodeYuvFormat {
                pixfmt: Pixfmt::I444,
                w,
                h,
                stride: vec![stride_i32 as usize; 3],
                u: plane,
                v: plane * 2,
            },
        })
    }

    fn target_bitrate(format: Format, w: usize, h: usize, ratio: f32) -> u32 {
        HwRamEncoder::calc_bitrate(w, h, ratio, !format.is_hevc()).clamp(1, i32::MAX as u32 / 1000)
    }
}

impl EncoderApi for Encoder {
    fn new(config: EncoderCfg, _: bool) -> ResultType<Self> {
        Self::from_config(&config)
    }

    fn encode_to_message(&mut self, frame: EncodeInput, ms: i64) -> ResultType<VideoFrame> {
        let pixels = frame.yuv()?;
        if pixels.len() < self.layout.u * 3 {
            bail!("incomplete H.26x 4:4:4 frame");
        }
        let mut packets = Vec::<EncodedVideoFrame>::new();
        let result = unsafe {
            rd_i444_encode(
                self.codec.0.as_ptr(),
                pixels.as_ptr(),
                self.layout.stride[0] as i32,
                ms,
                (&mut packets as *mut Vec<EncodedVideoFrame>).cast(),
                write_packet,
            )
        };
        if result < 0 || packets.is_empty() {
            bail!("H.26x 4:4:4 encoder produced no frame ({result})");
        }
        let frames = EncodedVideoFrames {
            frames: packets.into(),
            i444: true,
            ..Default::default()
        };
        let mut message = VideoFrame::new();
        if self.format.is_hevc() {
            message.set_h265s(frames);
        } else {
            message.set_h264s(frames);
        }
        Ok(message)
    }

    fn yuvfmt(&self) -> EncodeYuvFormat {
        self.layout.clone()
    }

    #[cfg(feature = "vram")]
    fn input_texture(&self) -> bool {
        false
    }

    fn set_quality(&mut self, ratio: f32) -> ResultType<()> {
        self.bitrate = Self::target_bitrate(self.format, self.layout.w, self.layout.h, ratio);
        unsafe { rd_i444_bitrate(self.codec.0.as_ptr(), i64::from(self.bitrate) * 1000) };
        Ok(())
    }
    fn bitrate(&self) -> u32 {
        self.bitrate
    }
    fn support_changing_quality(&self) -> bool {
        true
    }
    fn latency_free(&self) -> bool {
        matches!(self.backend, Backend::Nvidia)
    }
    fn is_hardware(&self) -> bool {
        true
    }
    fn disable(&self) {
        self.format.disabled().store(true, Ordering::Relaxed);
    }
}

unsafe extern "C" fn write_packet(
    output: *mut c_void,
    bytes: *const u8,
    len: i32,
    pts: i64,
    key: i32,
) {
    if len > 0 && !bytes.is_null() {
        let packets = &mut *output.cast::<Vec<EncodedVideoFrame>>();
        packets.push(EncodedVideoFrame {
            data: Bytes::copy_from_slice(std::slice::from_raw_parts(bytes, len as usize)),
            key: key != 0,
            pts,
            ..Default::default()
        });
    }
}

#[derive(Default)]
struct HardwareDecodeBudget {
    previous_pts: Option<i64>,
    slow_frames: u8,
}

impl HardwareDecodeBudget {
    fn record(&mut self, pts: i64, elapsed: Duration) {
        let frame_interval = self.previous_pts.replace(pts)
            .and_then(|previous| pts.checked_sub(previous))
            .filter(|interval| (1..=250).contains(interval));
        if frame_interval.is_some_and(|ms| elapsed > Duration::from_millis(ms as u64 + 2)) {
            self.slow_frames = self.slow_frames.saturating_add(1);
        } else {
            self.slow_frames = 0;
        }
    }

    fn over_budget(&self) -> bool {
        self.slow_frames >= 4
    }
}

pub(super) struct Decoder(Codec, Option<HardwareDecodeBudget>);

impl Decoder {
    pub(super) fn new(format: Format) -> ResultType<Self> {
        let threads = realtime_codec_thread_num(8);
        let raw = unsafe { rd_i444_decoder(i32::from(format.is_hevc()), threads as i32) };
        let codec = NonNull::new(raw).ok_or_else(|| anyhow!("H.26x 4:4:4 decoder unavailable"))?;
        Ok(Self(Codec(codec), None))
    }

    pub(super) fn try_d3d11(format: Format) -> Option<Self> {
        if !format.is_hevc() {
            return None;
        }
        let raw = unsafe { rd_i444_d3d11_decoder(realtime_codec_thread_num(4) as i32) };
        NonNull::new(raw).map(|codec| Self(Codec(codec), Some(HardwareDecodeBudget::default())))
    }

    pub(super) fn is_hardware(&self) -> bool {
        self.1.is_some()
    }

    pub(super) fn over_budget(&self) -> bool {
        self.1.as_ref().is_some_and(HardwareDecodeBudget::over_budget)
    }

    pub(super) fn decode(
        &mut self,
        frames: &EncodedVideoFrames,
        rgb: &mut ImageRgb,
    ) -> ResultType<bool> {
        use std::convert::TryFrom;
        let started = self.1.as_ref().map(|_| Instant::now());
        let mut output = Decoded {
            codec: self.0 .0,
            rgb,
            rendered: false,
        };
        for frame in &frames.frames {
            if frame.data.is_empty() {
                bail!("empty H.26x 4:4:4 packet");
            }
            let size = i32::try_from(frame.data.len())?;
            let result = unsafe {
                rd_i444_decode(
                    self.0 .0.as_ptr(),
                    frame.data.as_ptr(),
                    size,
                    (&mut output as *mut Decoded).cast(),
                    render,
                )
            };
            if result < 0 {
                bail!("H.26x 4:4:4 decoding failed ({result})");
            }
        }
        if output.rendered {
            if let (Some(budget), Some(started), Some(packet)) =
                (self.1.as_mut(), started, frames.frames.last())
            {
                budget.record(packet.pts, started.elapsed());
            }
        }
        Ok(output.rendered)
    }
}

struct Decoded<'a> {
    codec: NonNull<c_void>,
    rgb: &'a mut ImageRgb,
    rendered: bool,
}

unsafe extern "C" fn render(
    output: *mut c_void,
    y: *const u8,
    y_stride: i32,
    u: *const u8,
    u_stride: i32,
    v: *const u8,
    v_stride: i32,
    width: i32,
    height: i32,
) -> i32 {
    if width <= 0
        || height <= 0
        || y.is_null()
        || u.is_null()
        || v.is_null()
        || [y_stride, u_stride, v_stride]
            .iter()
            .any(|stride| *stride < width)
    {
        return -1;
    }
    let output = &mut *output.cast::<Decoded>();
    let rgb = &mut output.rgb;
    let convert = match rgb.fmt() {
        ImageFormat::ARGB => I444ToARGB,
        ImageFormat::ABGR => I444ToABGR,
        _ => return -1,
    };
    let Some(stride) = (width as usize)
        .checked_mul(4)
        .and_then(|stride| stride.checked_next_multiple_of(rgb.align().max(1)))
    else {
        return -1;
    };
    let Some(len) = stride
        .checked_mul(height as usize)
        .filter(|n| *n <= i32::MAX as usize)
    else {
        return -1;
    };
    rgb.raw.resize(len, 0);
    let result = rd_i444_convert(
        output.codec.as_ptr(),
        convert,
        y,
        y_stride,
        u,
        u_stride,
        v,
        v_stride,
        rgb.raw.as_mut_ptr(),
        stride as i32,
        width,
        height,
    );
    if result == 0 {
        rgb.w = width as usize;
        rgb.h = height as usize;
        output.rendered = true;
    }
    result
}
