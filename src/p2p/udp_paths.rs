use crate::kcp_stream::KcpStream;
use hbb_common::{
    bytes::BytesMut,
    futures_util::{stream::FuturesUnordered, FutureExt, StreamExt},
    sodiumoxide::{crypto::auth, randombytes},
    tokio::{
        self,
        net::UdpSocket,
        sync::Semaphore,
        time::{timeout, Duration, Instant},
    },
    ResultType,
};
use std::{net::SocketAddr, sync::Arc};

const EXTRA_SOCKETS: usize = 3;
const WIDE_EXTRA_SOCKETS: usize = 11;
const RECEIPT_SIZE: usize = 38;
const MAX_PEERS: usize = 8;
// A NAT that maps every destination to a new port hides the mapping the peer has to reach.
// The side behind it opens PREDICTED_SOCKETS mappings towards the peer's advertised port and
// the other side guesses GUESSES of its ports; both do both, since neither knows its own NAT.
const PREDICTED_SOCKETS: usize = 256;
const PREDICTION_DELAY: Duration = Duration::from_millis(400);
const GUESSES: usize = 1536;
const GUESS_BATCH: usize = 12;
const GUESS_INTERVAL: Duration = Duration::from_millis(20);
const PORTS: usize = 65536 - 1024;
// Coprime to PORTS, so no port repeats, and below PREDICTED_SOCKETS, so the first pass lands
// in the consecutive ports of a sequential allocator wherever they are.
const GUESS_STRIDE: usize = 251;
// The peer decides how often it asks; this bounds the sockets and guesses it can make us spend.
static PREDICTIONS: Semaphore = Semaphore::const_new(2);

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

async fn observed_socket(source: SocketAddr, nas: SocketAddr, wide: bool) -> Option<(Arc<UdpSocket>, Vec<u8>, bool)> {
    let local = SocketAddr::new(source.ip(), 0);
    #[cfg(target_os = "windows")]
    let pinned =
        super::Interface::configured().filter(|i| source.ip() == std::net::IpAddr::V4(i.address));
    #[cfg(target_os = "windows")]
    let socket = if let Some(i) = pinned {
        crate::platform::bind_p2p_stun_udp(i.address, i.index, 0, 0)?
    } else {
        UdpSocket::bind(local).await.ok()?
    };
    #[cfg(not(target_os = "windows"))]
    let socket = UdpSocket::bind(local).await.ok()?;
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
    pub async fn gather(source: SocketAddr, nas: SocketAddr, wide: bool) -> Self {
        let mut result = Self::default();
        if source.ip().is_unspecified() {
            return result;
        }
        let mut jobs: FuturesUnordered<_> = (0..EXTRA_SOCKETS)
            .map(|_| observed_socket(source, nas, wide))
            .collect();
        let mut extended = false;
        while let Some(candidate) = jobs.next().await {
            if let Some((socket, ticket, supported)) = candidate {
                result.sockets.push(socket);
                result.tickets.extend(ticket);
                if supported && !extended {
                    extended = true;
                    jobs.extend((EXTRA_SOCKETS..WIDE_EXTRA_SOCKETS).map(|_| observed_socket(source, nas, wide)));
                }
            }
        }
        result
    }
}

fn guessed_port(base: usize, guess: usize) -> u16 {
    (1024 + (base + guess * GUESS_STRIDE) % PORTS) as u16
}

fn predicted_socket_count() -> usize {
    #[cfg(unix)]
    {
        use hbb_common::libc::{getrlimit, rlimit, setrlimit, RLIMIT_NOFILE};
        let mut limit = rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        // SAFETY: `limit` is a valid rlimit for both calls.
        if unsafe { getrlimit(RLIMIT_NOFILE, &mut limit) } != 0 {
            return 0;
        }
        // Apple platforms start at 256 descriptors.
        if limit.rlim_cur < 1024 && limit.rlim_max >= 1024 {
            let raised = rlimit {
                rlim_cur: 1024,
                ..limit
            };
            if unsafe { setrlimit(RLIMIT_NOFILE, &raised) } == 0 {
                limit = raised;
            }
        }
        return PREDICTED_SOCKETS.min((limit.rlim_cur / 4) as usize);
    }
    #[cfg(not(unix))]
    PREDICTED_SOCKETS
}

