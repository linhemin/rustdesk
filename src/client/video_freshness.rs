use std::time::{Duration, Instant};

// A decoder that never catches up would otherwise freeze the picture: every frame it finishes
// already has a successor waiting.
const MAX_HOLD: Duration = Duration::from_millis(50);
const DEFAULT_FRAME_INTERVAL: Duration = Duration::from_millis(16);

/// Preserve timely frames when decoding and reception briefly overlap. Frames already
/// queued in a burst are decoded for their references while presentation catches up.
#[derive(Default)]
pub(super) struct Freshness {
    skipping_since: Option<Instant>,
    previous_pts: Option<i64>,
}

impl Freshness {
    pub(super) fn show(
        &mut self,
        following_frame_was_queued: bool,
        pending: usize,
        pts: Option<i64>,
        decode_time: Duration,
        now: Instant,
    ) -> bool {
        let frame_interval = pts
            .zip(self.previous_pts)
            .and_then(|(pts, previous)| pts.checked_sub(previous))
            .filter(|ms| (4..=250).contains(ms))
            .map_or(DEFAULT_FRAME_INTERVAL, |ms| {
                Duration::from_millis(ms as u64)
            })
            .min(MAX_HOLD);
        self.previous_pts = pts;
        let behind = pending > 0
            && (following_frame_was_queued || pending > 1 || decode_time >= frame_interval);
        if !behind {
            self.skipping_since = None;
            return true;
        }

        let since = *self.skipping_since.get_or_insert(now);
        let stale = now.saturating_duration_since(since) < MAX_HOLD;
        if !stale {
            self.skipping_since = None;
        }
        !stale
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(arrived: &[i32], decode: Duration) -> Vec<i32> {
        let mut freshness = Freshness::default();
        let mut now = Instant::now();
        let mut shown = Vec::new();
        for (index, frame) in arrived.iter().enumerate() {
            let pending = arrived.len() - index - 1;
            now += decode;
            if freshness.show(pending > 0, pending, None, decode, now) {
                shown.push(*frame);
            }
        }
        shown
    }

    #[test]
    fn a_single_successor_arriving_during_a_timely_decode_does_not_hide_the_frame() {
        let mut freshness = Freshness::default();
        let mut now = Instant::now();
        let decode = Duration::from_millis(7);
        for pts in [0, 16, 33, 50] {
            now += decode;
            assert!(freshness.show(false, 1, Some(pts), decode, now));
        }
    }

    #[test]
    fn a_late_decode_with_a_waiting_successor_drops_the_current_frame() {
        let mut freshness = Freshness::default();
        let now = Instant::now();
        let decode = Duration::from_millis(10);
        assert!(freshness.show(false, 0, Some(0), decode, now));
        assert!(!freshness.show(false, 1, Some(8), decode, now + decode));
    }

    #[test]
    fn frames_arriving_together_show_only_the_newest() {
        assert_eq!(shown(&[1], Duration::from_millis(5)), [1]);
        assert_eq!(shown(&[1, 2, 3, 4], Duration::from_millis(5)), [4]);
    }

    #[test]
    fn a_backlog_slower_to_decode_than_to_arrive_still_moves_the_picture() {
        let frames: Vec<i32> = (1..=12).collect();
        assert_eq!(shown(&frames, Duration::from_millis(20)), [4, 8, 12]);
    }
}
