use std::collections::HashSet;

const MAX_VPX_RETRIES: usize = 100;

#[derive(Debug)]
pub(super) struct FrameEncodeResult {
    pub(super) send_conn_ids: HashSet<i32>,
    pub(super) vpx_no_output: bool,
    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    pub(super) encode_outcome: crate::video_diagnostics::EncodeOutcome,
    pub(super) encode_us: u64,
}

#[derive(Default)]
pub(super) struct PendingVpxFrame {
    retries_left: usize,
}

impl PendingVpxFrame {
    pub(super) fn on_capture(&mut self, no_output: bool) {
        self.retries_left = if no_output { MAX_VPX_RETRIES } else { 0 };
    }

    pub(super) fn take_retry(&mut self) -> bool {
        if self.retries_left == 0 {
            return false;
        }
        self.retries_left -= 1;
        true
    }

    pub(super) fn on_retry(&mut self, no_output: bool) {
        if !no_output {
            self.retries_left = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_capture_does_not_resend_a_frame_after_output() {
        let mut pending = PendingVpxFrame::default();
        pending.on_capture(false);
        assert!(!pending.take_retry());
    }

    #[test]
    fn dropped_vpx_frame_retries_only_until_delivered_or_replaced() {
        let mut pending = PendingVpxFrame::default();
        pending.on_capture(true);
        assert!(pending.take_retry());
        pending.on_retry(true);
        assert!(pending.take_retry());
        pending.on_retry(false);
        assert!(!pending.take_retry());

        pending.on_capture(true);
        pending.on_capture(false);
        assert!(!pending.take_retry());
    }
}
