use hbb_common::{
    protobuf::Message as _,
    rendezvous_proto::{rendezvous_message, RendezvousMessage, TestNatRequest},
    timeout, ResultType, Stream,
};

/// A cold direct-only offer starts gathering before its punch request. Fetch the
/// signed observers up front, as a relay session would before an in-session upgrade.
pub(crate) async fn prepare_direct_ice(server: &str, key: &str) {
    if hbb_common::webrtc::WebRTCStream::has_expanded_udp_observer() {
        return;
    }
    let exchange = async {
        let mut socket = crate::p2p::connect_rendezvous(server, None, 1_500).await?;
        if !crate::secure_tcp_with_direct_permission(&mut socket, key, true).await? {
            return Ok(false);
        }
        confirm_signed_direct_permission(&mut socket).await
    };
    if !matches!(timeout(1_500, exchange).await, Ok(Ok(true))) {
        hbb_common::log::trace!("Direct ICE will use the configured STUN servers");
    }
}

/// Confirm the signed grant on its own connection before caching its observers.
/// hbbs keeps the connection open after this reserved request.
pub(crate) async fn confirm_signed_direct_permission(conn: &mut Stream) -> ResultType<bool> {
    if !conn.is_secured() {
        return Ok(false);
    }
    let mut request = RendezvousMessage::new();
    request.set_test_nat_request(TestNatRequest {
        serial: -604180,
        ..Default::default()
    });
    let result = timeout(1250, async {
        conn.send(&request).await?;
        let Some(Ok(bytes)) = conn.next().await else {
            return Ok(false);
        };
        let Ok(response) = RendezvousMessage::parse_from_bytes(&bytes) else {
            return Ok(false);
        };
        Ok(matches!(
            response.union,
            Some(rendezvous_message::Union::TestNatResponse(r)) if (1..=65535).contains(&r.port)
        ))
    })
    .await
    .unwrap_or(Ok(false));
    finish_signed_observer_exchange(conn, matches!(&result, Ok(true)));
    result
}

// The signed announcement can be replayed. Commit it only after the caller has
// authenticated a reply on this same connection with its fresh session keys.
pub(crate) fn finish_signed_observer_exchange(conn: &mut Stream, confirmed: bool) {
    if let Stream::Tcp(socket) = conn {
        let secured = socket.is_secured();
        if let Some((key, observers)) = socket.take_signed_observers() {
            if secured && confirmed {
                hbb_common::webrtc::WebRTCStream::remember_signed_observers(&key, &observers);
            }
        }
    }
}
