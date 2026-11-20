//! A short PCP MAP lease for one authenticated peer's IP (RFC 6887 sections 11 and 13.3).
//! The control socket is separate from the ICE data socket named by MAP's internal port.
use super::{current_interface, public_stun_address, Interface};
use hbb_common::{
    tokio::{
        self,
        net::UdpSocket,
        sync::{watch, Semaphore},
        time::{sleep, timeout},
    },
    webrtc::{InterfaceStunConn, InterfaceStunResult},
};
use std::{
    any::Any,
    io::{Error, ErrorKind},
    net::{IpAddr, Ipv4Addr, SocketAddr, SocketAddrV4},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

const LIFETIME: u32 = 120;
const RESPONSE_WAIT: Duration = Duration::from_millis(1500);
const RETRY_WAIT: Duration = Duration::from_secs(90);

#[derive(Clone, Copy, PartialEq, Eq)]
struct Gateway {
    index: u32,
    source: Ipv4Addr,
    router: Ipv4Addr,
}

fn gateway_for(interface: Interface) -> Option<Gateway> {
    let selected = current_interface()?;
    if selected.index != interface.index || selected.address != interface.address {
        return None;
    }
    let adapter = default_net::get_interfaces()
        .into_iter()
        .find(|i| i.index == interface.index)?;
    let IpAddr::V4(router) = adapter.gateway?.ip_addr else {
        return None;
    };
    interface.on_link(router).then_some(Gateway {
        index: interface.index,
        source: interface.address,
        router,
    })
}

struct Map {
    client: SocketAddrV4,
    peer: Ipv4Addr,
    nonce: [u8; 12],
}

impl Map {
    fn packet(&self, lifetime: u32, external: Option<SocketAddrV4>) -> Vec<u8> {
        let mut bytes = vec![0; if lifetime == 0 { 60 } else { 84 }];
        bytes[0] = 2; // PCP version
        bytes[1] = 1; // MAP
        bytes[4..8].copy_from_slice(&lifetime.to_be_bytes());
        bytes[8..24].copy_from_slice(&self.client.ip().to_ipv6_mapped().octets());
        bytes[24..36].copy_from_slice(&self.nonce);
        bytes[36] = 17; // UDP
        bytes[40..42].copy_from_slice(&self.client.port().to_be_bytes());
        let endpoint = external.unwrap_or(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0));
        bytes[42..44].copy_from_slice(&endpoint.port().to_be_bytes());
        bytes[44..60].copy_from_slice(&endpoint.ip().to_ipv6_mapped().octets());
        if lifetime != 0 {
            bytes[60] = 3; // mandatory-to-process FILTER, never retry without it
            bytes[62..64].copy_from_slice(&20u16.to_be_bytes());
            bytes[65] = 128; // exact IPv4-mapped /128, any source port on that IP
            bytes[68..84].copy_from_slice(&self.peer.to_ipv6_mapped().octets());
        }
        bytes
    }

    fn response(&self, bytes: &[u8]) -> Option<(SocketAddrV4, u32)> {
        if !(60..=1100).contains(&bytes.len())
            || bytes.len() % 4 != 0
            || bytes[..2] != [2, 0x81]
            || bytes[3] != 0
            || bytes[24..36] != self.nonce
            || bytes[36] != 17
            || bytes[40..42] != self.client.port().to_be_bytes()
            || bytes[44..56] != [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff]
        {
            return None;
        }
        let lifetime = u32::from_be_bytes(bytes[4..8].try_into().ok()?);
        let external = SocketAddrV4::new(
            Ipv4Addr::new(bytes[56], bytes[57], bytes[58], bytes[59]),
            u16::from_be_bytes([bytes[42], bytes[43]]),
        );
        if !(4..=600).contains(&lifetime)
            || external.port() == 0
            || !public_stun_address(*external.ip())
        {
            return None;
        }
        let mut options = &bytes[60..];
        while !options.is_empty() {
            let header = options.get(..4)?;
            let length = usize::from(u16::from_be_bytes([header[2], header[3]]));
            let value = options.get(4..4 + length)?;
            if header[0] == 3 {
                if length != 20
                    || value[1..4] != [128, 0, 0]
                    || value[4..] != self.peer.to_ipv6_mapped().octets()
                {
                    return None;
                }
            } else if header[0] < 128 {
                return None;
            }
            options = options.get(4 + ((length + 3) & !3)..)?;
        }
        Some((external, lifetime))
    }
}

