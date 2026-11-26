use super::{GenericService, VideoFrameController};
use base::message_proto::Message;
use hbb_common::{bail, ResultType};
use scrap::{codec::Encoder, record::Recorder, EncodeInput};
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

const MOTION_GAP: Duration = Duration::from_millis(100);
const MOTION_FRAMES: u8 = 4;
const QUIET_PERIOD: Duration = Duration::from_millis(350);
const MAX_SETTLE_WAIT: Duration = Duration::from_secs(10);
const QUALITY_FRAME_INTERVAL: Duration = Duration::from_millis(100);
const MAX_QUALITY_FRAMES: u8 = 4;

#[derive(Default)]
pub(super) struct SettledQuality {
    last_capture: Option<Instant>,
    moving_frames: u8,
    last_motion: Option<Instant>,
    latest_sent: bool,
    remaining: u8,
    next_frame: Option<Instant>,
}

impl SettledQuality {
    pub(super) fn on_capture(&mut self, now: Instant, sent: bool, refine_first_image: bool) {
        self.moving_frames = if self
            .last_capture
            .is_some_and(|last| now.saturating_duration_since(last) <= MOTION_GAP)
        {
            self.moving_frames.saturating_add(1)
        } else {
            1
        };
        if refine_first_image && self.last_capture.is_none() {
            self.last_motion = Some(now);
            self.remaining = 1;
        } else if self.moving_frames >= MOTION_FRAMES {
            self.last_motion = Some(now);
            self.remaining = MAX_QUALITY_FRAMES;
            self.next_frame = None;
        }
        self.last_capture = Some(now);
        self.latest_sent = sent;
    }

    pub(super) fn on_pending_output(&mut self) {
        self.latest_sent = true;
    }

    pub(super) fn waiting(&mut self, now: Instant) -> Option<Duration> {
        let waited = now.saturating_duration_since(self.last_motion?);
        if waited >= MAX_SETTLE_WAIT {
            self.last_motion = None;
            return None;
        }
        (self.latest_sent
            && now.saturating_duration_since(self.last_capture?) >= QUIET_PERIOD
            && !self.next_frame.is_some_and(|next| now < next))
        .then_some(waited)
    }

    pub(super) fn on_attempt(&mut self, now: Instant, sent: bool) {
        self.remaining = self.remaining.saturating_sub(1);
        if sent && self.remaining > 0 {
            self.next_frame = Some(now + QUALITY_FRAME_INTERVAL);
            return;
        }
        self.last_motion = None;
    }
}

pub(super) fn send(
    sp: &GenericService,
    encoder: &mut Encoder,
    yuv: &[u8],
    now: Instant,
    ms: i64,
    recorder: &Mutex<Option<Recorder>>,
    size: (usize, usize),
    frame_controller: &mut VideoFrameController,
) -> ResultType<bool> {
    let input = if !yuv.is_empty() {
        EncodeInput::YUV(yuv)
    } else {
        #[cfg(all(windows, feature = "vram"))]
        {
            if !encoder.input_texture() {
                return Ok(false);
            }
            EncodeInput::Repeat
        }
        #[cfg(not(all(windows, feature = "vram")))]
        {
            return Ok(false);
        }
    };
    sp.snapshot(|snapshot| {
        if snapshot.has_subscribes() {
            bail!("SWITCH");
        }
        Ok(())
    })?;
    let mut video = match encoder.encode_to_message(input, ms) {
        Ok(frame) if frame.union.is_some() => frame,
        Ok(_) => return Ok(false),
        Err(error) => {
            hbb_common::log::trace!("Settled quality frame did not encode: {error}");
            return Ok(false);
        }
    };
    video.display = frame_controller.display_idx as _;
    let mut message = Message::new();
    message.set_video_frame(video);
    if let Some(recorder) = recorder.lock().unwrap().as_mut() {
        recorder.write_message(&message, size.0, size.1);
    }
    let sent = sp.send_video_frame(message);
    let delivered = !sent.is_empty();
    frame_controller.set_send(now, sent);
    Ok(delivered)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_sends_a_bounded_quality_burst_after_motion() {
        let start = Instant::now();
        let mut settled = SettledQuality::default();
        for index in 0..4 {
            settled.on_capture(start + Duration::from_millis(index * 17), true, false);
        }
        assert!(settled
            .waiting(start + Duration::from_millis(300))
            .is_none());
        let first = start + Duration::from_millis(405);
        for index in 0..u32::from(MAX_QUALITY_FRAMES) {
            let next = first + QUALITY_FRAME_INTERVAL * index;
            assert!(settled.waiting(next).is_some());
            settled.on_attempt(next, true);
            assert!(settled.waiting(next + Duration::from_millis(1)).is_none());
        }
        for second in 1..10 {
            let frame = start + Duration::from_secs(second);
            settled.on_capture(frame, true, false);
            assert!(settled.waiting(frame + QUIET_PERIOD).is_none());
        }
    }

    #[test]
    fn best_can_refine_the_quiet_first_image_once_without_continuous_motion() {
        let start = Instant::now();
        let mut settled = SettledQuality::default();
        settled.on_capture(start, false, true);
        assert!(settled.waiting(start + QUIET_PERIOD).is_none());
        settled.on_pending_output();
        assert!(settled.waiting(start + QUIET_PERIOD).is_some());
        settled.on_attempt(start + QUIET_PERIOD, true);
        assert!(settled.waiting(start + Duration::from_secs(1)).is_none());
    }
}
