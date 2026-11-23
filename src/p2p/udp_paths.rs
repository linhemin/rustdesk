use crate::{kcp_stream::KcpStream, p2p::probe_report::{self, Port, Recording}};
use hbb_common::{
    bytes::BytesMut,
    futures_util::{stream::FuturesUnordered, StreamExt},
    sodiumoxide::{crypto::auth, randombytes},
    tokio::{
        self,
        net::UdpSocket,
        time::{timeout, Duration, Instant},
    },
    ResultType,
};
use std::{net::SocketAddr, sync::{atomic::Ordering::Relaxed, Arc}};

const EXTRA_SOCKETS: usize = 3;
const WIDE_EXTRA_SOCKETS: usize = 11;
const RECEIPT_SIZE: usize = 38;
pub(crate) const MAX_LOCAL_SOCKETS: usize = 1 + WIDE_EXTRA_SOCKETS + 2;
const MAX_PEERS: usize = 8;

#[derive(Debug, Default)]
pub(crate) struct Counts {
    pub sockets: usize,
    pub ports: usize,
    pub sent: u32,
    pub errors: u32,
    pub authenticated: usize,
    pub received: u32,
    pub valid_foreign: u32,
    pub verified_foreign: u32,
}

impl std::fmt::Display for Counts {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "UDP candidate timeout: {} sockets, {} NAS ports, {} sent, {} send errors, {} authenticated pairs",
            self.sockets, self.ports, self.sent, self.errors, self.authenticated)
    }
}
impl std::error::Error for Counts {}

#[derive(Default)]
pub(crate) struct Candidates {
    sockets: Vec<Arc<UdpSocket>>,
    pub tickets: Vec<u8>,
}

async fn observed_socket(source: SocketAddr, nas: SocketAddr, wide: bool, primary: Option<(&UdpSocket, Option<u16>)>) -> Option<(Arc<UdpSocket>, Vec<u8>, bool)> {
    // The primary port is advertised independently of the secondary receipts.
    // Use one existing observation slot to preserve that source port toward the peer.
    let preferred = if let Some((socket, observed)) = primary {
        let port = match observed {
            Some(port) => Some(port),
            None => super::udp_mapping::observe_v4_port(socket, nas).await.ok(),
        };
        if let Some(port) = port.filter(|p| *p >= 32768 && *p != source.port()) {
            bind_observed_port(source, port).await
        } else { None }
    } else { None };
    let socket = match preferred {
        Some(socket) => socket,
        None => bind_observed_port(source, 0).await?,
    };
    let mut request = [0; 96];
    request[..8].copy_from_slice(&[0, 1, 0, 76, 0x21, 0x12, 0xa4, 0x42]);
    randombytes::randombytes_into(&mut request[8..20]);
    request[20..24].copy_from_slice(&[0, 0x26, 0, 72]);
    request[24..32].copy_from_slice(b"RD-PATH1");
    if wide { request[32..40].copy_from_slice(b"RD-WIDE1"); }
    let mut buf = [0; 128];
    for wait in [250, 450] {
        socket.send_to(&request, nas).await.ok()?;
        if let Ok(Ok((n, from))) =
            timeout(Duration::from_millis(wait), socket.recv_from(&mut buf)).await
        {
            if from != nas
                || n < 32
                || buf[..2] != [1, 1]
                || buf[4..20] != request[4..20]
                || usize::from(u16::from_be_bytes([buf[2], buf[3]])) != n - 20
            {
                continue;
            }
            let pos = match &buf[20..24] {
                [0, 0x20, 0, 8] => 32,
                [0, 0x20, 0, 20] => 44,
                _ => continue,
            };
            let expanded = wide && n == pos + 52 && buf[pos + 44..n] == [0xc0, 0x52, 0, 4, 0, 0, 0, 11];
            if (n == pos + 44 || expanded) && buf[pos..pos + 4] == [0xc0, 0x51, 0, 38] {
                return Some((
                    Arc::new(socket),
                    buf[pos + 4..pos + 4 + RECEIPT_SIZE].to_vec(),
                    expanded,
                ));
            }
            return None; // An older hbbs supplied a standard binding response.
        }
    }
    None
}