// Arming before the first send also cleans up a MAP whose reply was lost or whose
// candidate task was cancelled. A deletion names our exact data port, protocol and nonce.
struct Lease {
    control: UdpSocket,
    // Keep the local UDP port reserved up to and including the deletion request.
    data: Arc<UdpSocket>,
    map: Map,
    external: Option<SocketAddrV4>,
}

impl Lease {
    async fn request(&mut self) -> Option<(SocketAddrV4, u32)> {
        let request = self.map.packet(LIFETIME, self.external);
        self.control.send(&request).await.ok()?;
        let mut buffer = [0; 1101];
        timeout(RESPONSE_WAIT, async {
            loop {
                let count = self.control.recv(&mut buffer).await.ok()?;
                if count >= 60
                    && buffer[..2] == [2, 0x81]
                    && buffer[24..36] == self.map.nonce
                    && buffer[3] != 0
                {
                    return None;
                }
                if let Some(grant) = self.map.response(&buffer[..count]) {
                    self.external = Some(grant.0);
                    return Some(grant);
                }
            }
        })
        .await
        .ok()?
    }
}

impl Drop for Lease {
    fn drop(&mut self) {
        let _ = self.control.try_send(&self.map.packet(0, self.external));
    }
}

struct PeerSocket {
    data: Arc<UdpSocket>,
    peer: Ipv4Addr,
    stop: watch::Sender<bool>,
    valid: watch::Receiver<bool>,
}

impl PeerSocket {
    fn usable(&self) -> InterfaceStunResult<()> {
        if *self.stop.borrow() || !*self.valid.borrow() {
            return Err(Error::new(ErrorKind::NotConnected, "PCP candidate retired").into());
        }
        Ok(())
    }

    fn allows(&self, address: SocketAddr) -> InterfaceStunResult<()> {
        self.usable()?;
        if address.ip() != IpAddr::V4(self.peer) {
            return Err(Error::new(ErrorKind::PermissionDenied, "Outside PCP peer filter").into());
        }
        Ok(())
    }
}

#[async_trait::async_trait]
impl InterfaceStunConn for PeerSocket {
    async fn connect(&self, target: SocketAddr) -> InterfaceStunResult<()> {
        self.allows(target)?;
        Ok(self.data.connect(target).await?)
    }
    async fn recv(&self, buf: &mut [u8]) -> InterfaceStunResult<usize> {
        self.recv_from(buf).await.map(|(n, _)| n)
    }
    async fn recv_from(&self, buf: &mut [u8]) -> InterfaceStunResult<(usize, SocketAddr)> {
        self.usable()?;
        let mut valid = self.valid.clone();
        loop {
            tokio::select! {
                _ = valid.wait_for(|v| !*v) => {
                    return Err(Error::new(ErrorKind::NotConnected, "PCP candidate retired").into());
                }
                result = self.data.recv_from(buf) => {
                    let (n, source) = result?;
                    if source.ip() == IpAddr::V4(self.peer) {
                        return Ok((n, source));
                    }
                }
            }
        }
    }
    async fn send(&self, buf: &[u8]) -> InterfaceStunResult<usize> {
        self.allows(self.data.peer_addr()?)?;
        Ok(self.data.send(buf).await?)
    }
    async fn send_to(&self, buf: &[u8], target: SocketAddr) -> InterfaceStunResult<usize> {
        self.allows(target)?;
        Ok(self.data.send_to(buf, target).await?)
    }
    fn local_addr(&self) -> InterfaceStunResult<SocketAddr> {
        Ok(self.data.local_addr()?)
    }
    fn remote_addr(&self) -> Option<SocketAddr> {
        self.data.peer_addr().ok()
    }
    async fn close(&self) -> InterfaceStunResult<()> {
        self.stop.send_replace(true);
        Ok(())
    }
    fn as_any(&self) -> &(dyn Any + Send + Sync) {
        self
    }
}

static BACKOFF: Mutex<Option<(Gateway, Instant)>> = Mutex::new(None);
static SLOTS: Semaphore = Semaphore::const_new(4);

