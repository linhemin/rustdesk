use std::time::Duration;

#[derive(Default)]
pub(super) struct EncodeBudget {
    frames: u32,
    encode_us: u64,
}

impl EncodeBudget {
    pub(super) fn record(&mut self, encode_us: u64) {
        self.frames += 1;
        self.encode_us += encode_us;
    }

    pub(super) fn misses_target(&self, elapsed: Duration, frame_period: Duration) -> bool {
        let expected_frames = elapsed.as_secs_f64() / frame_period.as_secs_f64();
        let fresh_frames = f64::from(self.frames);
        // An idle or source-limited desktop can miss its target with spare encoder time.
        fresh_frames >= (expected_frames * 0.25).max(6.0)
            && fresh_frames < expected_frames * 0.9
            && self.encode_us as f64 >= fresh_frames * frame_period.as_micros() as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn misses_target(frames: u32, frame_period: Duration, encode_us: u64) -> bool {
        let mut sample = EncodeBudget::default();
        for _ in 0..frames {
            sample.record(encode_us);
        }
        sample.misses_target(Duration::from_secs(1), frame_period)
    }

    #[test]
    fn sustained_slow_encoding_at_half_the_requested_fps_backs_off() {
        assert!(misses_target(31, Duration::from_secs(1) / 60, 22_500));
    }

    #[test]
    fn frames_at_display_cadence_and_idle_frames_keep_their_bitrate() {
        let frame_period = Duration::from_secs(1) / 60;
        assert!(!misses_target(60, frame_period, 15_200));
        assert!(!misses_target(31, frame_period, 13_900));
        assert!(!misses_target(31, frame_period, 3_100));
        assert!(!misses_target(1, frame_period, 15_200));
    }
}
