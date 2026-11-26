use hbb_common::{
    anyhow::{anyhow, ensure},
    config::RELAY_PORT,
    futures_util::{stream::FuturesUnordered, StreamExt},
    protobuf::Message as _,
    rendezvous_proto::{
        rendezvous_message::Union, RegionalRelayDirectory, RegionalRelayPing, RegionalRelaySample,
        RendezvousMessage,
    },
    sodiumoxide::crypto::sign,
    tokio::{
        self,
        sync::watch,
        time::{timeout, Duration, Instant},
    },
    websocket::{check_ws, WsFramedStream},
    ResultType, Stream,
};
use std::sync::Mutex;

use super::relay_list::{self, MAX_RELAYS};
const MAX_FRAME: usize = 4096;
const DIRECTORY_DOMAIN: &[u8] = b"RustDesk regional relay directory v1\0";
const CACHE_TIME: Duration = Duration::from_secs(30);
const BUDGET: Duration = Duration::from_millis(2100);
const MEASURE_WINDOW: Duration = Duration::from_millis(1200);

// Separate concurrent TCP and ICE offers share the same background measurements.
struct Entry {
    nodes: Vec<String>,
    key: String,
    ipv4: bool,
    started: Instant,
    result: watch::Receiver<(Vec<RegionalRelaySample>, bool)>,
}
static CACHE: Mutex<Option<Entry>> = Mutex::new(None);

#[cfg(target_os = "ios")]
pub(super) fn network_changed() {
    CACHE.lock().unwrap().take();
}

fn refresh(key: &str, ipv4: bool) -> Option<watch::Receiver<(Vec<RegionalRelaySample>, bool)>> {
    let nodes = relay_list::configured();
    if nodes.len() < 2 {
        return None;
    }
    let mut cache = CACHE.lock().unwrap();
    if let Some(entry) = cache.as_ref().filter(|e| {
        e.nodes == nodes && e.key == key && e.ipv4 == ipv4 && e.started.elapsed() < CACHE_TIME
    }) {
        return Some(entry.result.clone());
    }
    let (tx, rx) = watch::channel((Vec::new(), false));
    *cache = Some(Entry {
        nodes: nodes.clone(),
        key: key.to_owned(),
        ipv4,
        started: Instant::now(),
        result: rx.clone(),
    });
    let key = key.to_owned();
    tokio::spawn(async move {
        let mut pending: FuturesUnordered<_> =
            nodes.iter().map(|name| measure(name, &key, ipv4)).collect();
        let _ = timeout(MEASURE_WINDOW, async {
            while let Some(sample) = pending.next().await {
                if let Ok(sample) = sample {
                    tx.send_modify(|state| state.0.push(sample));
                }
            }
        })
        .await;
        tx.send_modify(|state| state.1 = true);
    });
    Some(rx)
}

pub(crate) fn prefetch(key: &str) {
    refresh(key, true);
}

pub(crate) async fn offer_samples(key: &str, ipv4: bool) -> Vec<RegionalRelaySample> {
    let Some(mut rx) = refresh(key, ipv4) else {
        return Vec::new();
    };
    // A slow or older hbbr can still be paired. Its missing echo must not block the first image.
    let _ = timeout(Duration::from_millis(300), rx.wait_for(|state| state.1)).await;
    let samples = rx.borrow().0.clone();
    samples
}

async fn read(stream: &mut Stream) -> ResultType<Union> {
    let data = stream
        .next()
        .await
        .ok_or_else(|| anyhow!("Relay closed the connection"))??;
    RendezvousMessage::parse_from_bytes(&data)?
        .union
        .ok_or_else(|| anyhow!("Empty relay reply"))
}

