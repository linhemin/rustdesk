use super::*;
use base::message_proto::{CodecAbility, SupportedDecoding};

// Single 64x64 red Annex B frames, generated with libx264 and libx265.
const H264_444: &[u8] = &[
    0x00, 0x00, 0x00, 0x01, 0x67, 0xf4, 0x00, 0x0a, 0x91, 0x96, 0x84, 0x26, 0xc0, 0x44, 0x00, 0x00,
    0x03, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0xf2, 0x3c, 0x48, 0x9a, 0x80, 0x00, 0x00, 0x00, 0x01,
    0x68, 0xce, 0x0f, 0x19, 0x20, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x3a, 0x24, 0x50, 0x00, 0x10,
    0xc7, 0x8a, 0x00, 0x02, 0x07, 0xb1, 0x40, 0x00, 0x43, 0xca, 0x4f, 0x27, 0x93, 0xd7, 0xaf, 0x5e,
    0xbd, 0x7a, 0xf5, 0xeb, 0xd7, 0xaf, 0x5e, 0xbe,
];

const H265_444: &[u8] = &[
    0x00, 0x00, 0x00, 0x01, 0x40, 0x01, 0x0c, 0x01, 0xff, 0xff, 0x04, 0x08, 0x00, 0x00, 0x03, 0x00,
    0x9e, 0x08, 0x00, 0x00, 0x03, 0x00, 0x00, 0x1e, 0x92, 0x80, 0x90, 0x00, 0x00, 0x00, 0x01, 0x42,
    0x01, 0x01, 0x04, 0x08, 0x00, 0x00, 0x03, 0x00, 0x9e, 0x08, 0x00, 0x00, 0x03, 0x00, 0x00, 0x1e,
    0x90, 0x04, 0x10, 0x20, 0xb2, 0xc9, 0x52, 0x49, 0x95, 0xe0, 0x2d, 0x01, 0x00, 0x00, 0x03, 0x00,
    0x01, 0x00, 0x00, 0x03, 0x00, 0x3c, 0x08, 0x00, 0x00, 0x00, 0x01, 0x44, 0x01, 0xc1, 0x72, 0x86,
    0x0c, 0x42, 0x24, 0x00, 0x00, 0x01, 0x28, 0x01, 0xaf, 0x0a, 0x60, 0xfa, 0x36, 0x82, 0x3f, 0xf5,
    0x70, 0x9f, 0x2e, 0xa0, 0x33, 0x38, 0x60, 0x7d, 0x3c, 0xf0,
];

const H264_420: &[u8] = &[
    0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0xc0, 0x0a, 0xda, 0x10, 0x9b, 0x01, 0x10, 0x00, 0x00, 0x03,
    0x00, 0x10, 0x00, 0x00, 0x03, 0x03, 0xc8, 0xf1, 0x22, 0x6a, 0x00, 0x00, 0x00, 0x01, 0x68, 0xce,
    0x0f, 0xc8, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x3a, 0x11, 0x8a, 0x00, 0x02, 0x18, 0xf1, 0xc0,
    0x00, 0x40, 0xf6, 0x38, 0x00, 0x08, 0x79, 0x49, 0xc9, 0xc9, 0xd7, 0x5d, 0x75, 0xd7, 0x5d, 0x75,
    0xd7, 0x5e,
];

fn frames(data: &'static [u8]) -> EncodedVideoFrames {
    EncodedVideoFrames {
        frames: vec![EncodedVideoFrame {
            data: Bytes::from_static(data),
            key: true,
            ..Default::default()
        }],
        i444: true,
        ..Default::default()
    }
}

#[test]
fn parallel_conversion_matches_serial_with_stride_and_uneven_rows() {
    let width = 1281;
    let height = 723;
    let stride = 1344;
    let rgb_stride = 5184;
    let plane = |shift: usize| {
        (0..(stride * height) as usize)
            .map(|pixel| ((pixel / 13 + shift) % 224 + 16) as u8)
            .collect::<Vec<_>>()
    };
    let (y, u, v) = (plane(0), plane(60), plane(190));
    let codec = Codec(NonNull::new(unsafe { rd_i444_decoder(1, 4) }).unwrap());
    for convert in [I444ToARGB as Convert444, I444ToABGR as Convert444] {
        let mut expected = vec![0xCC; (rgb_stride * height) as usize];
        let mut output = expected.clone();
        unsafe {
            assert_eq!(
                convert(
                    y.as_ptr(), stride, u.as_ptr(), stride, v.as_ptr(), stride,
                    expected.as_mut_ptr(), rgb_stride, width, height,
                ),
                0
            );
            assert_eq!(
                rd_i444_convert(
                    codec.0.as_ptr(), convert, y.as_ptr(), stride, u.as_ptr(), stride,
                    v.as_ptr(), stride, output.as_mut_ptr(), rgb_stride, width, height,
                ),
                0
            );
        }
        assert!(output == expected);
    }
}

