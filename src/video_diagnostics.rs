use base::message_proto::{
    video_frame::Union, TestDelay, VideoDiagnosticSample, VideoDiagnostics, VideoFrame,
};
use hbb_common::{lazy_static, log, ResultType};
use std::{
    collections::HashMap,
    io::ErrorKind,
    mem,
    sync::{
        atomic::{AtomicU64, Ordering::Relaxed},
        Mutex,
    },
    time::{Duration, Instant},
};

const SAMPLE_MAX_AGE: Duration = Duration::from_secs(3);
const SAMPLE_MAX_BYTES: usize = 2048;

lazy_static::lazy_static! {
    static ref CAPTURE_SAMPLES: Mutex<HashMap<usize, Sample>> = Default::default();
}

struct Sample {
    at: Instant,
    report: VideoDiagnosticSample,
}

impl Sample {
    fn new(metrics: String) -> Self {
        log::info!("video_diag_v1 {metrics}");
        Self {
            at: Instant::now(),
            report: VideoDiagnosticSample {
                time_unix_ms: hbb_common::get_time(),
                metrics,
                ..Default::default()
            },
        }
    }

    fn fresh(&self) -> Option<VideoDiagnosticSample> {
        (self.at.elapsed() <= SAMPLE_MAX_AGE).then(|| self.report.clone())
    }
}

pub(crate) fn peer_report(display: usize, send: &SendStats) -> Option<VideoDiagnostics> {
    let capture = CAPTURE_SAMPLES
        .lock()
        .unwrap()
        .get(&display)
        .and_then(Sample::fresh);
    let send = send.last.as_ref().and_then(Sample::fresh);
    if capture.is_none() && send.is_none() {
        return None;
    }
    Some(VideoDiagnostics {
        capture: capture.into(),
        send: send.into(),
        ..Default::default()
    })
}

pub(crate) fn clear_capture(display: usize) {
    CAPTURE_SAMPLES.lock().unwrap().remove(&display);
}

fn valid_metrics(metrics: &str, prefix: &str) -> bool {
    metrics.len() <= SAMPLE_MAX_BYTES
        && metrics.strip_prefix(prefix).is_some_and(|fields| {
            fields.split(' ').all(|field| {
                field.split_once('=').is_some_and(|(key, value)| {
                    !key.is_empty()
                        && key.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
                        && !value.is_empty()
                        && value
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b == b'.')
                })
            })
        })
}

fn log_peer_sample(sample: &VideoDiagnosticSample, prefix: &str) {
    if sample.time_unix_ms > 0 && valid_metrics(&sample.metrics, prefix) {
        log::info!(
            "video_diag_peer_v1 host_time_ms={} {}",
            sample.time_unix_ms,
            sample.metrics
        );
    }
}

pub(crate) fn receive_peer_report(delay: &mut TestDelay, enabled: bool) {
    let incoming = delay.video_diagnostics.take();
    delay.request_video_diagnostics = enabled && !delay.from_client;
    if let Some(report) = incoming.filter(|_| delay.request_video_diagnostics) {
        if let Some(capture) = report.capture.as_ref() {
            log_peer_sample(capture, "role=capture ");
        }
        if let Some(send) = report.send.as_ref() {
            log_peer_sample(send, "role=send ");
        }
    }
}

