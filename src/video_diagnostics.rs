use base::message_proto::{video_frame::Union, VideoFrame};
use hbb_common::log;
use std::{
    io::ErrorKind,
    mem,
    sync::atomic::{AtomicU64, Ordering::Relaxed},
    time::{Duration, Instant},
};

pub(crate) fn frame_count(frame: &VideoFrame) -> usize {
    match &frame.union {
        Some(
            Union::Vp8s(v) | Union::Vp9s(v) | Union::Av1s(v) | Union::H264s(v) | Union::H265s(v),
        ) => v.frames.len(),
        Some(_) => 1,
        None => 0,
    }
}

#[derive(Default)]
pub(crate) struct CaptureStats {
    pub(crate) dxgi_frames: usize,
    pub(crate) dxgi_no_frame: usize,
    pub(crate) gdi_frames: usize,
    pub(crate) gdi_no_frame: usize,
    capture_errors: usize,
    capture_max_us: u64,
    pub(crate) convert_max_us: u64,
    encode_calls: usize,
    encoded: usize,
    pub(crate) repeat_encoded: usize,
    encode_max_us: u64,
    pub(crate) ack_wait_max_us: u64,
    pub(crate) ack_missed: usize,
}

impl CaptureStats {
    pub(crate) fn encoded(&mut self, frames: usize, elapsed_us: u64) {
        self.encode_calls += 1;
        self.encoded += frames;
        self.encode_max_us = self.encode_max_us.max(elapsed_us);
    }

    pub(crate) fn capture(
        &mut self,
        gdi: bool,
        result: Result<bool, ErrorKind>,
        elapsed: Duration,
    ) {
        self.capture_max_us = self.capture_max_us.max(elapsed.as_micros() as u64);
        match (gdi, result) {
            (false, Ok(true)) => self.dxgi_frames += 1,
            (true, Ok(true)) => self.gdi_frames += 1,
            (false, Ok(false) | Err(ErrorKind::WouldBlock)) => self.dxgi_no_frame += 1,
            (true, Ok(false) | Err(ErrorKind::WouldBlock)) => self.gdi_no_frame += 1,
            (_, Err(_)) => self.capture_errors += 1,
        }
    }

    pub(crate) fn report(
        &mut self,
        display: usize,
        gdi: bool,
        target_period: Duration,
        period: Duration,
    ) {
        let t = mem::take(self);
        log::info!(
            "video_diag_v1 role=capture display={display} interval_ms={} backend={} target_fps={:.1} dxgi_frames={} dxgi_no_frame={} gdi_frames={} gdi_no_frame={} capture_errors={} capture_max_us={} convert_max_us={} encode_calls={} encoded_frames={} refresh_frames={} encode_max_us={} ack_wait_max_us={} ack_missed={}",
            period.as_millis(), if gdi { "gdi" } else { "dxgi" },
            1.0 / target_period.as_secs_f64(), t.dxgi_frames, t.dxgi_no_frame, t.gdi_frames,
            t.gdi_no_frame, t.capture_errors, t.capture_max_us, t.convert_max_us, t.encode_calls,
            t.encoded, t.repeat_encoded, t.encode_max_us, t.ack_wait_max_us, t.ack_missed
        );
    }
}

pub(crate) struct SendStats {
    since: Instant,
    frames: usize,
    queue_max: usize,
    queue_age_max_us: u64,
    send_max_us: u64,
}

impl Default for SendStats {
    fn default() -> Self {
        Self {
            since: Instant::now(),
            frames: 0,
            queue_max: 0,
            queue_age_max_us: 0,
            send_max_us: 0,
        }
    }
}

impl SendStats {
    pub(crate) fn record(&mut self, frames: usize, depth: usize, age: Duration, send: Duration) {
        self.frames += frames;
        self.queue_max = self.queue_max.max(depth);
        self.queue_age_max_us = self.queue_age_max_us.max(age.as_micros() as u64);
        self.send_max_us = self.send_max_us.max(send.as_micros() as u64);
    }

    pub(crate) fn report(&mut self, conn: i32, client_ack: bool) {
        let elapsed = self.since.elapsed();
        if elapsed < Duration::from_secs(1) {
            return;
        }
        let t = mem::take(self);
        if t.frames > 0 {
            log::info!(
                "video_diag_v1 role=send conn={conn} interval_ms={} client_ack={client_ack} written_frames={} queue_max={} queue_age_max_us={} stream_write_max_us={}",
                elapsed.as_millis(), t.frames, t.queue_max, t.queue_age_max_us, t.send_max_us
            );
        }
    }
}

#[derive(Default)]
pub(crate) struct ReceiveStats {
    pub(crate) received: AtomicU64,
    pub(crate) decode_queue_max: AtomicU64,
    pub(crate) overwritten: AtomicU64,
    pub(crate) decoded: AtomicU64,
    pub(crate) decode_errors: AtomicU64,
    pub(crate) decode_max_us: AtomicU64,
    pub(crate) ui_submitted: AtomicU64,
}

impl ReceiveStats {
    pub(crate) fn report(&self, interval_ms: u128, transport: &str) {
        log::info!(
            "video_diag_v1 role=receive transport={transport} interval_ms={interval_ms} received_frames={} decode_queue_max={} overwritten={} decoded_frames={} decode_errors={} decode_max_us={} ui_submitted={}",
            self.received.swap(0, Relaxed), self.decode_queue_max.swap(0, Relaxed),
            self.overwritten.swap(0, Relaxed), self.decoded.swap(0, Relaxed),
            self.decode_errors.swap(0, Relaxed), self.decode_max_us.swap(0, Relaxed),
            self.ui_submitted.swap(0, Relaxed)
        );
    }
}
