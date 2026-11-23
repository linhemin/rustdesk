use hbb_common::{
    anyhow::Context, config::Config, protobuf::Message as _, rendezvous_proto::{
        rendezvous_message, RendezvousMessage, TestNatRequest,
    }, socket_client, timeout, tokio, ResultType, Stream,
};
use std::{net::SocketAddr, sync::Arc};

pub(super) fn routed_source(peer: SocketAddr) -> std::io::Result<SocketAddr> {
    let route = std::net::UdpSocket::bind(Config::get_any_listen_addr(peer.is_ipv4()))?;
    route.connect(peer)?;
    Ok(SocketAddr::new(route.local_addr()?.ip(), 0))
}

// hbbs pairs the ordinary IPv4 port with the source of the signaling connection.
// The IPv6 direct transport negotiates its own endpoint independently.
pub(crate) async fn ordinary_udp_socket(
    server: &str,
    verify_rendezvous: bool,
) -> ResultType<(Arc<tokio::net::UdpSocket>, SocketAddr)> {
    let original = super::rendezvous_punch_socket(server, verify_rendezvous).await?;
    if !original.0.local_addr()?.ip().is_unspecified() {
        return Ok(original);
    }
    let mut target = original.1;
    if original.1.is_ipv6() {
        let lookup = tokio::net::lookup_host(server);
        if let Ok(Ok(mut addresses)) = timeout(400, lookup).await {
            if let Some(v4) = addresses.find(
                |addr| matches!(addr, SocketAddr::V4(a) if super::usable_server_ipv4(*a.ip())),
            ) {
                if routed_source(v4).is_ok() {
                    target = v4;
                } else {
                    #[cfg(target_vendor = "apple")]
                    if let Ok(translated) = udp_peer_destination(&original.0, v4).await {
                        target = translated;
                    }
                }
            }
        }
    }
    if let Ok(source) = routed_source(target) {
        if let Ok(socket) = tokio::net::UdpSocket::bind(source).await {
            return Ok((Arc::new(socket), target));
        }
    }
    Ok(original)
}

// With native IPv6 signaling, hbbs cannot associate an IPv4 peer with our UDP port.
// Ask the authenticated hbbs for its own IPv4 listener; a STUN observer cannot carry signaling.
async fn nas_ipv4_listener(server: SocketAddr, source: SocketAddr, key: &str) -> ResultType<std::net::SocketAddrV4> {
    const SERIAL: i32 = -604181;
    let mut conn = connect_udp_observer(server, source).await?;
    if !crate::secure_tcp_with_direct_permission(&mut conn, key, true).await? || !conn.is_secured() {
        hbb_common::bail!("No authenticated direct permission");
    }
    let mut request = RendezvousMessage::new();
    request.set_test_nat_request(TestNatRequest { serial: SERIAL, ..Default::default() });
    conn.send(&request).await?;
    let bytes = conn.next().await.context("No rendezvous listener reply")??;
    if let Some(rendezvous_message::Union::TestNatResponse(reply)) = RendezvousMessage::parse_from_bytes(&bytes)?.union {
        if let Some(config) = reply.cu.into_option().filter(|v| v.serial == SERIAL) {
            if let [endpoint] = config.rendezvous_servers.as_slice() {
                let endpoint: std::net::SocketAddrV4 = endpoint.parse()?;
                if endpoint.port() != 0 && (super::usable_server_ipv4(*endpoint.ip())
                    || server.ip().is_loopback() && endpoint.ip().is_loopback()) {
                    return Ok(endpoint);
                }
            }
        }
    }
    hbb_common::bail!("No IPv4 rendezvous listener advertised")
}

async fn mapped_listener(target: SocketAddr) -> ResultType<(Arc<tokio::net::UdpSocket>, SocketAddr, u16)> {
    #[cfg(target_os = "windows")]
    let socket = if let Some(iface) = super::Interface::configured().filter(|_| target.is_ipv4()) {
        crate::platform::bind_p2p_stun_udp(iface.address, iface.index, 0, 0)
            .context("Selected UDP interface unavailable")?
    } else {
        tokio::net::UdpSocket::bind(routed_source(target)?).await?
    };
    #[cfg(not(target_os = "windows"))]
    let socket = tokio::net::UdpSocket::bind(routed_source(target)?).await?;
    let port = super::udp_mapping::observe_v4_port(&socket, target).await?;
    Ok((Arc::new(socket), target, port))
}

pub(crate) async fn controller_socket(server: &str, key: &str, recover_ipv4: bool) -> ResultType<(Arc<tokio::net::UdpSocket>, SocketAddr, u16)> {
    let (socket, target) = ordinary_udp_socket(server, false).await?;
    if recover_ipv4 {
        // A tunnel can expose an IPv4 socket locally and still reach hbbs over IPv6.
        // Keep the socket and port only when the NAS observed the right address family.
        if let Ok(port) = super::udp_mapping::observe_v4_port(&socket, target).await {
            return Ok((socket, target, port));
        }
        if let Ok(Ok(v4)) = timeout(2_000, nas_ipv4_listener(target, socket.local_addr()?, key)).await {
            if let Ok(mapped) = mapped_listener(SocketAddr::V4(v4)).await {
                return Ok(mapped);
            }
            #[cfg(target_vendor = "apple")]
            if let Ok(nat64) = system_ipv6_destination(v4).await {
                if let Ok(mapped) = mapped_listener(nat64).await {
                    return Ok(mapped);
                }
            }
        }
    }
    Ok((socket, target, 0))
}