async fn predicted_socket(source: std::net::IpAddr) -> Option<Arc<UdpSocket>> {
    #[cfg(target_os = "windows")]
    if let Some(i) =
        super::Interface::configured().filter(|i| source == std::net::IpAddr::V4(i.address))
    {
        return crate::platform::bind_p2p_stun_udp(i.address, i.index, 0, 0).map(Arc::new);
    }
    UdpSocket::bind(SocketAddr::new(source, 0))
        .await
        .ok()
        .map(Arc::new)
}

async fn predict(
    primary: &UdpSocket,
    peer: SocketAddr,
    listen: bool,
    key: &auth::Key,
    deadline: Instant,
) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
    tokio::time::sleep(PREDICTION_DELAY).await;
    let Ok(Ok(_permit)) = tokio::time::timeout_at(deadline, PREDICTIONS.acquire()).await else {
        return Err(Counts::default().into());
    };
    let source = primary.local_addr()?.ip();
    let mut jobs = FuturesUnordered::new();
    for _ in 0..predicted_socket_count() {
        let Some(socket) = predicted_socket(source).await else {
            break;
        };
        jobs.push(check_socket(socket, vec![peer], listen, key, deadline, true));
    }
    let mut totals = Counts {
        sockets: jobs.len(),
        ..Default::default()
    };
    let mut nonce = [0; 8];
    randombytes::randombytes_into(&mut nonce);
    let probe = packet(if listen { 2 } else { 0 }, &nonce, key);
    let base = usize::from(u16::from_be_bytes([nonce[0], nonce[1]]));
    let mut guesses = 0;
    let mut guess_at = Instant::now();
    loop {
        tokio::select! {
            Some(result) = jobs.next() => match result {
                Ok(selected) => return Ok(selected),
                Err(e) => {
                    if let Some(c) = e.downcast_ref::<Counts>() {
                        totals.sent += c.sent;
                        totals.errors += c.errors;
                        totals.authenticated += c.authenticated;
                    }
                }
            },
            _ = tokio::time::sleep_until(guess_at), if guesses < GUESSES && guess_at < deadline => {
                for _ in 0..GUESS_BATCH {
                    let mut guess = peer;
                    guess.set_port(guessed_port(base, guesses));
                    guesses += 1;
                    match primary.send_to(&probe, guess).await { Ok(_) => totals.sent += 1, Err(_) => totals.errors += 1 }
                }
                guess_at = Instant::now() + GUESS_INTERVAL;
            }
            else => return Err(totals.into()),
        }
    }
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
    pub async fn select(
        self,
        primary: Arc<UdpSocket>,
        peer: SocketAddr,
        listen: bool,
    ) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
        self.select_within(primary, peer, listen, Duration::from_secs(6))
            .await
    }

    pub async fn select_within(
        self,
        primary: Arc<UdpSocket>,
        peer: SocketAddr,
        listen: bool,
        window: Duration,
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
        let deadline = Instant::now() + window;
        let guesser = primary.clone();
        let mut jobs: FuturesUnordered<_> = std::iter::once(primary)
            .chain(self.local.sockets)
            .map(|s| check_socket(s, destinations.clone(), listen, &key, deadline, false).boxed())
            .collect();
        jobs.push(predict(&guesser, peer, listen, &key, deadline).boxed());
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
                        totals.sockets += c.sockets;
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

async fn check_socket(
    socket: Arc<UdpSocket>,
    mut peers: Vec<SocketAddr>,
    listen: bool,
    key: &auth::Key,
    deadline: Instant,
    predicted: bool,
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
                    match socket.send_to(&probe, peers[cursor]).await { Ok(_) => sent += 1, Err(_) => errors += 1 }
                    cursor = (cursor + 1) % peers.len();
                }
                next = Instant::now() + Duration::from_millis(if predicted { 1000 } else if start.elapsed().as_millis() < 250 { 90 } else { 350 });
            }
            received = socket.recv_from(&mut buf) => {
                let (n, from) = match received {
                    Ok(pair) => pair,
                    Err(e) if matches!(e.kind(), std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionRefused) => continue,
                    Err(e) => return Err(e.into()),
                };
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
                                socket.send_to(&packet((kind ^ 2) + 1, &original, key), from).await?;
                            }
                            socket.send_to(&probe, from).await?;
                        } else if request {
                            let candidate = &mut pending[index];
                            candidate.request = Some(incoming);
                            let response = if candidate.retry_challenge {
                                packet(kind, &candidate.challenge, key)
                            } else {
                                packet(buf[4] + 1, &incoming, key)
                            };
                            candidate.retry_challenge = !candidate.retry_challenge;
                            socket.send_to(&response, from).await?;
                        }
                    } else if peers.len() + pending.len() < max_peers
                        && (request || (buf[4] == kind + 1 && incoming == nonce)) {
                        let mut challenge = [0; 8];
                        randombytes::randombytes_into(&mut challenge);
                        pending.push(PendingAddress {
                            addr: from, challenge, request: request.then_some(incoming), retry_challenge: false,
                        });
                        socket.send_to(&packet(kind, &challenge, key), from).await?;
                    }
                    continue;
                }
                if !known && peers.len() >= max_peers { continue; }
                if buf[4] == (kind ^ 2) {
                    if !authenticated.contains(&from) {
                        authenticated.push(from);
                        // The peer's guess opened this pair; answer on it without waiting a turn.
                        if known && predicted { socket.send_to(&probe, from).await?; }
                    }
                    let reply = packet(buf[4] + 1, &buf[5..13], key);
                    socket.send_to(&reply, from).await?;
                } else if buf[4] == kind + 1 && buf[5..13] == nonce && known && !listen {
                    socket.connect(from).await?;
                    return Ok((socket, None));
                } else if buf[4] != kind + 1 || buf[5..13] != nonce { continue; }
                // A valid packet from a different source port supplies a peer-reflexive candidate.
                if !known { peers.push(from); socket.send_to(&probe, from).await?; }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    async fn direct_kcp_recovers_when_no_advertised_port_reaches_the_peer() {
        async fn bind() -> Arc<UdpSocket> {
            Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap())
        }
        let (left, right) = (bind().await, bind().await);
        // Each side was told a port the other does not use, as behind a NAT that maps every
        // destination to a new port.
        let (stale_left, stale_right) = (bind().await, bind().await);
        let key = auth::gen_key();
        let paths = || Paths { local: Candidates::default(), ports: vec![], key: key.clone() };
        let host = async {
            let (socket, syn) = paths().select(right, stale_left.local_addr().unwrap(), true).await.unwrap();
            KcpStream::accept(socket, Duration::from_secs(2), syn).await.unwrap()
        };
        let client = async {
            let window = Duration::from_secs(3);
            let (socket, _) = paths().select_within(left, stale_right.local_addr().unwrap(), false, window).await.unwrap();
            KcpStream::connect(socket, Duration::from_secs(2)).await.unwrap()
        };
        let ((_a, mut host), (_b, mut client)) = tokio::join!(host, client);
        client.send_raw(vec![42; 4500]).await.unwrap();
        assert_eq!(host.next_timeout(2000).await.unwrap().unwrap().as_ref(), &[42; 4500]);
        host.send_raw(vec![17; 4500]).await.unwrap();
        assert_eq!(client.next_timeout(2000).await.unwrap().unwrap().as_ref(), &[17; 4500]);
    }

    #[tokio::test]
    async fn silent_peer_releases_the_relay_fallback_when_the_window_ends() {
        let socket = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let silent = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let paths = Paths { local: Candidates::default(), ports: vec![], key: auth::gen_key() };
        let start = Instant::now();
        let result = paths.select_within(socket, silent.local_addr().unwrap(), false, Duration::from_secs(1)).await;
        assert!(result.unwrap_err().downcast_ref::<Counts>().is_some_and(|c| c.sent > 0));
        assert!(start.elapsed() < Duration::from_millis(1500));
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
