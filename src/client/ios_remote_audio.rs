#[cfg(target_os = "ios")]
use hbb_common::{bail, ResultType};
use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};

pub(crate) const REPORT_OPTION: &str = "ios-remote-audio-report";

#[derive(Default)]
pub(crate) struct Progress {
    pub(super) formats: AtomicUsize,
    pub(super) packets: AtomicUsize,
    pub(super) muted_packets: AtomicUsize,
    pub(super) decoded: AtomicUsize,
    pub(super) callbacks: AtomicUsize,
    pub(super) pcm_samples: AtomicUsize,
    pub(super) audible_callbacks: AtomicUsize,
}

impl Progress {
    pub(crate) fn report(&self) -> String {
        format!(
            "RustDesk iPhone audio\nformats={} received_packets={} muted_packets={} decoded_packets={} output_callbacks={} output_samples={} nonzero_callbacks={}",
            self.formats.load(Relaxed),
            self.packets.load(Relaxed),
            self.muted_packets.load(Relaxed),
            self.decoded.load(Relaxed),
            self.callbacks.load(Relaxed),
            self.pcm_samples.load(Relaxed),
            self.audible_callbacks.load(Relaxed),
        )
    }
}

#[cfg(target_os = "ios")]
pub(super) fn activate() -> ResultType<()> {
    extern "C" {
        fn rustdesk_ios_activate_remote_audio() -> i32;
    }
    let status = unsafe { rustdesk_ios_activate_remote_audio() };
    if status != 0 {
        bail!("iPhone audio session activation failed ({status})");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_distinguishes_packet_receipt_from_playback() {
        let progress = Progress::default();
        progress.formats.store(1, Relaxed);
        progress.packets.store(8, Relaxed);
        progress.decoded.store(3, Relaxed);
        assert_eq!(
            progress.report(),
            "RustDesk iPhone audio\nformats=1 received_packets=8 muted_packets=0 decoded_packets=3 output_callbacks=0 output_samples=0 nonzero_callbacks=0"
        );
    }
}