impl Candidates {
    pub async fn gather(primary: &UdpSocket, nas: SocketAddr, wide: bool, observed: Option<u16>) -> Self {
        let mut result = Self::default();
        let Ok(source) = primary.local_addr() else { return result; };
        if source.ip().is_unspecified() {
            return result;
        }
        let mut jobs: FuturesUnordered<_> = (0..EXTRA_SOCKETS)
            .map(|_| observed_socket(source, nas, wide, None))
            .collect();
        let mut extended = false;
        while let Some(candidate) = jobs.next().await {
            if let Some((socket, ticket, supported)) = candidate {
                result.sockets.push(socket);
                result.tickets.extend(ticket);
                if supported && !extended {
                    extended = true;
                    jobs.extend((EXTRA_SOCKETS..WIDE_EXTRA_SOCKETS).map(|i| {
                        observed_socket(source, nas, wide, (i == EXTRA_SOCKETS).then_some((primary, observed)))
                    }));
                }
            }
        }
        if extended { result.bind_observed_ports(source).await; }
        result
    }

    async fn bind_observed_ports(&mut self, source: SocketAddr) {
        // Some NATs rewrite traffic to hbbs but preserve the local source port toward
        // the peer. Keep the original sockets and try the port the peer already knows.
        let mut added = 0;
        for receipt in self.tickets.chunks_exact(RECEIPT_SIZE) {
            let port = u16::from_be_bytes([receipt[0], receipt[1]]);
            if port < 32768 || self.sockets.iter().any(|s| s.local_addr().is_ok_and(|a| a.port() == port)) {
                continue;
            }
            if let Some(socket) = bind_observed_port(source, port).await {
                self.sockets.push(Arc::new(socket));
                added += 1;
                if added == 2 { break; }
            }
        }
    }
}

async fn bind_observed_port(source: SocketAddr, port: u16) -> Option<UdpSocket> {
    #[cfg(target_os = "windows")]
    if let Some(iface) = super::Interface::configured().filter(|i| source.ip() == std::net::IpAddr::V4(i.address)) {
        return crate::platform::bind_p2p_stun_udp(iface.address, iface.index, port, port);
    }
    let mut local = source;
    local.set_port(port);
    UdpSocket::bind(local).await.ok()
}

pub(crate) struct Paths {
    pub local: Candidates,
    pub ports: Vec<u32>,
    pub key: auth::Key,
}

fn packet(kind: u8, nonce: &[u8], key: &auth::Key) -> [u8; 45] {
    let mut p = [0; 45];
    p[..4].copy_from_slice(b"RDU2");
    p[4] = kind;
    p[5..13].copy_from_slice(nonce);
    let tag = auth::authenticate(&p[..13], key);
    p[13..].copy_from_slice(&tag.0);
    p
}

impl Paths {
    pub(crate) fn record(&self, primary: &UdpSocket) -> ResultType<Recording> {
        let ports = std::iter::once(primary).chain(self.local.sockets.iter().map(AsRef::as_ref))
            .map(|s| s.local_addr().map(|a| a.port())).collect::<std::io::Result<Vec<_>>>()?;
        Ok(Recording::start(probe_report::id(&self.key), ports.into_iter()))
    }

