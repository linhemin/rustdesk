use base::message_proto::VideoFrame;
use crossbeam_queue::ArrayQueue;
use std::time::{Duration, Instant};

// A decoder that never catches up would otherwise freeze the picture: every frame it finishes
// already has a successor waiting.
const MAX_HOLD: Duration = Duration::from_millis(50);

/// Frames that arrive together (a retransmitted packet releases everything held behind it) are
/// all decoded, because each one is the reference for the next, but only the newest is shown.
#[derive(Default)]
pub(super) struct Freshness {
    skipping_since: Option<Instant>,
}

impl Freshness {
    /// Whether to show the frame just decoded. `queue` holds the frames received after it.
    pub(super) fn show(&mut self, queue: &ArrayQueue<VideoFrame>, now: Instant) -> bool {
        let since = *self.skipping_since.get_or_insert(now);
        let stale = !queue.is_empty() && now.saturating_duration_since(since) < MAX_HOLD;
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
        let queue = ArrayQueue::new(arrived.len());
        for display in arrived {
            let frame = VideoFrame {
                display: *display,
                ..Default::default()
            };
            assert!(queue.push(frame).is_ok());
        }
        let mut freshness = Freshness::default();
        let mut now = Instant::now();
        let mut shown = Vec::new();
        while let Some(frame) = queue.pop() {
            now += decode;
            if freshness.show(&queue, now) {
                shown.push(frame.display);
            }
        }
        shown
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
