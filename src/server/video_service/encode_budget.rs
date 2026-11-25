use std::time::Duration;

#[derive(Default)]
pub(super) struct EncodeBudget {
    frames: u32,
    sent: u32,
    work_us: u64,
    slowest: [u64; 3],
}

pub(super) struct FrameHealth {
    pub(super) min_fps: u32,
    pub(super) on_target: bool,
    pub(super) headroom: bool,
    pub(super) overloaded: bool,
}

impl EncodeBudget {
    pub(super) fn record(&mut self, work_us: u64, sent: bool) {
        self.frames += 1;
        self.sent += u32::from(sent);
        self.work_us += work_us;
        if work_us > self.slowest[0] {
            self.slowest[0] = work_us;
            self.slowest.sort_unstable();
        }
    }

    pub(super) fn frame_health(
        &self,
        elapsed: Duration,
        fps_limit: u32,
        source_updates: u32,
    ) -> FrameHealth {
        let seconds = elapsed.as_secs_f64();
        let updates = source_updates.max(self.frames);
        let demand = ((f64::from(updates) / seconds).round() as u32).min(fps_limit);
        let active = updates >= 3 && demand >= 3;
        let min_fps = if active { (demand * 9).div_ceil(10) } else { 0 };
        let sent_fps = (f64::from(self.sent) / seconds).round() as u32;
        let on_target = sent_fps >= min_fps;
        let budget_us = 1_000_000.0 / f64::from(demand.max(1));
        let busy = self.work_us as f64 / (f64::from(self.frames.max(1)) * budget_us);
        FrameHealth {
            min_fps,
            on_target: active && on_target,
            headroom: active && on_target && busy < 0.85 && (self.slowest[0] as f64) < budget_us,
            overloaded: active && !on_target && (busy >= 0.90 || self.sent < self.frames),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn measure(frames: u32, sent: u32, updates: u32, work_us: u64) -> FrameHealth {
        let mut sample = EncodeBudget::default();
        for frame in 0..frames {
            sample.record(work_us, frame < sent);
        }
        sample.frame_health(Duration::from_secs(1), 60, updates)
    }

    #[test]
    fn idle_and_30_fps_sources_do_not_inherit_a_60_fps_limit() {
        for frames in [0, 1] {
            let idle = measure(frames, frames, frames, 20_000);
            assert_eq!(idle.min_fps, 0);
            assert!(!idle.headroom && !idle.overloaded);
        }
        let video = measure(30, 30, 30, 16_000);
        assert_eq!(video.min_fps, 27);
        assert!(video.headroom && !video.overloaded);
    }

    #[test]
    fn lost_fresh_frames_or_processing_overload_prevent_bitrate_growth() {
        assert!(measure(60, 60, 60, 4_000).headroom);
        assert!(!measure(60, 60, 60, 15_200).headroom);
        assert!(measure(30, 30, 60, 22_500).overloaded);
        assert!(measure(30, 16, 30, 16_000).overloaded);
        for (slow_frames, headroom) in [(1, true), (3, false)] {
            let mut sample = EncodeBudget::default();
            for frame in 0..60 {
                sample.record(if frame < slow_frames { 32_000 } else { 4_000 }, true);
            }
            let health = sample.frame_health(Duration::from_secs(1), 60, 60);
            assert_eq!(health.headroom, headroom);
            assert!(!health.overloaded);
        }
    }
}
