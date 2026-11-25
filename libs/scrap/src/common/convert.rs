#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(non_upper_case_globals)]
#![allow(improper_ctypes)]
#![allow(dead_code)]

include!(concat!(env!("OUT_DIR"), "/yuv_ffi.rs"));

use rayon::prelude::*;
use std::sync::{Mutex, OnceLock};

#[cfg(not(target_os = "ios"))]
use crate::PixelBuffer;
use crate::{generate_call_macro, EncodeYuvFormat, TraitPixelBuffer};
use hbb_common::{bail, log, ResultType};

generate_call_macro!(call_yuv, false);

pub(super) type PlanarToRgb = unsafe extern "C" fn(
    *const u8,
    i32,
    *const u8,
    i32,
    *const u8,
    i32,
    *mut u8,
    i32,
    i32,
    i32,
) -> i32;
pub(super) type BiplanarToRgb =
    unsafe extern "C" fn(*const u8, i32, *const u8, i32, *mut u8, i32, i32, i32) -> i32;

#[derive(Clone, Copy)]
pub(super) enum YuvToRgb {
    Planar(PlanarToRgb, bool),
    Nv12(BiplanarToRgb),
}

struct RgbSource {
    convert: YuvToRgb,
    planes: [*const u8; 3],
    stride: [i32; 3],
    width: i32,
    dst_stride: i32,
}

// The conversion borrows the input planes read-only and joins every stripe before returning.
unsafe impl Sync for RgbSource {}

impl RgbSource {
    unsafe fn rows(&self, dst: &mut [u8], first: usize, count: i32) -> i32 {
        let plane = |index: usize, row: usize| {
            if row == 0 {
                self.planes[index]
            } else {
                self.planes[index].offset(row as isize * self.stride[index] as isize)
            }
        };
        let y = plane(0, first);
        match self.convert {
            YuvToRgb::Planar(convert, subsampled) => {
                let chroma_row = if subsampled { first / 2 } else { first };
                convert(
                    y,
                    self.stride[0],
                    plane(1, chroma_row),
                    self.stride[1],
                    plane(2, chroma_row),
                    self.stride[2],
                    dst.as_mut_ptr(),
                    self.dst_stride,
                    self.width,
                    count,
                )
            }
            YuvToRgb::Nv12(convert) => convert(
                y,
                self.stride[0],
                plane(1, first / 2),
                self.stride[1],
                dst.as_mut_ptr(),
                self.dst_stride,
                self.width,
                count,
            ),
        }
    }

    unsafe fn convert(&self, dst: &mut [u8], height: i32, pool: Option<&rayon::ThreadPool>) -> i32 {
        let Some(pool) = pool else {
            return self.rows(dst, 0, height);
        };
        let stride = self.dst_stride as usize;
        // I420 and NV12 stripes must begin on whole chroma rows.
        let rows = (height as usize)
            .div_ceil(pool.current_num_threads())
            .next_multiple_of(2);
        pool.install(|| {
            dst[..stride * height as usize]
                .par_chunks_mut(stride * rows)
                .enumerate()
                .map(|(index, stripe)| {
                    self.rows(stripe, index * rows, (stripe.len() / stride) as i32)
                })
                .find_any(|result| *result != 0)
                .unwrap_or(0)
        })
    }
}

