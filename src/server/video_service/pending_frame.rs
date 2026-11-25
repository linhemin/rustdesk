use std::collections::HashSet;

const MAX_VPX_RETRIES: usize = 100;
const MAX_HARDWARE_DRAIN_ATTEMPTS: u8 = 10;

#[derive(Debug)]
pub(super) struct FrameEncodeResult {
    pub(super) send_conn_ids: HashSet<i32>,
    pub(super) vpx_no_output: bool,
    pub(super) last_output_pts: Option<i64>,
    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    pub(super) encode_outcome: crate::video_diagnostics::EncodeOutcome,
    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    pub(super) encode_us: u64,
}

#[derive(Default)]
pub(super) struct PendingHardwareFrame {
    capture_pts: Option<i64>,
    attempts: u8,
}

impl PendingHardwareFrame {
    pub(super) fn on_capture(&mut self, pts: i64, output_pts: Option<i64>) {
        self.attempts = 0;
        self.capture_pts = Some(pts);
        self.on_output(output_pts);
    }

    pub(super) fn on_output(&mut self, output_pts: Option<i64>) {
        if self
            .capture_pts
            .zip(output_pts)
            .is_some_and(|(capture, output)| output >= capture)
        {
            self.capture_pts = None;
        }
    }

    pub(super) fn take_drain_attempt(&mut self) -> bool {
        if self.capture_pts.is_none() || self.attempts >= MAX_HARDWARE_DRAIN_ATTEMPTS {
            return false;
        }
        self.attempts += 1;
        true
    }
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

    #[test]
    fn delayed_hardware_stops_draining_as_soon_as_the_last_capture_is_sent() {
        let mut pending = PendingHardwareFrame::default();
        assert!(!pending.take_drain_attempt());
        pending.on_capture(33, Some(0));
        assert!(pending.take_drain_attempt());
        pending.on_output(Some(33));
        assert!(!pending.take_drain_attempt());
        pending.on_capture(66, Some(66));
        assert!(!pending.take_drain_attempt());
    }
}