    pub async fn select(self, primary: Arc<UdpSocket>, peer: SocketAddr, listen: bool)
        -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
        self.select_recorded(primary, peer, listen, None).await
    }

    pub(crate) async fn select_recorded(
        self,
        primary: Arc<UdpSocket>,
        peer: SocketAddr,
        listen: bool,
        report: Option<&Recording>,
    ) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
        let peer = super::ordinary_udp::udp_peer_destination(&primary, peer).await?;
        let mut destinations = vec![peer];
        for port in self
            .ports
            .iter()
            .take(WIDE_EXTRA_SOCKETS)
            .filter_map(|p| u16::try_from(*p).ok())
        {
            let mut addr = peer;
            addr.set_port(port);
            if port != 0 && !destinations.contains(&addr) {
                destinations.push(addr);
            }
        }
        let key = self.key;
        let count = self.local.sockets.len() + 1;
        let mut jobs: FuturesUnordered<_> = std::iter::once(primary)
            .chain(self.local.sockets)
            .enumerate()
            .map(|(i, s)| check_socket(s, destinations.clone(), listen, &key, report.and_then(|r| r.ports.get(i))))
            .collect();
        let mut totals = Counts {
            sockets: count,
            ports: destinations.len(),
            ..Default::default()
        };
        let mut socket_error = None;
        while let Some(result) = jobs.next().await {
            match result {
                Ok(selected) => return Ok(selected),
                Err(e) => {
                    if let Some(c) = e.downcast_ref::<Counts>() {
                        totals.sent += c.sent;
                        totals.errors += c.errors;
                        totals.authenticated += c.authenticated;
                        totals.received += c.received;
                        totals.valid_foreign += c.valid_foreign;
                        totals.verified_foreign += c.verified_foreign;
                    } else {
                        socket_error = Some(e);
                    }
                }
            }
        }
        if totals.sent == 0 && totals.errors == 0 {
            if let Some(error) = socket_error {
                return Err(error);
            }
        }
        Err(totals.into())
    }
}

struct PendingAddress {
    addr: SocketAddr,
    challenge: [u8; 8],
    request: Option<[u8; 8]>,
    retry_challenge: bool,
}

async fn probe_send(socket: &UdpSocket, packet: &[u8; 45], to: SocketAddr, row: Option<&Port>) -> std::io::Result<usize> {
    let sent = socket.send_to(packet, to).await;
    if let Some(row) = row {
        if sent.is_ok() {
            row.tx.fetch_add(1, Relaxed);
            if matches!(packet[4], 1 | 3) { row.replies.fetch_add(1, Relaxed); }
        } else { row.errors.fetch_add(1, Relaxed); }
    }
    sent
}