pub(super) async fn bind_peer(
    interface: Interface,
    peer: Ipv4Addr,
    min: u16,
    max: u16,
) -> Option<(Arc<dyn InterfaceStunConn + Send + Sync>, SocketAddrV4)> {
    if !public_stun_address(peer) {
        return None;
    }
    let gateway = tokio::task::spawn_blocking(move || gateway_for(interface))
        .await
        .ok()??;
    if BACKOFF
        .lock()
        .ok()?
        .as_ref()
        .is_some_and(|(g, until)| *g == gateway && *until > Instant::now())
    {
        return None;
    }
    let permit = SLOTS.try_acquire().ok()?;
    let data = Arc::new(crate::platform::bind_p2p_stun_udp(
        gateway.source,
        gateway.index,
        min,
        max,
    )?);
    let SocketAddr::V4(client) = data.local_addr().ok()? else {
        return None;
    };
    let control = crate::platform::bind_p2p_stun_udp(gateway.source, gateway.index, 0, 0)?;
    control.connect((gateway.router, 5351)).await.ok()?;
    let lease = Lease {
        control,
        data,
        map: Map {
            client,
            peer,
            nonce: hbb_common::rand::random(),
        },
        external: None,
    };
    let result = start(lease, permit, move || {
        gateway_for(interface) == Some(gateway)
    })
    .await;
    if result.is_none() {
        *BACKOFF.lock().ok()? = Some((gateway, Instant::now() + RETRY_WAIT));
    }
    result
}

