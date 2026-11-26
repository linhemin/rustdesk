use super::{path_rtt, Client, PeerConnection};
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
    route: crate::p2p::relay_list::Route,
) -> ResultType<PeerConnection> {
    if reply.relay_server != route.id {
        bail!("Relay startup does not match the agreed endpoint");
    }
    let authority = crate::get_rs_pk(key);
    let signed = reply.pk().to_vec();
    if !authority
        .and_then(|pk| crate::decode_id_pk(&signed, &pk).ok())
        .is_some_and(|(id, _)| id == peer)
    {
        bail!("Relay startup has no verified peer identity");
    }
    let (mut stream, label) =
        Client::dial_relay(peer, reply.uuid, route, conn_type, ipv4).await?;
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
    failed_relays: Vec<String>,
    agreement: OnceLock<Agreement>,
}

pub(super) struct Agreement {
    rendezvous: String,
    endpoint: String,
    signed_identity: Vec<u8>,
}

// Only the winning connection proceeds to desktop login. The direct is held throughout the
// relay pairing and authentication; an unreachable node may delay login by at most this budget.
pub(super) async fn compare_direct(
    connection: &mut PeerConnection, frames: &mut path_rtt::InitialFrames, agreement: &Agreement,
    peer: &str, key: &str, token: &str, switch_code: &str,
) -> ResultType<()> {
    let Some(identity) = connection.0.2.as_ref() else { return Ok(()) };
    let setup = async {
        let (mut stream, label) = Client::request_relay(peer, agreement.endpoint.clone(),
            &agreement.rendezvous, true, key, token, ConnType::DEFAULT_CONN, switch_code).await?;
        let actual = Client::secure_connection(peer, agreement.signed_identity.clone(), key, &mut stream).await?;
        if !stream.is_secured() || actual.as_ref() != Some(identity) {
            bail!("Standby relay did not authenticate the same peer");
        }
        Ok::<_, hbb_common::anyhow::Error>((stream, label))
    };
    let Ok(Ok((mut relay, label))) = hbb_common::timeout(750, setup).await else { return Ok(()) };
    if path_rtt::prefer_alternate(&mut connection.0.0, &mut relay, frames).await? {
        connection.0 = (relay, false, Some(identity.clone()), None, label);
        connection.2 = false;
    }
    Ok(())
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
    fn failed_regions_are_excluded_from_later_offers_even_without_measurements() {
        let first = RelayStart::default();
        assert!(first.request());
        assert!(!first.request());
        first.accept("tokyo.example:21117");
        let retry = first.ordinary_retry();
        assert!(retry.request());
        let offered = ["tokyo.example:21117", "fuzhou.example:21117", "sz.example:21117"].map(str::to_owned);
        assert_eq!(retry.offered(offered.to_vec()), &offered[1..]);
        retry.accept(&offered[1]);
        assert_eq!(retry.ordinary_retry().offered(offered.to_vec()), &offered[2..]);
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
    async fn both_hbbr_joins_use_the_relay_key_and_the_peer_signature_uses_the_id_key() {
        let _admission = crate::server::UNAUTHORIZED_TESTS.acquire().await.unwrap();
        let hbbr = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = hbbr.local_addr().unwrap();
        let id = Config::get_id();
        let identity = Config::get_key_pair().1;
        let (authority, secret) = sign::gen_keypair();
        let relay_key = crate::encode64(sign::gen_keypair().0.0);
        let route = crate::p2p::relay_list::Route {
            address: address.to_string(),
            id: "k1-opaque.relay-id.invalid:21117".to_owned(),
            key: relay_key.clone(),
        };
        let uuid = uuid::Uuid::new_v4().to_string();
        let mut reply = RelayResponse {
            uuid: uuid.clone(),
            relay_server: route.id.clone(),
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
        let controlled = tokio::spawn(crate::server::create_relay_connection(
            crate::server::new_for_test(), route.clone(), uuid.clone(), address, true, true,
            Default::default(), None,
        ));
        let relay = tokio::spawn(async move {
            let accept = || async {
                let (tcp, peer) = hbbr.accept().await.unwrap();
                let mut stream = Stream::from(tcp, peer);
                let bytes = stream.next().await.unwrap().unwrap();
                let request = RendezvousMessage::parse_from_bytes(&bytes).unwrap().take_request_relay();
                assert_eq!(request.uuid, uuid);
                assert!(request.licence_key == relay_key, "Both hbbr legs must use the relay key");
                (stream, request.id)
            };
            let (mut a, first) = accept().await;
            let (mut b, second) = accept().await;
            assert_ne!(first.is_empty(), second.is_empty());
            loop {
                tokio::select! {
                    bytes = a.next() => {
                        let Some(Ok(bytes)) = bytes else { break };
                        if b.send_bytes(bytes.freeze()).await.is_err() { break; }
                    }
                    bytes = b.next() => {
                        let Some(Ok(bytes)) = bytes else { break };
                        if a.send_bytes(bytes.freeze()).await.is_err() { break; }
                    }
                }
            }
        });
        let ((stream, direct, pk, _, _), _, _) = open(
            &id,
            &crate::encode64(authority.0),
            ConnType::DEFAULT_CONN,
            true,
            reply,
            "test rendezvous".into(),
            route,
        )
        .await
        .unwrap();
        assert!(stream.is_secured() && !direct);
        assert_eq!(pk, Some(identity));
        drop(stream);
        relay.await.unwrap();
        controlled.await.unwrap();
    }
}

impl RelayStart {
    pub(super) fn agreed(&self, rendezvous: &str, endpoint: &str, signed_identity: &[u8]) {
        if !signed_identity.is_empty() {
            let _ = self.agreement.set(Agreement {
                rendezvous: rendezvous.to_owned(), endpoint: endpoint.to_owned(),
                signed_identity: signed_identity.to_vec(),
            });
        }
    }

    pub(super) fn agreement(&self, rendezvous: &str) -> Option<&Agreement> {
        self.agreement.get().filter(|agreement| agreement.rendezvous == rendezvous)
    }

    pub(super) fn request(&self) -> bool {
        self.requested.set(()).is_ok()
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
        let mut failed_relays = self.failed_relays.clone();
        if let Some(endpoint) = self.accepted.get() {
            if !failed_relays.contains(endpoint) {
                failed_relays.push(endpoint.clone());
            }
        }
        Self { failed_relays, ..Self::default() }
    }

    pub(super) fn offered(&self, mut endpoints: Vec<String>) -> Vec<String> {
        endpoints.retain(|endpoint| !self.failed_relays.contains(endpoint));
        endpoints
    }

    pub(super) fn remaining(
        &self,
        mut samples: Vec<RegionalRelaySample>,
    ) -> Vec<RegionalRelaySample> {
        samples.retain(|s| !self.failed_relays.contains(&crate::check_port(&s.relay_server, RELAY_PORT)));
        samples
    }
}