fn verify_directory(reply: &RegionalRelayDirectory, nonce: u64, key: &str) -> ResultType<()> {
    ensure!(nonce != 0 && reply.nonce == nonce, "Stale relay directory");
    let pk = crate::get_rs_pk(key).ok_or_else(|| anyhow!("Missing directory signing key"))?;
    let sig = sign::Signature::from_bytes(&reply.signature)
        .map_err(|_| anyhow!("Invalid directory signature"))?;
    let unsigned = RegionalRelayDirectory {
        nonce,
        relay_servers: reply.relay_servers.clone(),
        allow_session_direct: reply.allow_session_direct,
        ..Default::default()
    };
    let mut content = DIRECTORY_DOMAIN.to_vec();
    content.extend(unsigned.write_to_bytes()?);
    ensure!(
        sign::verify_detached(&sig, &content, &pk),
        "Relay directory signature mismatch"
    );
    Ok(())
}

async fn query(stream: &mut Stream, nonce: u64) -> ResultType<RegionalRelayDirectory> {
    stream.set_max_packet_length(MAX_FRAME);
    let mut request = RendezvousMessage::new();
    request.set_regional_relay_directory(RegionalRelayDirectory {
        nonce,
        ..Default::default()
    });
    stream.send(&request).await?;
    let Union::RegionalRelayDirectory(reply) = read(stream).await? else {
        return Err(anyhow!("Expected relay directory"));
    };
    ensure!(
        reply.relay_servers.len() <= MAX_RELAYS,
        "Oversized relay directory"
    );
    Ok(reply)
}

async fn signed_ws_directory(
    server: &str,
    key: &str,
) -> ResultType<(RegionalRelayDirectory, bool)> {
    ensure!(
        server.starts_with("wss://") && !key.is_empty(),
        "Verified WSS signalling and key required"
    );
    let mut stream = Stream::WebSocket(WsFramedStream::new_verified_wss(server, 1500).await?);
    let nonce = hbb_common::rand::random::<u64>().max(1);
    let reply = query(&mut stream, nonce).await?;
    verify_directory(&reply, nonce, key)?;
    Ok((reply, stream.local_addr().is_ipv4()))
}

pub(crate) async fn ws_direct_grant(server: &str, key: &str) -> bool {
    matches!(timeout(BUDGET, signed_ws_directory(&check_ws(server), key)).await,
        Ok(Ok((reply, _))) if reply.allow_session_direct)
}

#[cfg(test)]
mod ws_grant_tests {
    use super::*;

    #[test]
    fn an_empty_signed_directory_can_grant_ice_only_for_its_nonce_and_policy() {
        let (pk, sk) = sign::gen_keypair();
        let key = crate::encode64(pk.0);
        let mut reply = RegionalRelayDirectory {
            nonce: 7,
            allow_session_direct: true,
            ..Default::default()
        };
        let mut content = DIRECTORY_DOMAIN.to_vec();
        content.extend(reply.write_to_bytes().unwrap());
        reply.signature = sign::sign_detached(&content, &sk)
            .to_bytes()
            .to_vec()
            .into();
        assert!(verify_directory(&reply, 7, &key).is_ok());
        assert!(verify_directory(&reply, 8, &key).is_err());
        reply.allow_session_direct = false;
        assert!(verify_directory(&reply, 7, &key).is_err());
    }
}

async fn measure(name: &str, key: &str, ipv4: bool) -> ResultType<RegionalRelaySample> {
    let endpoint = crate::check_port(name, RELAY_PORT);
    let (mut stream, _) = super::relay::connect(endpoint, key, ipv4).await?;
    stream.set_max_packet_length(128);
    let nonce = hbb_common::rand::random::<u64>().max(1);
    let mut ping = RendezvousMessage::new();
    ping.set_regional_relay_ping(RegionalRelayPing {
        nonce,
        ..Default::default()
    });
    let start = Instant::now();
    stream.send(&ping).await?;
    ensure!(
        matches!(read(&mut stream).await?, Union::RegionalRelayPing(p) if p.nonce == nonce),
        "Relay echo mismatch"
    );
    Ok(RegionalRelaySample {
        relay_server: name.to_owned(),
        connect_ms: start.elapsed().as_millis().max(1) as u32,
        ..Default::default()
    })
}