#[test]
fn decodes_h264_and_h265_444_and_rejects_mislabeled_420() {
    for (codec, bytes) in [(Format::H264, H264_444), (Format::H265, H265_444)] {
        let mut rgb = ImageRgb::new(ImageFormat::ABGR, 32);
        let decoded = Decoder::new(codec)
            .unwrap()
            .decode(&frames(bytes), &mut rgb)
            .unwrap();
        assert!(decoded, "{:?}", codec);
        assert_eq!((rgb.w, rgb.h, rgb.raw.len()), (64, 64, 64 * 64 * 4));
        assert!(rgb.raw[0] > 220 && rgb.raw[1] < 20 && rgb.raw[2] < 20);
    }

    let mut rgb = ImageRgb::new(ImageFormat::ABGR, 1);
    assert!(Decoder::new(Format::H264)
        .unwrap()
        .decode(&frames(H264_420), &mut rgb)
        .is_err());
    assert!(rgb.raw.is_empty());
}

#[test]
#[ignore = "Requires Intel Quick Sync hardware and drivers"]
fn hevc_444_uses_d3d11_and_matches_software() {
    for (width, height) in [(1920, 1080), (3840, 2160)] {
        compare_d3d11_decode(width, height);
    }
}

#[test]
fn hardware_decode_budget_uses_real_frame_cadence() {
    let mut budget = HardwareDecodeBudget::default();
    for frame in 0..8 {
        budget.record(frame * 100, Duration::from_millis(36));
    }
    assert!(!budget.over_budget());
    for frame in 0..4 {
        budget.record(716 + frame * 16, Duration::from_millis(36));
    }
    assert!(budget.over_budget());
}

fn compare_d3d11_decode(width: usize, height: usize) {
    let mut encoder =
        Encoder::open(Format::H265, Backend::QuickSync, width, height, 1.0, None).unwrap();
    let mut pixels = vec![128; encoder.layout.u * 3];
    let mut decoder = Decoder::new(Format::H265).unwrap();
    let mut hardware = Decoder::try_d3d11(Format::H265).unwrap();
    let mut rgb = ImageRgb::new(ImageFormat::ABGR, 1);
    let mut hardware_rgb = ImageRgb::new(ImageFormat::ABGR, 1);
    let mut decoded = 0;
    let mut software_time = std::time::Duration::ZERO;
    let mut hardware_time = std::time::Duration::ZERO;
    for frame in 0..30 {
        pixels[frame..encoder.layout.u].fill(50 + frame as u8);
        pixels[encoder.layout.u..encoder.layout.v].fill(90);
        pixels[encoder.layout.v..].fill(200);
        let encoded = encoder
            .encode_to_message(EncodeInput::YUV(&pixels), (frame * 1000 / 60) as i64)
            .unwrap();
        assert!(encoded.h265s().i444);
        let started = std::time::Instant::now();
        let rendered = decoder.decode(encoded.h265s(), &mut rgb).unwrap();
        software_time += started.elapsed();
        let started = std::time::Instant::now();
        let hardware_rendered = hardware.decode(encoded.h265s(), &mut hardware_rgb).unwrap();
        hardware_time += started.elapsed();
        assert_eq!(hardware_rendered, rendered, "frame {frame}");
        if rendered {
            assert_eq!((rgb.w, rgb.h), (width, height));
            assert_eq!((hardware_rgb.w, hardware_rgb.h), (width, height));
            assert_eq!(rgb.raw.len(), hardware_rgb.raw.len());
            assert!(
                rgb.raw.iter().zip(&hardware_rgb.raw).all(|(cpu, gpu)| cpu.abs_diff(*gpu) <= 2),
                "4:4:4 pixels differ on frame {}", frame
            );
            decoded += 1;
        }
    }
    assert_eq!(decoded, 30);
    println!("{width}×{height} 4:4:4 mean decode and conversion: CPU {:?}, D3D11 {:?}",
        software_time / decoded, hardware_time / decoded);
}

#[test]
fn software_only_decoder_accepts_h264_420() {
    let mut encoded = frames(H264_420);
    encoded.i444 = false;
    let frame = base::message_proto::video_frame::Union::H264s(encoded);
    let mut decoder = crate::codec::Decoder::with_backend(CodecFormat::H264, None, true);
    let mut rgb = ImageRgb::new(ImageFormat::ABGR, 1);
    let mut chroma = None;
    let mut pixelbuffer = true;
    assert!(decoder.handle_video_frame(
        &frame, &mut rgb, &mut Default::default(), &mut pixelbuffer, &mut chroma,
    ).unwrap());
    assert!(pixelbuffer);
    assert_eq!(chroma, Some(base::message_proto::Chroma::I420));
    assert_eq!(decoder.decoder_backend().map(|backend| backend.name()), Some("cpu"));
}

#[test]
fn legacy_peer_requires_420_and_support_is_per_codec() {
    let mut peer = SupportedDecoding {
        ability_h264: 1,
        ability_h265: 1,
        ..Default::default()
    };
    assert!(!Format::H264.peer_supports(&peer));
    assert!(!Format::H265.peer_supports(&peer));

    peer.i444 = Some(CodecAbility {
        h265: true,
        ..Default::default()
    })
    .into();
    assert!(!Format::H264.peer_supports(&peer));
    assert!(Format::H265.peer_supports(&peer));
    peer.ability_h265 = 0;
    assert!(!Format::H265.peer_supports(&peer));
}
