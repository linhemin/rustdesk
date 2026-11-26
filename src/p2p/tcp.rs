use super::Interface;
use hbb_common::{
    socket_client,
    tokio::time::{sleep, Instant},
    Stream,
};
use std::{net::SocketAddr, time::Duration};

pub(crate) async fn connect_punch(
    peer: SocketAddr,
    local: SocketAddr,
    timeout: u64,
) -> hbb_common::ResultType<Stream> {
    if let Some(iface) = Interface::configured()
        .filter(|iface| peer.is_ipv4() && local.ip() == std::net::IpAddr::V4(iface.address))
    {
        return iface.connect(peer, local.port(), timeout).await;
    }
    if local.is_ipv6() && peer.is_ipv4() {
        // The ordinary TCP candidate needs its own IPv4 signaling socket. Do not
        // send the peer address to an external DNS64 helper on this attempt.
        #[cfg(target_vendor = "apple")]
        if let SocketAddr::V4(v4) = peer {
            let translated = super::ordinary_udp::system_ipv6_destination(v4).await?;
            return socket_client::connect_tcp_local(translated, Some(local), timeout).await;
        }
        hbb_common::bail!("IPv4 TCP punch needs an IPv4 signaling source");
    }
    socket_client::connect_tcp_local(peer, Some(local), timeout).await
}

fn controller_tcp_source(
    peer: SocketAddr,
    local: SocketAddr,
    is_local: bool,
) -> Option<SocketAddr> {
    // The LAN peer already has a listener. Its route can differ from the
    // Wi-Fi, VPN or cellular route used to reach the rendezvous server.
    let lan_listener = is_local && matches!(peer.ip(), std::net::IpAddr::V4(ip) if ip.is_private());
    (!lan_listener).then_some(local)
}

pub(crate) async fn connect_controller_tcp(
    peer: SocketAddr,
    local: SocketAddr,
    is_local: bool,
    timeout: u64,
) -> hbb_common::ResultType<Stream> {
    if let Some(source) = controller_tcp_source(peer, local, is_local) {
        let deadline = Instant::now() + Duration::from_millis(timeout);
        let mut delays = [80, 200, 400].into_iter();
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            let result = connect_punch(peer, source, left.as_millis() as u64).await;
            let Some(delay) = delays.next().filter(|_| result.is_err()) else {
                return result;
            };
            let delay = Duration::from_millis(delay);
            if Instant::now() + delay >= deadline {
                return result;
            }
            // The peer may have sent its rendezvous reply just before binding its listener.
            // Retry that same mapping only after a fast failure within the original budget.
            sleep(delay).await;
        }
    }
    if let Some(iface) = Interface::configured() {
        return iface.connect(peer, 0, timeout).await;
    }
    socket_client::connect_tcp_local(peer, None, timeout).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio;

    #[tokio::test]
    async fn a_peer_that_starts_listening_after_the_reply_still_connects() {
        let late = tokio::net::TcpSocket::new_v4().unwrap();
        late.bind("127.0.0.1:0".parse().unwrap()).unwrap();
        let peer = late.local_addr().unwrap();
        let source = "127.0.0.1:0".parse().unwrap();
        let delayed = async {
            sleep(Duration::from_millis(160)).await;
            late.listen(1).unwrap().accept().await.unwrap()
        };
        let (dial, (_, received)) = hbb_common::timeout(4_000, async {
            tokio::join!(connect_controller_tcp(peer, source, false, 3_000), delayed)
        })
        .await
        .unwrap();
        assert_eq!(dial.unwrap().local_addr(), received);
    }
    #[test]
    fn a_private_listener_does_not_reuse_the_public_punch_source() {
        let signal = "[2001:db8::1]:41001".parse().unwrap();
        let lan = "192.168.1.5:49000".parse().unwrap();
        assert_eq!(controller_tcp_source(lan, signal, true), None);
        assert_eq!(controller_tcp_source(lan, signal, false), Some(signal));
    }
}