async fn start(
    mut lease: Lease,
    permit: tokio::sync::SemaphorePermit<'static>,
    gateway_unchanged: impl Fn() -> bool + Copy + Send + 'static,
) -> Option<(Arc<dyn InterfaceStunConn + Send + Sync>, SocketAddrV4)> {
    let peer = lease.map.peer;
    let data = lease.data.clone();
    let (external, mut lifetime) = lease.request().await?;
    if !tokio::task::spawn_blocking(gateway_unchanged).await.ok()? {
        return None;
    }
    let (stop, mut end) = watch::channel(false);
    let (alive, valid) = watch::channel(true);
    tokio::spawn(async move {
        let _permit = permit;
        loop {
            tokio::select! {
                _ = end.changed() => break,
                _ = sleep(Duration::from_secs(u64::from(lifetime) / 2)) => {}
            }
            if !tokio::task::spawn_blocking(gateway_unchanged)
                .await
                .unwrap_or(false)
            {
                break;
            }
            let renewed = tokio::select! {
                _ = end.changed() => break,
                reply = lease.request() => reply,
            };
            match renewed {
                Some((address, seconds)) if address == external => lifetime = seconds,
                _ => break,
            }
        }
        alive.send_replace(false);
        // Dropping the lease releases the mapping while its control socket is still bound.
    });
    Some((
        Arc::new(PeerSocket {
            data,
            peer,
            stop,
            valid,
        }),
        external,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assigned(request: &[u8], external: SocketAddrV4, lifetime: u32) -> Vec<u8> {
        let mut reply = request.to_vec();
        reply[1] |= 0x80;
        reply[4..8].copy_from_slice(&lifetime.to_be_bytes());
        reply[8..24].fill(0);
        reply[42..44].copy_from_slice(&external.port().to_be_bytes());
        reply[44..60].copy_from_slice(&external.ip().to_ipv6_mapped().octets());
        reply
    }

    #[test]
    fn map_matches_owner_ipv4_udp_tuple_and_exact_filter() {
        let m = Map {
            client: "192.168.1.8:49987".parse().unwrap(),
            peer: "8.8.4.4".parse().unwrap(),
            nonce: [0x52; 12],
        };
        let address = "1.1.1.1:45001".parse::<SocketAddrV4>().unwrap();
        let request = m.packet(LIFETIME, None);
        assert_eq!(request.len(), 84);
        assert_eq!(request[36], 17);
        assert_eq!(
            request[44..60],
            Ipv4Addr::UNSPECIFIED.to_ipv6_mapped().octets()
        );
        assert_eq!(&request[60..68], &[3, 0, 0, 20, 0, 128, 0, 0]);
        assert_eq!(request[68..84], m.peer.to_ipv6_mapped().octets());
        let ok = assigned(&request, address, 120);
        assert_eq!(m.response(&ok), Some((address, 120)));
        // FILTER must be processed or the gateway must fail the entire request. An echo is optional.
        assert_eq!(m.response(&ok[..60]), Some((address, 120)));
        for index in [1, 3, 24, 36, 40, 44, 60, 63, 65, 66, 83] {
            let mut bad = ok.clone();
            bad[index] ^= 1;
            assert!(m.response(&bad).is_none(), "accepted changed byte {index}");
        }
        for addr in ["100.64.0.7:41000", "10.2.0.7:41000", "1.1.1.1:0"] {
            assert!(m
                .response(&assigned(&request, addr.parse().unwrap(), 120))
                .is_none());
        }
        for lifetime in [0, 1, 3600, u32::MAX] {
            assert!(m.response(&assigned(&request, address, lifetime)).is_none());
        }
        let remove = m.packet(0, Some(address));
        assert_eq!(remove.len(), 60);
        assert_eq!(&remove[4..8], &[0; 4]);
        assert_eq!(&remove[24..36], &m.nonce);
        assert_eq!(&remove[40..42], &m.client.port().to_be_bytes());
    }

    async fn wire_fixture() -> (UdpSocket, Lease) {
        let gateway = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let control = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        control
            .connect(gateway.local_addr().unwrap())
            .await
            .unwrap();
        let data = Arc::new(UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap());
        let SocketAddr::V4(client) = data.local_addr().unwrap() else {
            unreachable!()
        };
        (
            gateway,
            Lease {
                data,
                control,
                map: Map {
                    client,
                    peer: Ipv4Addr::LOCALHOST,
                    nonce: [3; 12],
                },
                external: None,
            },
        )
    }

    #[tokio::test]
    async fn granted_port_carries_peer_data_and_releases_without_a_filter() {
        let (gateway, lease) = wire_fixture().await;
        let addr = SocketAddr::V4(lease.map.client);
        let external: SocketAddrV4 = "1.1.1.1:48001".parse().unwrap();
        let (renew_tx, renew_rx) = tokio::sync::oneshot::channel();
        let gateway_task = tokio::spawn(async move {
            let mut buf = [0; 128];
            for round in 0..2 {
                let (count, source) = gateway.recv_from(&mut buf).await.unwrap();
                assert_eq!(count, 84);
                assert_eq!(u16::from_be_bytes([buf[40], buf[41]]), addr.port());
                assert_eq!(buf[65], 128);
                if round == 1 {
                    assert_eq!(&buf[42..44], &external.port().to_be_bytes());
                }
                gateway
                    .send_to(&assigned(&buf[..count], external, 4), source)
                    .await
                    .unwrap();
            }
            renew_tx.send(()).unwrap();
            let (n, _) = gateway.recv_from(&mut buf).await.unwrap();
            assert_eq!(n, 60);
            assert_eq!(&buf[4..8], &0u32.to_be_bytes());
            assert_eq!(&buf[24..36], &[3; 12]);
        });
        let (socket, reported) = start(lease, SLOTS.try_acquire().unwrap(), || true)
            .await
            .unwrap();
        assert_eq!(reported, external);
        let peer = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        peer.send_to(b"ICE", addr).await.unwrap();
        let mut bytes = [0u8; 16];
        let (len, src) = socket.recv_from(&mut bytes).await.unwrap();
        assert_eq!(&bytes[..len], b"ICE");
        socket.send_to(b"OK", src).await.unwrap();
        let (n, from) = peer.recv_from(&mut bytes).await.unwrap();
        assert_eq!((&bytes[..n], from), (&b"OK"[..], addr));
        assert!(socket
            .send_to(b"x", "8.8.4.4:1234".parse().unwrap())
            .await
            .is_err());
        timeout(Duration::from_secs(6), renew_rx)
            .await
            .unwrap()
            .unwrap();
        socket.close().await.unwrap();
        timeout(Duration::from_secs(4), gateway_task)
            .await
            .unwrap()
            .unwrap();
        assert!(socket.send_to(b"x", src).await.is_err());
    }

    #[tokio::test]
    async fn cancelled_allocation_releases_only_the_outstanding_nonce_and_port() {
        let (gateway, lease) = wire_fixture().await;
        let internal = lease.map.client.port();
        let task = tokio::spawn(start(lease, SLOTS.try_acquire().unwrap(), || true));
        let mut bytes = [0u8; 128];
        let (n, source) = gateway.recv_from(&mut bytes).await.unwrap();
        assert_eq!(n, 84);
        task.abort();
        assert!(matches!(task.await, Err(e) if e.is_cancelled()));
        let (n, deleted_from) = timeout(Duration::from_secs(1), gateway.recv_from(&mut bytes))
            .await
            .unwrap()
            .unwrap();
        assert_eq!((n, deleted_from), (60, source));
        assert_eq!(&bytes[4..8], &[0; 4]);
        assert_eq!(&bytes[24..36], &[3; 12]);
        assert_eq!(&bytes[40..42], &internal.to_be_bytes());
    }
}
