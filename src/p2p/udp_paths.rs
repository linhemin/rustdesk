use crate::kcp_stream::KcpStream;
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
use std::{net::SocketAddr, sync::Arc};

const EXTRA_SOCKETS: usize = 3;
const RECEIPT_SIZE: usize = 38;
const MAX_PEERS: usize = 8;

#[derive(Debug, Default)]
pub(crate) struct Counts {
    pub sockets: usize,
    pub ports: usize,
    pub sent: u32,
    pub errors: u32,
    pub authenticated: usize,
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

async fn observed_socket(source: SocketAddr, nas: SocketAddr) -> Option<(Arc<UdpSocket>, Vec<u8>)> {
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
            if n == pos + 44 && buf[pos..pos + 4] == [0xc0, 0x51, 0, 38] {
                return Some((
                    Arc::new(socket),
                    buf[pos + 4..pos + 4 + RECEIPT_SIZE].to_vec(),
                ));
            }
            return None; // An older hbbs supplied a standard binding response.
        }
    }
    None
}

impl Candidates {
    pub async fn gather(source: SocketAddr, nas: SocketAddr) -> Self {
        let mut result = Self::default();
        if source.ip().is_unspecified() {
            return result;
        }
        let mut jobs: FuturesUnordered<_> = (0..EXTRA_SOCKETS)
            .map(|_| observed_socket(source, nas))
            .collect();
        while let Some(candidate) = jobs.next().await {
            if let Some((socket, ticket)) = candidate {
                result.sockets.push(socket);
                result.tickets.extend(ticket);
            }
        }
        result
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
        let peer = super::ordinary_udp::udp_peer_destination(&primary, peer).await?;
        let mut destinations = vec![peer];
        for port in self
            .ports
            .iter()
            .take(EXTRA_SOCKETS)
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
            .map(|s| check_socket(s, destinations.clone(), listen, &key))
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

async fn check_socket(
    socket: Arc<UdpSocket>,
    mut peers: Vec<SocketAddr>,
    listen: bool,
    key: &auth::Key,
) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
    let ip = peers[0].ip();
    let mut nonce = [0; 8];
    randombytes::randombytes_into(&mut nonce);
    let kind = if listen { 2 } else { 0 };
    let probe = packet(kind, &nonce, key);
    let mut authenticated = Vec::new();
    let mut buf = [0; 1500];
    let start = Instant::now();
    let deadline = start + Duration::from_secs(6);
    let mut next = start;
    let mut sent = 0u32;
    let mut errors = 0u32;
    loop {
        tokio::select! {
            biased;
            _ = tokio::time::sleep_until(deadline) => {
                return Err(Counts { sent, errors, authenticated: authenticated.len(), ..Default::default() }.into());
            }
            _ = tokio::time::sleep_until(next) => {
                for peer in &peers {
                    match socket.send_to(&probe, peer).await { Ok(_) => sent += 1, Err(_) => errors += 1 }
                }
                next = Instant::now() + Duration::from_millis(if start.elapsed().as_millis() < 250 { 90 } else { 350 });
            }
            received = socket.recv_from(&mut buf) => {
                let (n, from) = match received {
                    Ok(pair) => pair,
                    Err(e) if matches!(e.kind(), std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionRefused) => continue,
                    Err(e) => return Err(e.into()),
                };
                if from.ip() != ip { continue; }
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
                if !known && peers.len() >= MAX_PEERS { continue; }
                if buf[4] == (kind ^ 2) {
                    if !authenticated.contains(&from) { authenticated.push(from); }
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
    async fn direct_kcp_recovers_when_the_observer_ports_do_not_reach_either_primary_socket() {
        async fn bind() -> Arc<UdpSocket> {
            Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap())
        }
        let (left, right, alternate) = (bind().await, bind().await, bind().await);
        let (unreachable_left, unreachable_right) = (bind().await, bind().await);
        let key = auth::gen_key();
        let controller = Paths {
            local: Candidates::default(),
            ports: vec![u32::from(alternate.local_addr().unwrap().port())],
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