pub(crate) async fn connect_udp_observer(
    observer: SocketAddr,
    source: SocketAddr,
) -> ResultType<Stream> {
    #[cfg(target_os = "windows")]
    if let Some(iface) =
        super::Interface::configured().filter(|i| source.ip() == std::net::IpAddr::V4(i.address))
    {
        return iface.connect(observer, 0, 1_500).await;
    }
    let local = SocketAddr::new(source.ip(), 0);
    socket_client::connect_tcp_local(observer, Some(local), 1_500).await
}

pub(crate) fn observed_peer(signaling: SocketAddr, ipv4: u32, verified: bool) -> SocketAddr {
    let ip = std::net::Ipv4Addr::from(ipv4);
    if verified && signaling.is_ipv6() && super::usable_server_ipv4(ip) && !ip.is_private() {
        SocketAddr::from((ip, signaling.port()))
    } else { signaling }
}

// Only the selected hbbs address can be an alternate. Preserve its reported
// inside address separately so IP access checks still see the signaling peer.
pub(crate) fn peer_candidate(peer: SocketAddr, server: SocketAddr, hint: &[u8]) -> SocketAddr {
    if let (SocketAddr::V4(peer4), SocketAddr::V4(server4)) = (peer, server) {
        if peer4.ip().is_private()
            && !server4.ip().is_private()
            && super::usable_server_ipv4(*server4.ip())
            && hint == server4.ip().octets()
        {
            return SocketAddr::from((*server4.ip(), peer.port()));
        }
    }
    peer
}

pub(crate) async fn connect_peer(
    socket: &tokio::net::UdpSocket,
    peer: SocketAddr,
) -> ResultType<()> {
    let peer = udp_peer_destination(socket, peer).await?;
    socket.connect(peer).await?;
    Ok(())
}

#[cfg(target_vendor = "apple")]
pub(crate) async fn udp_peer_destination(
    socket: &tokio::net::UdpSocket,
    peer: SocketAddr,
) -> ResultType<SocketAddr> {
    let SocketAddr::V4(v4) = peer else {
        return Ok(peer);
    };
    if !socket.local_addr()?.is_ipv6() {
        return Ok(peer);
    }
    system_ipv6_destination(v4).await
}

#[cfg(not(target_vendor = "apple"))]
pub(crate) async fn udp_peer_destination(_: &tokio::net::UdpSocket, peer: SocketAddr) -> ResultType<SocketAddr> {
    Ok(peer)
}

#[cfg(target_vendor = "apple")]
pub(crate) async fn system_ipv6_destination(v4: std::net::SocketAddrV4) -> ResultType<SocketAddr> {
    use hbb_common::libc;
    use std::{ffi::CString, net::Ipv6Addr, ptr};

    // On DNS64 networks Darwin synthesizes a routable IPv6 address even for
    // a numeric IPv4 literal. Rust's lookup_host short-circuits numeric input.
    let lookup = tokio::task::spawn_blocking(move || -> Option<SocketAddr> {
        let host = CString::new(v4.ip().to_string()).ok()?;
        let hints = libc::addrinfo {
            ai_flags: libc::AI_DEFAULT,
            ai_family: libc::AF_UNSPEC,
            ai_socktype: libc::SOCK_DGRAM,
            ..unsafe { std::mem::zeroed() }
        };
        let mut first = ptr::null_mut();
        // The list and its entries belong to getaddrinfo until freeaddrinfo below.
        unsafe {
            if libc::getaddrinfo(host.as_ptr(), ptr::null(), &hints, &mut first) != 0 {
                return None;
            }
            let mut cur = first;
            let mut translated = None;
            while let Some(entry) = cur.as_ref() {
                if entry.ai_family == libc::AF_INET6
                    && !entry.ai_addr.is_null()
                    && entry.ai_addrlen as usize >= std::mem::size_of::<libc::sockaddr_in6>()
                {
                    let addr = &*entry.ai_addr.cast::<libc::sockaddr_in6>();
                    translated = Some(SocketAddr::new(
                        Ipv6Addr::from(addr.sin6_addr.s6_addr).into(),
                        v4.port(),
                    ));
                    break;
                }
                cur = entry.ai_next;
            }
            libc::freeaddrinfo(first);
            translated
        }
    });
    timeout(1_500, lookup)
        .await??
        .context("No system IPv6 route to the IPv4 peer")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_configured_rendezvous_can_supplement_a_private_peer() {
        let inside = "192.168.5.8:48214".parse().unwrap();
        let hbbs = "8.8.8.8:21116".parse().unwrap();
        assert_eq!(
            peer_candidate(inside, hbbs, &[8, 8, 8, 8]),
            "8.8.8.8:48214".parse().unwrap()
        );
        assert_eq!(peer_candidate(inside, hbbs, &[1, 2, 3, 4]), inside);
        assert_eq!(peer_candidate(inside, hbbs, &[]), inside);
    }

    #[tokio::test]
    async fn signal_reuses_the_mapping_source_and_observer() {
        let hbbs = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let observer = hbbs.local_addr().unwrap();
        let mapped = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let source = mapped.local_addr().unwrap();
        let stream = connect_udp_observer(observer, source).await.unwrap();
        let (_, observed) = hbbs.accept().await.unwrap();
        assert_eq!(observed.ip(), source.ip());
        assert_eq!(stream.local_addr(), observed);
    }
}