pub(crate) fn frame_count(frame: &VideoFrame) -> usize {
    match &frame.union {
        Some(
            Union::Vp8s(v) | Union::Vp9s(v) | Union::Av1s(v) | Union::H264s(v) | Union::H265s(v),
        ) => v.frames.len(),
        Some(_) => 1,
        None => 0,
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum EncodeOutcome {
    Frames(usize),
    VpxNoOutput,
    Error,
}

impl EncodeOutcome {
    pub(crate) fn from_result(result: &ResultType<VideoFrame>) -> Self {
        match result {
            Ok(frame) => Self::Frames(frame_count(frame)),
            Err(error) if error.is::<scrap::VpxNoOutput>() => Self::VpxNoOutput,
            Err(_) => Self::Error,
        }
    }
}

#[derive(Default)]
pub(crate) struct EncodeStats {
    calls: usize,
    frames: usize,
    vpx_no_output: usize,
    empty_output: usize,
    errors: usize,
    max_us: u64,
    total_us: u64,
}

impl EncodeStats {
    pub(crate) fn record(&mut self, outcome: EncodeOutcome, elapsed_us: u64) {
        self.calls += 1;
        match outcome {
            EncodeOutcome::Frames(0) => self.empty_output += 1,
            EncodeOutcome::Frames(frames) => self.frames += frames,
            EncodeOutcome::VpxNoOutput => self.vpx_no_output += 1,
            EncodeOutcome::Error => self.errors += 1,
        }
        self.max_us = self.max_us.max(elapsed_us);
        self.total_us += elapsed_us;
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
    capture_total_us: u64,
    convert_max_us: u64,
    convert_total_us: u64,
    pub(crate) encode: EncodeStats,
    settled_quality_frames: usize,
    ack_wait_max_us: u64,
    ack_wait_total_us: u64,
    ack_missed: usize,
}

impl CaptureStats {
    pub(crate) fn capture(
        &mut self,
        gdi: bool,
        result: Result<bool, ErrorKind>,
        elapsed: Duration,
    ) {
        let elapsed = elapsed.as_micros() as u64;
        self.capture_max_us = self.capture_max_us.max(elapsed);
        self.capture_total_us += elapsed;
        match (gdi, result) {
            (false, Ok(true)) => self.dxgi_frames += 1,
            (true, Ok(true)) => self.gdi_frames += 1,
            (false, Ok(false) | Err(ErrorKind::WouldBlock)) => self.dxgi_no_frame += 1,
            (true, Ok(false) | Err(ErrorKind::WouldBlock)) => self.gdi_no_frame += 1,
            (_, Err(_)) => self.capture_errors += 1,
        }
    }

    pub(crate) fn conversion(&mut self, elapsed: Duration) {
        let elapsed = elapsed.as_micros() as u64;
        self.convert_max_us = self.convert_max_us.max(elapsed);
        self.convert_total_us += elapsed;
    }

    pub(crate) fn settled_quality_refresh(&mut self) {
        self.settled_quality_frames += 1;
    }

    pub(crate) fn ack_wait(&mut self, elapsed: Duration, missed: usize) {
        let elapsed = elapsed.as_micros() as u64;
        self.ack_wait_max_us = self.ack_wait_max_us.max(elapsed);
        self.ack_wait_total_us += elapsed;
        self.ack_missed += missed;
    }

    pub(crate) fn report(
        &mut self,
        display: usize,
        gdi: bool,
        codec: scrap::CodecFormat,
        hardware: bool,
        target_kbps: u32,
        size: (usize, usize),
        target_period: Duration,
        period: Duration,
    ) {
        let t = mem::take(self);
        let dxgi_updates = scrap::dxgi::take_desktop_updates();
        let dxgi_prefetched = scrap::dxgi::take_prefetched_frames();
        let settled_quality_frames = t.settled_quality_frames;
        let (width, height) = size;
        let encoding = if hardware { "gpu" } else { "cpu" };
        let metrics = format!(
            "role=capture display={display} interval_ms={} backend={} target_fps={:.1} dxgi_frames={} dxgi_no_frame={} gdi_frames={} gdi_no_frame={} capture_errors={} capture_max_us={} convert_max_us={} encode_calls={} encoded_frames={} refresh_frames=0 encode_max_us={} ack_wait_max_us={} ack_missed={} codec={codec:?} encoding={encoding} target_kbps={target_kbps} encode_vpx_no_output={} encode_empty_output={} encode_errors={} refresh_calls=0 refresh_vpx_no_output=0 refresh_empty_output=0 refresh_errors=0 refresh_encode_max_us=0 width={width} height={height} capture_total_us={} convert_total_us={} encode_total_us={} refresh_encode_total_us=0 ack_wait_total_us={} dxgi_updates={dxgi_updates} dxgi_prefetched={dxgi_prefetched} settled_quality_frames={settled_quality_frames}",
            period.as_millis(), if gdi { "gdi" } else { "dxgi" },
            1.0 / target_period.as_secs_f64(), t.dxgi_frames, t.dxgi_no_frame, t.gdi_frames,
            t.gdi_no_frame, t.capture_errors, t.capture_max_us, t.convert_max_us, t.encode.calls,
            t.encode.frames, t.encode.max_us, t.ack_wait_max_us, t.ack_missed,
            t.encode.vpx_no_output, t.encode.empty_output, t.encode.errors,
            t.capture_total_us, t.convert_total_us, t.encode.total_us, t.ack_wait_total_us,
        );
        let sample = Sample::new(metrics);
        CAPTURE_SAMPLES.lock().unwrap().insert(display, sample);
    }
}

pub(crate) struct SendStats {
    since: Instant,
    frames: usize,
    queue_max: usize,
    queue_age_max_us: u64,
    send_max_us: u64,
    discarded: usize,
    last: Option<Sample>,
}

impl Default for SendStats {
    fn default() -> Self {
        Self {
            since: Instant::now(),
            frames: 0,
            queue_max: 0,
            queue_age_max_us: 0,
            send_max_us: 0,
            discarded: 0,
            last: None,
        }
    }
}

impl SendStats {
    pub(crate) fn discarded(&mut self, frames: usize) {
        self.discarded += frames;
    }

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
        if t.frames > 0 || t.discarded > 0 {
            self.last = Some(Sample::new(format!(
                "role=send conn={conn} interval_ms={} client_ack={client_ack} written_frames={} queue_max={} queue_age_max_us={} stream_write_max_us={} queue_discarded_frames={}",
                elapsed.as_millis(), t.frames, t.queue_max, t.queue_age_max_us, t.send_max_us, t.discarded,
            )));
        } else {
            self.last = t.last;
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

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::{EncodedVideoFrame, EncodedVideoFrames};
    use hbb_common::protobuf::Message as _;

    #[test]
    fn diagnostic_samples_round_trip_without_echoing_remote_content() {
        let wire = TestDelay {
            video_diagnostics: Some(VideoDiagnostics {
                capture: Some(VideoDiagnosticSample {
                    time_unix_ms: 123,
                    metrics: "role=capture display=0 codec=VP8 encode_vpx_no_output=12".to_owned(),
                    ..Default::default()
                })
                .into(),
                ..Default::default()
            })
            .into(),
            ..Default::default()
        }
        .write_to_bytes()
        .unwrap();

        let mut probe = TestDelay::parse_from_bytes(&wire).unwrap();
        let capture = probe.video_diagnostics.capture.as_ref().unwrap();
        assert!(valid_metrics(&capture.metrics, "role=capture "));
        assert!(!valid_metrics(
            "role=capture display=0\nforged=1",
            "role=capture "
        ));
        receive_peer_report(&mut probe, true);
        assert!(probe.request_video_diagnostics);
        assert!(probe.video_diagnostics.is_none());

        let mut probe = TestDelay::parse_from_bytes(&wire).unwrap();
        receive_peer_report(&mut probe, false);
        assert!(!probe.request_video_diagnostics);
        assert!(probe.video_diagnostics.is_none());
    }

    #[test]
    fn counts_vpx_no_output_separately_from_encoding_errors() {
        let mut frame = VideoFrame::new();
        frame.set_vp8s(EncodedVideoFrames {
            frames: vec![EncodedVideoFrame::new()],
            ..Default::default()
        });
        let results = [
            Ok(frame),
            Ok(VideoFrame::new()),
            Err(scrap::VpxNoOutput.into()),
            Err(hbb_common::anyhow::anyhow!("encoder failure")),
        ];
        let mut stats = EncodeStats::default();
        for result in &results {
            stats.record(EncodeOutcome::from_result(result), 100);
        }
        assert_eq!(stats.calls, 4);
        assert_eq!(stats.frames, 1);
        assert_eq!(stats.vpx_no_output, 1);
        assert_eq!(stats.empty_output, 1);
        assert_eq!(stats.errors, 1);
    }
}
