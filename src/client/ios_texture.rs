use base::message_proto::{video_frame, SupportedDecoding, VideoFrame};
use scrap::CodecFormat;

extern "C" {
    fn rustdesk_ios_texture_capabilities() -> u32;
    fn rustdesk_ios_texture_clear_frame(display: i32);
    fn rustdesk_ios_texture_decode(codec: u32, display: i32, bytes: *const u8, length: usize, pts: i64, key: bool) -> i32;
}

pub(super) enum DecodeStatus {
    Frame,
    Pending,
    Failed,
}

pub(super) fn clear_frame(display: usize) {
    unsafe { rustdesk_ios_texture_clear_frame(display as i32) }
}

pub(super) fn with_native_decoders(
    mut decoding: SupportedDecoding,
    unsupported: &[CodecFormat],
) -> SupportedDecoding {
    let native = unsafe { rustdesk_ios_texture_capabilities() };
    let h264 = native & 1 != 0 && !unsupported.contains(&CodecFormat::H264);
    let h265 = native & 2 != 0 && !unsupported.contains(&CodecFormat::H265);
    if h264 { decoding.ability_h264 = 1; }
    if h265 { decoding.ability_h265 = 1; }
    decoding
}

pub(super) fn decode(frame: &VideoFrame) -> DecodeStatus {
    let (codec, packets) = match frame.union.as_ref() {
        Some(video_frame::Union::H264s(packets)) => (1, packets),
        Some(video_frame::Union::H265s(packets)) => (2, packets),
        _ => return DecodeStatus::Failed,
    };
    let mut current = DecodeStatus::Pending;
    for packet in &packets.frames {
        if packet.data.is_empty() {
            continue;
        }
        let status = unsafe {
            rustdesk_ios_texture_decode(
                codec, frame.display, packet.data.as_ptr(), packet.data.len(), packet.pts, packet.key,
            )
        };
        match status {
            1 => current = DecodeStatus::Frame,
            0 => {}
            _ => return DecodeStatus::Failed,
        }
    }
    current
}
