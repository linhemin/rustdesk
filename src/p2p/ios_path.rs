use hbb_common::tokio::sync::watch;
use std::sync::OnceLock;

fn changes() -> &'static watch::Sender<()> {
    static CHANGES: OnceLock<watch::Sender<()>> = OnceLock::new();
    CHANGES.get_or_init(|| watch::channel(()).0)
}

pub(crate) fn subscribe() -> watch::Receiver<()> {
    changes().subscribe()
}

#[no_mangle]
pub extern "C" fn rustdesk_ios_p2p_wake() {
    changes().send_replace(());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn foreground_signal_wakes_existing_session_observers() {
        let controller = subscribe();
        rustdesk_ios_p2p_wake();
        assert!(controller.has_changed().unwrap());
    }
}