async fn check_socket(
    socket: Arc<UdpSocket>,
    mut peers: Vec<SocketAddr>,
    listen: bool,
    key: &auth::Key,
    row: Option<&Port>,
) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
    let ip = peers[0].ip();
    let mut nonce = [0; 8];
    randombytes::randombytes_into(&mut nonce);
    let kind = if listen { 2 } else { 0 };
    let probe = packet(kind, &nonce, key);
    let mut authenticated = Vec::new();
    // A NAT or a second interface can use a different source IP for the peer than for hbbs.
    // Require a fresh challenge for that exact tuple before adding it to the periodic checks.
    let mut pending: Vec<PendingAddress> = Vec::new();
    let mut buf = [0; 1500];
    let start = Instant::now();
    let deadline = start + Duration::from_secs(6);
    let mut next = start;
    let max_peers = MAX_PEERS.max(peers.len() + 4);
    let mut cursor = 0;
    let mut sent = 0u32;
    let mut errors = 0u32;
    let mut traffic = Counts::default();
    loop {
        tokio::select! {
            biased;
            _ = tokio::time::sleep_until(deadline) => {
                return Err(Counts { sent, errors, authenticated: authenticated.len(), ..traffic }.into());
            }
            _ = tokio::time::sleep_until(next) => {
                for _ in 0..peers.len().min(4) {
                    match probe_send(&socket, &probe, peers[cursor], row).await { Ok(_) => sent += 1, Err(_) => errors += 1 }
                    cursor = (cursor + 1) % peers.len();
                }
                next = Instant::now() + Duration::from_millis(if start.elapsed().as_millis() < 250 { 90 } else { 350 });
            }
            received = socket.recv_from(&mut buf) => {
                let (n, from) = match received {
                    Ok(pair) => pair,
                    Err(e) if matches!(e.kind(), std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionRefused) => continue,
                    Err(e) => return Err(e.into()),
                };
                if let Some(row) = row { row.rx.fetch_add(1, Relaxed); }
                traffic.received = traffic.received.saturating_add(1);
                if listen && !buf[..n].starts_with(b"RDU2") && authenticated.contains(&from) {
                    if let Some(syn) = KcpStream::incoming_syn(&buf[..n]) {
                        socket.connect(from).await?;
                        return Ok((socket, Some(syn)));
                    }
                }
                if n != 45 || &buf[..4] != b"RDU2" { continue; }
                let Some(tag) = auth::Tag::from_slice(&buf[13..45]) else { continue };
                if !auth::verify(&tag, &buf[..13], key) { continue; }
                if let Some(row) = row { row.verified.fetch_add(1, Relaxed); }
                let known = peers.contains(&from);
                if !known && from.ip() != ip {
                    traffic.valid_foreign = traffic.valid_foreign.saturating_add(1);
                    if from.ip().is_unspecified() || from.ip().is_multicast()
                        || (from.ip().is_loopback() && !ip.is_loopback())
                        || from.ip() == std::net::IpAddr::V4(std::net::Ipv4Addr::BROADCAST) {
                        continue;
                    }
                    let incoming = <[u8; 8]>::try_from(&buf[5..13])?;
                    let request = buf[4] == (kind ^ 2);
                    if let Some(index) = pending.iter().position(|p| p.addr == from) {
                        if buf[4] == kind + 1 && incoming == pending[index].challenge {
                            let candidate = pending.swap_remove(index);
                            if peers.len() >= max_peers { continue; }
                            peers.push(from);
                            traffic.verified_foreign += 1;
                            if let Some(original) = candidate.request {
                                authenticated.push(from);
                                probe_send(&socket, &packet((kind ^ 2) + 1, &original, key), from, row).await?;
                            }
                            probe_send(&socket, &probe, from, row).await?;
                        } else if request {
                            let candidate = &mut pending[index];
                            candidate.request = Some(incoming);
                            let response = if candidate.retry_challenge {
                                packet(kind, &candidate.challenge, key)
                            } else {
                                packet(buf[4] + 1, &incoming, key)
                            };
                            candidate.retry_challenge = !candidate.retry_challenge;
                            probe_send(&socket, &response, from, row).await?;
                        }
                    } else if peers.len() + pending.len() < max_peers
                        && (request || (buf[4] == kind + 1 && incoming == nonce)) {
                        let mut challenge = [0; 8];
                        randombytes::randombytes_into(&mut challenge);
                        pending.push(PendingAddress {
                            addr: from, challenge, request: request.then_some(incoming), retry_challenge: false,
                        });
                        probe_send(&socket, &packet(kind, &challenge, key), from, row).await?;
                    }
                    continue;
                }
                if !known && peers.len() >= max_peers { continue; }
                if buf[4] == (kind ^ 2) {
                    if !authenticated.contains(&from) { authenticated.push(from); }
                    let reply = packet(buf[4] + 1, &buf[5..13], key);
                    probe_send(&socket, &reply, from, row).await?;
                } else if buf[4] == kind + 1 && buf[5..13] == nonce && known && !listen {
                    socket.connect(from).await?;
                    return Ok((socket, None));
                } else if buf[4] != kind + 1 || buf[5..13] != nonce { continue; }
                // A valid packet from a different source port supplies a peer-reflexive candidate.
                if !known { peers.push(from); probe_send(&socket, &probe, from, row).await?; }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn nas_observes_a_secondary_socket_on_the_primary_mapped_port() {
        let nas = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let primary = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let port = UdpSocket::bind("127.0.0.1:0").await.unwrap().local_addr().unwrap().port();
        let observer = async {
            let mut request = [0; 96];
            let (_, from) = nas.recv_from(&mut request).await.unwrap();
            let mut reply = [0; 76];
            reply[..4].copy_from_slice(&[1, 1, 0, 56]);
            reply[4..20].copy_from_slice(&request[4..20]);
            reply[20..24].copy_from_slice(&[0, 0x20, 0, 8]);
            reply[32..36].copy_from_slice(&[0xc0, 0x51, 0, 38]);
            nas.send_to(&reply, from).await.unwrap();
            from.port()
        };
        let candidate = observed_socket(primary.local_addr().unwrap(), nas.local_addr().unwrap(), true, Some((&primary, Some(port))));
        let (from, candidate) = tokio::join!(observer, candidate);
        assert!(candidate.is_some());
        assert_eq!(from, port);
    }

    #[tokio::test]
    async fn direct_path_works_when_the_peer_can_only_reach_the_nas_observed_port() {
        let peer = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let primary = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let port = UdpSocket::bind("127.0.0.1:0").await.unwrap().local_addr().unwrap().port();
        let mut local = Candidates { sockets: Vec::new(), tickets: vec![0; RECEIPT_SIZE] };
        local.tickets[..2].copy_from_slice(&port.to_be_bytes());
        local.bind_observed_ports(primary.local_addr().unwrap()).await;
        let key = auth::gen_key();
        let destination = SocketAddr::new(primary.local_addr().unwrap().ip(), port);
        let peer_addr = peer.local_addr().unwrap();
        let challenge = packet(0, &[7; 8], &key);
        let ack = packet(1, &[7; 8], &key);
        let host = Paths { local, ports: vec![], key };
        let accept = async {
            let (sock, syn) = host.select(primary, peer_addr, true).await.unwrap();
            assert_eq!(sock.local_addr().unwrap().port(), port);
            KcpStream::accept(sock, Duration::from_secs(2), syn).await.unwrap()
        };
        let dial = async {
            // Model a filter that only admits responses from the NAS-observed port.
            peer.send_to(&challenge, destination).await.unwrap();
            timeout(Duration::from_secs(2), async {
                let mut buf = [0; 64];
                loop {
                    let (n, from) = peer.recv_from(&mut buf).await.unwrap();
                    if from == destination && buf[..n] == ack[..] { break; }
                }
            }).await.unwrap();
            peer.connect(destination).await.unwrap();
            KcpStream::connect(peer, Duration::from_secs(2)).await.unwrap()
        };
        let ((_a, mut client), (_b, mut server)) = tokio::join!(dial, accept);
        client.send_raw(b"hello".to_vec()).await.unwrap();
        assert_eq!(&server.next_timeout(2000).await.unwrap().unwrap()[..], b"hello");
    }

    #[tokio::test]
    async fn controlled_report_counts_replies_on_the_receiving_port_for_one_round() {
        let remote = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let controlled = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let addr = controlled.local_addr().unwrap();
        let extra = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let key = auth::gen_key();
        let id = probe_report::id(&key);
        let paths = Paths { key: key.clone(), ports: vec![],
            local: Candidates { sockets: vec![extra], tickets: vec![] } };
        let recording = paths.record(&controlled).unwrap();
        assert!(probe_report::take(&[0; 32]).is_none());
        let done = probe_report::take(&id).unwrap();
        assert!(probe_report::take(&id).is_none());
        remote.send_to(&packet(0, &[7; 8], &key), addr).await.unwrap();
        remote.send_to(b"invalid", addr).await.unwrap();
        let _ = paths.select_recorded(controlled, remote.local_addr().unwrap(), true, Some(&recording)).await.unwrap_err();
        drop(recording);
        let report = done.await.unwrap();
        let first = &report.ports[0];
        assert_eq!((first.local_port, first.received, first.verified, first.replies),
            (u32::from(addr.port()), 2, 1, 1));
        assert!(first.sent > first.replies);
        assert_eq!((report.ports[1].received, report.ports[1].replies), (0, 0));
        assert!(probe_report::display(&id, &report).is_some());
        assert!(probe_report::display(&[0; 32], &report).is_none());
    }

    #[tokio::test]
    async fn peer_on_a_different_source_ip_must_return_the_tuple_challenge_before_kcp() {
        let left = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let right = Arc::new(UdpSocket::bind("127.0.0.2:0").await.unwrap());
        let unreachable = UdpSocket::bind("127.0.0.3:0").await.unwrap();
        let outsider = UdpSocket::bind("127.0.0.4:0").await.unwrap();
        let target = left.local_addr().unwrap();
        let key = auth::gen_key();
        let paths = || Paths { local: Candidates::default(), ports: vec![], key: key.clone() };
        let controller = async {
            let (socket, _) = paths().select(left, unreachable.local_addr().unwrap(), false).await.unwrap();
            assert_eq!(socket.peer_addr().unwrap(), right.local_addr().unwrap());
            KcpStream::connect(socket, Duration::from_secs(2)).await.unwrap()
        };
        let controlled = async {
            let mut probe = [0; 45];
            unreachable.recv_from(&mut probe).await.unwrap();
            // A copy of an ACK for the advertised address cannot nominate a different source.
            outsider.send_to(&packet(1, &probe[5..13], &key), target).await.unwrap();
            let (n, _) = timeout(Duration::from_secs(1), outsider.recv_from(&mut probe)).await.unwrap().unwrap();
            assert_eq!((n, probe[4]), (45, 0));
            let (socket, syn) = paths().select(right.clone(), target, true).await.unwrap();
            KcpStream::accept(socket, Duration::from_secs(2), syn).await.unwrap()
        };
        let ((_a, mut client), (_b, mut host)) = tokio::join!(controller, controlled);
        client.send_raw(vec![42; 4500]).await.unwrap();
        assert_eq!(host.next_timeout(2000).await.unwrap().unwrap().as_ref(), &[42; 4500]);
        host.send_raw(vec![17; 4500]).await.unwrap();
        assert_eq!(client.next_timeout(2000).await.unwrap().unwrap().as_ref(), &[17; 4500]);
    }

    #[tokio::test]
    async fn direct_kcp_recovers_when_the_observer_ports_do_not_reach_either_primary_socket() {
        async fn bind() -> Arc<UdpSocket> {
            Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap())
        }
        let (left, right, alternate) = (bind().await, bind().await, bind().await);
        let (unreachable_left, unreachable_right) = (bind().await, bind().await);
        let stale = [bind().await, bind().await, bind().await];
        let mut ports: Vec<_> = stale.iter().map(|s| u32::from(s.local_addr().unwrap().port())).collect();
        ports.push(u32::from(alternate.local_addr().unwrap().port()));
        let key = auth::gen_key();
        let controller = Paths {
            local: Candidates::default(),
            ports,
            key: key.clone(),
        };
        let responder = Paths {
            local: Candidates {
                sockets: vec![alternate],
                tickets: vec![],
            },
            ports: vec![],
            key,
        };
        let host = async {
            let (socket, syn) = responder
                .select(right, unreachable_left.local_addr().unwrap(), true)
                .await
                .unwrap();
            KcpStream::accept(socket, Duration::from_secs(2), syn)
                .await
                .unwrap()
        };
        let client = async {
            let (socket, _) = controller
                .select(left, unreachable_right.local_addr().unwrap(), false)
                .await
                .unwrap();
            KcpStream::connect(socket, Duration::from_secs(2))
                .await
                .unwrap()
        };
        let ((_a, mut host), (_b, mut client)) = tokio::join!(host, client);
        let payload = vec![42; 4500];
        client.send_raw(payload.clone()).await.unwrap();
        assert_eq!(
            host.next_timeout(2000).await.unwrap().unwrap().as_ref(),
            &payload
        );
        host.send_raw(b"video".to_vec()).await.unwrap();
        assert_eq!(
            client.next_timeout(2000).await.unwrap().unwrap().as_ref(),
            b"video"
        );
    }
}
