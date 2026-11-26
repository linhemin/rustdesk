use super::{Client, PeerConnection};
use hbb_common::{
    bail,
    config::RELAY_PORT,
    rendezvous_proto::{ConnType, RegionalRelaySample, RelayResponse},
    ResultType,
};
use std::sync::OnceLock;

pub(super) async fn open(
    peer: &str,
    key: &str,
    conn_type: ConnType,
    ipv4: bool,
    reply: RelayResponse,
    rendezvous: String,
) -> ResultType<PeerConnection> {
    let authority = crate::get_rs_pk(key);
    let signed = reply.pk().to_vec();
    if !authority
        .and_then(|pk| crate::decode_id_pk(&signed, &pk).ok())
        .is_some_and(|(id, _)| id == peer)
    {
        bail!("Relay startup has no verified peer identity");
    }
    let (mut stream, label) =
        Client::create_relay(peer, reply.uuid, reply.relay_server, key, conn_type, ipv4).await?;
    let identity = Client::secure_connection(peer, signed, key, &mut stream).await?;
    if identity.is_none() || !stream.is_secured() {
        bail!("Relay peer authentication did not complete");
    }
    Ok((
        (stream, false, identity, None, label),
        (reply.feedback, rendezvous),
        false,
    ))
}

#[derive(Default)]
pub(super) struct RelayStart {
    requested: OnceLock<()>,
    accepted: OnceLock<String>,
    failed_relay: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        config::Config,
        protobuf::Message as _,
        rendezvous_proto::{IdPk, RendezvousMessage},
        sodiumoxide::crypto::sign,
        tokio::{self, net::TcpListener},
        Stream,
    };

    #[test]
    fn a_failed_bootstrap_retries_ordinary_punch_with_the_other_measured_region() {
        let first = RelayStart::default();
        assert!(first.request());
        assert!(!first.request());
        first.accept("tokyo.example:21117");
        let retry = first.ordinary_retry();
        assert!(!retry.request());
        let samples = ["tokyo.example", "fuzhou.example"]
            .into_iter()
            .map(|name| RegionalRelaySample {
                relay_server: name.into(),
                connect_ms: 55,
                ..Default::default()
            })
            .collect();
        let remaining = retry.remaining(samples);
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].relay_server, "fuzhou.example");
    }

    #[tokio::test]
    #[cfg(not(target_os = "ios"))]
    async fn acknowledged_startup_pairs_the_requested_relay_and_verifies_the_host() {
        let _admission = crate::server::UNAUTHORIZED_TESTS.acquire().await.unwrap();
        let hbbr = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = hbbr.local_addr().unwrap();
        let id = Config::get_id();
        let identity = Config::get_key_pair().1;
        let (authority, secret) = sign::gen_keypair();
        let uuid = uuid::Uuid::new_v4().to_string();
        let mut reply = RelayResponse {
            uuid: uuid.clone(),
            relay_server: address.to_string(),
            ..Default::default()
        };
        reply.set_pk(
            sign::sign(
                &IdPk {
                    id: id.clone(),
                    pk: identity.clone().into(),
                    ..Default::default()
                }
                .write_to_bytes()
                .unwrap(),
                &secret,
            )
            .into(),
        );
        let controlled = tokio::spawn(async move {
            let (tcp, peer) = hbbr.accept().await.unwrap();
            let mut stream = Stream::from(tcp, address);
            let bytes = stream.next().await.unwrap().unwrap();
            assert_eq!(
                RendezvousMessage::parse_from_bytes(&bytes)
                    .unwrap()
                    .request_relay()
                    .uuid,
                uuid
            );
            crate::server::create_tcp_connection(
                crate::server::new_for_test(),
                stream,
                peer,
                true,
                Default::default(),
            )
            .await
            .unwrap();
        });
        let ((stream, direct, pk, _, _), _, _) = open(
            &id,
            &crate::encode64(authority.0),
            ConnType::DEFAULT_CONN,
            true,
            reply,
            "test rendezvous".into(),
        )
        .await
        .unwrap();
        assert!(stream.is_secured() && !direct);
        assert_eq!(pk, Some(identity));
        drop(stream);
        controlled.await.unwrap();
    }
}

impl RelayStart {
    pub(super) fn request(&self) -> bool {
        self.failed_relay.is_none() && self.requested.set(()).is_ok()
    }

    pub(super) fn requested(&self) -> bool {
        self.requested.get().is_some()
    }

    pub(super) fn accept(&self, endpoint: &str) {
        let _ = self.accepted.set(crate::check_port(endpoint, RELAY_PORT));
    }

    pub(super) fn accepted(&self) -> bool {
        self.accepted.get().is_some()
    }

    pub(super) fn ordinary_retry(&self) -> Self {
        Self {
            failed_relay: self.accepted.get().cloned(),
            ..Self::default()
        }
    }

    pub(super) fn remaining(
        &self,
        mut samples: Vec<RegionalRelaySample>,
    ) -> Vec<RegionalRelaySample> {
        if let Some(failed) = &self.failed_relay {
            samples.retain(|s| crate::check_port(&s.relay_server, RELAY_PORT) != *failed);
        }
        samples
    }
}
