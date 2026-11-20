use std::time::{Duration, Instant};

/// Measure only complete video messages delivered to this viewer. File transfers
/// and audio must not make a shared connection look fast enough for a higher rung.
#[derive(Default)]
pub(super) struct DeliveryWindow {
    start: Option<Instant>,
    bytes: u64,
    frames: u32,
    queued: u32,
}

impl DeliveryWindow {
    pub(super) fn frame(&mut self, bytes: usize, frames: usize, queue_depth: usize) {
        if frames == 0 {
            return;
        }
        let frames = frames.min(u32::MAX as usize) as u32;
        self.bytes = self.bytes.saturating_add(bytes as u64);
        self.frames = self.frames.saturating_add(frames);
        if queue_depth >= 3 {
            self.queued = self.queued.saturating_add(frames);
        }
    }

    pub(super) fn finish(&mut self, now: Instant) -> Option<(u32, u32, u32)> {
        let old = std::mem::replace(
            self,
            Self {
                start: Some(now),
                ..Default::default()
            },
        );
        let elapsed = now.checked_duration_since(old.start?)?;
        if old.frames == 0
            || !(Duration::from_millis(500)..=Duration::from_secs(5)).contains(&elapsed)
        {
            return None;
        }
        let ms = elapsed.as_millis() as u64;
        Some((
            (old.bytes.saturating_mul(8) / ms).min(u32::MAX as u64) as u32,
            (u64::from(old.frames) * 1000 / ms).min(1000) as u32,
            (u64::from(old.queued) * 100 / u64::from(old.frames)) as u32,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn samples_only_video_and_discards_stale_or_empty_windows() {
        let mut w = DeliveryWindow::default();
        let start = Instant::now();
        w.frame(500_000, 1, 9);
        assert_eq!(w.finish(start), None);
        for n in 0..30 {
            w.frame(20_000, 1, if n < 3 { 4 } else { 0 });
        }
        assert_eq!(
            w.finish(start + Duration::from_secs(1)),
            Some((4800, 30, 10))
        );
        assert_eq!(w.finish(start + Duration::from_secs(2)), None);
        w.frame(4000, 1, 0);
        assert_eq!(w.finish(start + Duration::from_secs(10)), None);
    }
}
