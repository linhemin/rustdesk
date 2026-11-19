use super::*;
use hbb_common::{
    sodiumoxide::crypto::box_,
    tcp::{Encrypt, FramedStream},
    tokio::{io::AsyncReadExt, net::TcpListener},
};

fn response(peer: SocketAddr) -> RendezvousMessage {
    let mut msg = RendezvousMessage::new();
    msg.set_punch_hole_response(PunchHoleResponse {
        socket_addr: AddrMangle::encode(peer).into(),
        ..Default::default()
    });
    msg
}

#[test]
fn only_an_eligible_cross_family_public_tcp_reply_can_trigger_a_retry() {
    let v4 = "192.0.2.1:12000".parse().unwrap();
    let v6 = "[2001:db8::1]:12000".parse().unwrap();
    assert_eq!(
        mismatched_public_tcp_family(true, v6, &response(v4)),
        Some(true)
    );
    assert_eq!(
        mismatched_public_tcp_family(true, v4, &response(v6)),
        Some(false)
    );
    assert_eq!(mismatched_public_tcp_family(true, v6, &response(v6)), None);
    assert_eq!(mismatched_public_tcp_family(false, v6, &response(v4)), None);
    for option in ["lan", "udp", "webrtc", "symmetric"] {
        let mut msg = response(v4);
        let Some(rendezvous_message::Union::PunchHoleResponse(ph)) = &mut msg.union else {
            unreachable!()
        };
        match option {
            "lan" => ph.set_is_local(true),
            "udp" => ph.is_udp = true,
            "webrtc" => ph.webrtc_sdp_answer = "answer".to_string(),
            _ => ph.set_nat_type(NatType::SYMMETRIC),
        }
        assert_eq!(mismatched_public_tcp_family(true, v6, &msg), None);
    }
}

#[test]
fn alternate_requires_a_matching_endpoint_or_an_explicit_decision() {
    let v4 = "192.0.2.2:12000".parse().unwrap();
    assert!(usable_family_reply(&response(v4), true));
    assert!(!usable_family_reply(&response(v4), false));
    assert!(!usable_family_reply(
        &response("0.0.0.0:0".parse().unwrap()),
        true
    ));
    let mut msg = RendezvousMessage::new();
    msg.set_punch_hole_response(PunchHoleResponse::default());
    assert!(!usable_family_reply(&msg, true));
    msg.set_punch_hole_response(PunchHoleResponse {
        failure: punch_hole_response::Failure::OFFLINE.into(),
        ..Default::default()
    });
    assert!(usable_family_reply(&msg, true));
    msg.set_relay_response(RelayResponse::default());
    assert!(!usable_family_reply(&msg, true));
    msg.set_relay_response(RelayResponse {
        refuse_reason: "server policy".to_owned(),
        ..Default::default()
    });
    assert!(usable_family_reply(&msg, true));
}

#[tokio::test]
async fn ipv6_controller_repeats_classic_request_on_signed_ipv4_socket() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let v4 = listener.local_addr().unwrap();
    let host = format!("localhost:{}", v4.port());
    let (pk, sk) = sign::gen_keypair();
    let v6 = "[2001:db8::1]:40000".parse().unwrap();
    let family = mismatched_public_tcp_family(true, v6, &response(v4)).unwrap();
    let serve = tokio::spawn(async move {
        let (tcp, source) = listener.accept().await.unwrap();
        assert!(source.is_ipv4());
        let mut conn = FramedStream::from(tcp, source);
        let (ephemeral, secret) = box_::gen_keypair();
        let mut msg = RendezvousMessage::new();
        msg.set_key_exchange(KeyExchange {
            keys: vec![sign::sign(&ephemeral.0, &sk).into()],
            ..Default::default()
        });
        conn.send(&msg).await.unwrap();
        let bytes = conn.next_timeout(3000).await.unwrap().unwrap();
        let reply = RendezvousMessage::parse_from_bytes(&bytes).unwrap();
        let Some(rendezvous_message::Union::KeyExchange(ex)) = reply.union else {
            panic!("classic punch sent before signed key exchange");
        };
        conn.set_key(Encrypt::decode(&ex.keys[1], &ex.keys[0], &secret).unwrap());
        let bytes = conn.next_timeout(3000).await.unwrap().unwrap();
        let packet = RendezvousMessage::parse_from_bytes(&bytes).unwrap();
        let Some(rendezvous_message::Union::PunchHoleRequest(req)) = packet.union else {
            panic!("missing classic TCP request");
        };
        assert_eq!(req.id, "test-peer");
        assert!(req.webrtc_sdp_offer.is_empty());
        conn.send(&response(v4)).await.unwrap();
    });
    let mut request = RendezvousMessage::new();
    request.set_punch_hole_request(PunchHoleRequest {
        id: "test-peer".into(),
        ..Default::default()
    });
    let (conn, reply) = retry_tcp_punch_family(&host, &crate::encode64(pk.0), family, &request)
        .await
        .unwrap();
    assert!(conn.is_secured());
    assert!(conn.local_addr().is_ipv4());
    assert!(usable_family_reply(&reply, family));
    serve.await.unwrap();
}

#[tokio::test]
async fn cancelling_during_key_exchange_closes_socket_without_sending_punch() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let host = listener.local_addr().unwrap().to_string();
    let retry = tokio::spawn(async move {
        let (pk, _) = sign::gen_keypair();
        let key = crate::encode64(pk.0);
        retry_tcp_punch_family(&host, &key, true, &RendezvousMessage::new()).await
    });
    let (mut socket, _) = tokio::time::timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    retry.abort();
    assert!(retry.await.is_err());
    let mut byte = [0u8; 1];
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), socket.read(&mut byte))
            .await
            .unwrap()
            .unwrap(),
        0
    );
}

#[tokio::test]
async fn different_server_key_never_receives_the_new_request() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let host = listener.local_addr().unwrap().to_string();
    let (expected, _) = sign::gen_keypair();
    let (_, unexpected) = sign::gen_keypair();
    let serve = tokio::spawn(async move {
        let (tcp, source) = listener.accept().await.unwrap();
        let mut conn = FramedStream::from(tcp, source);
        let ephemeral = box_::gen_keypair().0;
        let mut msg = RendezvousMessage::new();
        msg.set_key_exchange(KeyExchange {
            keys: vec![sign::sign(&ephemeral.0, &unexpected).into()],
            ..Default::default()
        });
        conn.send(&msg).await.unwrap();
        assert!(conn.next_timeout(1000).await.is_none());
    });
    let result = retry_tcp_punch_family(
        &host,
        &crate::encode64(expected.0),
        true,
        &RendezvousMessage::new(),
    )
    .await;
    assert!(result
        .err()
        .unwrap()
        .to_string()
        .contains("Signature mismatch"));
    serve.await.unwrap();
}
