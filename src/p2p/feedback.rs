use base::config::keys::OPTION_RECORD_P2P_DIAGNOSTICS;
use hbb_common::{
    config::{Config, RENDEZVOUS_PORT},
    rendezvous_proto::{P2pFeedback, RendezvousMessage},
    socket_client,
    tokio::{self, sync::Semaphore},
};

pub(crate) fn submit(report: P2pFeedback) {
    static SEND: Semaphore = Semaphore::const_new(1);
    if crate::get_local_option(OPTION_RECORD_P2P_DIAGNOSTICS) != "Y" {
        return;
    }
    let server = Config::get_option("custom-rendezvous-server");
    let key = Config::get_option("key");
    if server.is_empty() || key.is_empty() {
        return;
    }
    let Ok(permit) = SEND.try_acquire() else { return };
    tokio::spawn(async move {
        let _permit = permit;
        let exchange = async {
            let target = crate::check_port(&server, RENDEZVOUS_PORT);
            let mut conn = socket_client::connect_tcp(target.as_str(), 1_500).await?;
            if crate::secure_tcp_with_feedback_permission(&mut conn, &key).await?
                && crate::get_local_option(OPTION_RECORD_P2P_DIAGNOSTICS) == "Y"
            {
                let mut message = RendezvousMessage::new();
                message.set_p2p_feedback(report);
                conn.send(&message).await?;
            }
            Ok::<_, hbb_common::anyhow::Error>(())
        };
        if !matches!(hbb_common::timeout(3_000, exchange).await, Ok(Ok(()))) {
            hbb_common::log::trace!("P2P feedback upload unavailable");
        }
    });
}