pub(super) unsafe fn convert_yuv_to_rgb(
    convert: YuvToRgb,
    planes: [*const u8; 3],
    stride: [i32; 3],
    dst: &mut [u8],
    dst_stride: i32,
    width: i32,
    height: i32,
) -> i32 {
    static POOL: OnceLock<Option<rayon::ThreadPool>> = OnceLock::new();
    static ACTIVE: Mutex<()> = Mutex::new(());
    let source = RgbSource {
        convert,
        planes,
        stride,
        width,
        dst_stride,
    };
    let can_split = width > 0
        && height >= 4
        && i64::from(width) * i64::from(height) >= 1920 * 1080
        && dst_stride > 0
        && (dst_stride as usize)
            .checked_mul(height as usize)
            .is_some_and(|len| len <= dst.len())
        && stride[0] > 0
        && stride[1] > 0
        && (matches!(convert, YuvToRgb::Nv12(_)) || stride[2] > 0);
    if can_split {
        // Concurrent sessions can convert on their own decoder thread while the pool is in use.
        if let Ok(_active) = ACTIVE.try_lock() {
            let pool = POOL.get_or_init(|| {
                let threads = crate::codec::realtime_codec_thread_num(4);
                if threads < 2 {
                    return None;
                }
                match rayon::ThreadPoolBuilder::new().num_threads(threads).build() {
                    Ok(pool) => Some(pool),
                    Err(err) => {
                        log::warn!("Could not start video conversion workers: {err}");
                        None
                    }
                }
            });
            return source.convert(dst, height, pool.as_ref());
        }
    }
    source.rows(dst, 0, height)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parallel_yuv_conversion_preserves_chroma_and_padded_rgb_rows() {
        let (width, height, stride, rgb_stride) = (1921, 1081, 1984, 7744);
        let plane = |stride: i32, rows: i32, offset: usize| {
            (0..(stride * rows) as usize)
                .map(|i| (16 + (i / 7 + offset) % 220) as u8)
                .collect::<Vec<_>>()
        };
        let y = plane(stride, height, 0);
        let u = plane(stride, height, 60);
        let v = plane(stride, height, 140);
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(4)
            .build()
            .unwrap();
        for convert in [
            YuvToRgb::Planar(I420ToABGR, true),
            YuvToRgb::Planar(I444ToARGB, false),
            YuvToRgb::Nv12(NV12ToARGB),
        ] {
            let source = RgbSource {
                convert,
                planes: [y.as_ptr(), u.as_ptr(), v.as_ptr()],
                stride: [stride; 3],
                width,
                dst_stride: rgb_stride,
            };
            let mut serial = vec![0xCC; (rgb_stride * height) as usize];
            let mut parallel = serial.clone();
            unsafe {
                assert_eq!(source.convert(&mut serial, height, None), 0);
                assert_eq!(source.convert(&mut parallel, height, Some(&pool)), 0);
            }
            assert!(parallel == serial);
        }
    }
}