fn best_common<'a>(
    controller: &'a [RegionalRelaySample],
    host: &[RegionalRelaySample],
) -> Option<&'a str> {
    if controller.len() > MAX_RELAYS {
        return None;
    }
    controller
        .iter()
        .filter(|a| (1..=10_000).contains(&a.connect_ms))
        .filter_map(|a| {
            let b = host
                .iter()
                .find(|b| b.relay_server == a.relay_server && b.connect_ms > 0)?;
            Some((
                a.connect_ms.saturating_add(b.connect_ms),
                a.relay_server.as_str(),
            ))
        })
        .min_by_key(|(total, _)| *total)
        .map(|(_, name)| name)
}

pub(crate) async fn choose_common(
    common: &[String],
    offered: &[RegionalRelaySample],
    key: &str,
    ipv4: bool,
) -> Option<String> {
    let first = common.first()?;
    if common.len() == 1 || offered.is_empty() {
        return Some(first.clone());
    }
    let mut host = offer_samples(key, ipv4).await;
    host.retain(|s| common.contains(&s.relay_server));
    Some(best_common(offered, &host).unwrap_or(first).to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(name: &str, ms: u32) -> RegionalRelaySample {
        RegionalRelaySample {
            relay_server: name.into(),
            connect_ms: ms,
            ..Default::default()
        }
    }

    #[test]
    fn regional_relay_selection_accounts_for_both_legs_and_requires_local_evidence() {
        let controller = [
            sample("tokyo", 50),
            sample("shenzhen", 135),
            sample("fuzhou", 150),
        ];
        let host = [
            sample("tokyo", 150),
            sample("shenzhen", 25),
            sample("fuzhou", 25),
        ];
        assert_eq!(best_common(&controller, &host), Some("shenzhen"));
        assert_eq!(
            best_common(&controller, &[sample("tokyo", 30), sample("shenzhen", 25)]),
            Some("tokyo")
        );
        assert_eq!(best_common(&controller, &[sample("unlisted", 1)]), None);
    }

    #[tokio::test]
    async fn regional_relay_measurement_requires_the_matching_application_echo() {
        use tokio::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let echo = tokio::spawn(async move {
            for valid in [false, true] {
                let (socket, _) = listener.accept().await.unwrap();
                let mut stream = Stream::from(socket, address);
                let Union::RegionalRelayPing(mut ping) = read(&mut stream).await.unwrap() else {
                    panic!()
                };
                if !valid {
                    ping.nonce ^= 1;
                }
                let mut response = RendezvousMessage::new();
                response.set_regional_relay_ping(ping);
                stream.send(&response).await.unwrap();
            }
        });
        let name = address.to_string();
        assert!(measure(&name, "", true).await.is_err());
        assert_eq!(measure(&name, "", true).await.unwrap().relay_server, name);
        echo.await.unwrap();
    }

    #[test]
    fn regional_relay_wss_directory_binds_nonce_and_nodes_to_operator_key() {
        let (public, private) = sign::gen_keypair();
        let mut directory = RegionalRelayDirectory {
            nonce: 72,
            relay_servers: vec!["tokyo.example".into()],
            ..Default::default()
        };
        let mut body = DIRECTORY_DOMAIN.to_vec();
        body.extend(directory.write_to_bytes().unwrap());
        directory.signature = sign::sign_detached(&body, &private)
            .to_bytes()
            .to_vec()
            .into();
        let key = crate::encode64(public.0);
        assert!(verify_directory(&directory, 72, &key).is_ok());
        assert!(verify_directory(&directory, 73, &key).is_err());
        directory.relay_servers.push("unapproved.example".into());
        assert!(verify_directory(&directory, 72, &key).is_err());
    }
}