#[cfg(not(target_os = "ios"))]
pub fn convert_to_yuv(
    captured: &PixelBuffer,
    dst_fmt: EncodeYuvFormat,
    dst: &mut Vec<u8>,
    mid_data: &mut Vec<u8>,
) -> ResultType<()> {
    let src = captured.data();
    let src_stride = captured.stride();
    let src_pixfmt = captured.pixfmt();
    let src_width = captured.width();
    let src_height = captured.height();
    if src_width > dst_fmt.w || src_height > dst_fmt.h {
        bail!(
            "src rect > dst rect: ({src_width}, {src_height}) > ({},{})",
            dst_fmt.w,
            dst_fmt.h
        );
    }
    if src_pixfmt == crate::Pixfmt::BGRA
        || src_pixfmt == crate::Pixfmt::RGBA
        || src_pixfmt == crate::Pixfmt::RGB565LE
    {
        // stride is calculated, not real, so we need to check it
        if src_stride[0] < src_width * src_pixfmt.bytes_per_pixel() {
            bail!(
                "src_stride too small: {} < {}",
                src_stride[0],
                src_width * src_pixfmt.bytes_per_pixel()
            );
        }
        if src.len() < src_stride[0] * src_height {
            bail!(
                "wrong src len, {} < {} * {}",
                src.len(),
                src_stride[0],
                src_height
            );
        }
    }
    let align = |x: usize| (x + 63) / 64 * 64;
    let unsupported = format!(
        "unsupported pixfmt conversion: {src_pixfmt:?} -> {:?}",
        dst_fmt.pixfmt
    );

    match (src_pixfmt, dst_fmt.pixfmt) {
        (crate::Pixfmt::BGRA, crate::Pixfmt::I420)
        | (crate::Pixfmt::RGBA, crate::Pixfmt::I420)
        | (crate::Pixfmt::RGB565LE, crate::Pixfmt::I420) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_uv = dst_fmt.stride[1];
            dst.resize(dst_fmt.h * dst_stride_y * 2, 0); // waste some memory to ensure memory safety
            let dst_y = dst.as_mut_ptr();
            let dst_u = dst[dst_fmt.u..].as_mut_ptr();
            let dst_v = dst[dst_fmt.v..].as_mut_ptr();
            let f = match src_pixfmt {
                crate::Pixfmt::BGRA => ARGBToI420,
                crate::Pixfmt::RGBA => ABGRToI420,
                crate::Pixfmt::RGB565LE => RGB565ToI420,
                _ => bail!(unsupported),
            };
            call_yuv!(f(
                src.as_ptr(),
                src_stride[0] as _,
                dst_y,
                dst_stride_y as _,
                dst_u,
                dst_stride_uv as _,
                dst_v,
                dst_stride_uv as _,
                src_width as _,
                src_height as _,
            ));
        }
        (crate::Pixfmt::BGRA, crate::Pixfmt::NV12)
        | (crate::Pixfmt::RGBA, crate::Pixfmt::NV12)
        | (crate::Pixfmt::RGB565LE, crate::Pixfmt::NV12) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_uv = dst_fmt.stride[1];
            dst.resize(
                align(dst_fmt.h) * (align(dst_stride_y) + align(dst_stride_uv / 2)),
                0,
            );
            let dst_y = dst.as_mut_ptr();
            let dst_uv = dst[dst_fmt.u..].as_mut_ptr();
            let (input, input_stride) = match src_pixfmt {
                crate::Pixfmt::BGRA => (src.as_ptr(), src_stride[0]),
                crate::Pixfmt::RGBA => (src.as_ptr(), src_stride[0]),
                crate::Pixfmt::RGB565LE => {
                    let mid_stride = src_width * 4;
                    mid_data.resize(mid_stride * src_height, 0);
                    call_yuv!(RGB565ToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        mid_stride as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), mid_stride)
                }
                _ => bail!(unsupported),
            };
            let f = match src_pixfmt {
                crate::Pixfmt::BGRA => ARGBToNV12,
                crate::Pixfmt::RGBA => ABGRToNV12,
                crate::Pixfmt::RGB565LE => ARGBToNV12,
                _ => bail!(unsupported),
            };
            call_yuv!(f(
                input,
                input_stride as _,
                dst_y,
                dst_stride_y as _,
                dst_uv,
                dst_stride_uv as _,
                src_width as _,
                src_height as _,
            ));
        }
        (crate::Pixfmt::BGRA, crate::Pixfmt::I444)
        | (crate::Pixfmt::RGBA, crate::Pixfmt::I444)
        | (crate::Pixfmt::RGB565LE, crate::Pixfmt::I444) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_u = dst_fmt.stride[1];
            let dst_stride_v = dst_fmt.stride[2];
            dst.resize(
                align(dst_fmt.h)
                    * (align(dst_stride_y) + align(dst_stride_u) + align(dst_stride_v)),
                0,
            );
            let dst_y = dst.as_mut_ptr();
            let dst_u = dst[dst_fmt.u..].as_mut_ptr();
            let dst_v = dst[dst_fmt.v..].as_mut_ptr();
            let (input, input_stride) = match src_pixfmt {
                crate::Pixfmt::BGRA => (src.as_ptr(), src_stride[0]),
                crate::Pixfmt::RGBA => {
                    mid_data.resize(src.len(), 0);
                    call_yuv!(ABGRToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        src_stride[0] as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), src_stride[0])
                }
                crate::Pixfmt::RGB565LE => {
                    let mid_stride = src_width * 4;
                    mid_data.resize(mid_stride * src_height, 0);
                    call_yuv!(RGB565ToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        mid_stride as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), mid_stride)
                }
                _ => bail!(unsupported),
            };

            call_yuv!(ARGBToI444(
                input,
                input_stride as _,
                dst_y,
                dst_stride_y as _,
                dst_u,
                dst_stride_u as _,
                dst_v,
                dst_stride_v as _,
                src_width as _,
                src_height as _,
            ));
        }
        _ => {
            bail!(unsupported);
        }
    }
    Ok(())
}

#[cfg(not(target_os = "ios"))]
pub fn convert(captured: &PixelBuffer, pixfmt: crate::Pixfmt, dst: &mut Vec<u8>) -> ResultType<()> {
    if captured.pixfmt() == pixfmt {
        dst.extend_from_slice(captured.data());
        return Ok(());
    }

    let src = captured.data();
    let src_stride = captured.stride();
    let src_pixfmt = captured.pixfmt();
    let src_width = captured.width();
    let src_height = captured.height();

    let unsupported = format!(
        "unsupported pixfmt conversion: {src_pixfmt:?} -> {:?}",
        pixfmt
    );

    match (src_pixfmt, pixfmt) {
        (crate::Pixfmt::BGRA, crate::Pixfmt::RGBA) | (crate::Pixfmt::RGBA, crate::Pixfmt::BGRA) => {
            dst.resize(src.len(), 0);
            call_yuv!(ABGRToARGB(
                src.as_ptr(),
                src_stride[0] as _,
                dst.as_mut_ptr(),
                src_stride[0] as _,
                src_width as _,
                src_height as _,
            ));
        }
        _ => {
            bail!(unsupported);
        }
    }
    Ok(())
}
