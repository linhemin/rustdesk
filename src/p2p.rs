use base::config::keys;
use hbb_common::{config::Config, socket_client, Stream};
use std::net::{Ipv4Addr, SocketAddr};

#[derive(Clone, Copy)]
pub(crate) struct Interface {
    pub(crate) address: Ipv4Addr,
    pub(crate) prefix: u8,
    index: u32,
}

impl Interface {
    pub(crate) fn configured() -> Option<Self> {
        #[cfg(target_os = "windows")]
        {
            if Config::is_proxy() || hbb_common::config::use_ws() {
                return None;
            }
            let address: Ipv4Addr = Config::get_option(keys::OPTION_P2P_INTERFACE_IP)
                .parse()
                .ok()?;
            if !address.is_private() {
                return None;
            }
            return default_net::get_interfaces().into_iter().find_map(|iface| {
                let network = iface.ipv4.iter().find(|network| network.addr == address)?;
                (network.prefix_len > 0 && network.prefix_len <= 32).then_some(Self {
                    address,
                    prefix: network.prefix_len,
                    index: iface.index,
                })
            });
        }
        #[cfg(not(target_os = "windows"))]
        None
    }

    pub(crate) fn on_link(self, address: Ipv4Addr) -> bool {
        let mask = u32::MAX << (32 - self.prefix);
        let host = u32::from(address) & !mask;
        address != self.address
            && address.is_private()
            && u32::from(address) & mask == u32::from(self.address) & mask
            && (self.prefix >= 31 || (host != 0 && host != !mask))
    }

    pub(crate) async fn connect(
        self,
        target: SocketAddr,
        source_port: u16,
        timeout: u64,
    ) -> hbb_common::ResultType<Stream> {
        #[cfg(target_os = "windows")]
        return crate::platform::connect_p2p_tcp(
            target,
            SocketAddr::from((self.address, source_port)),
            self.index,
            timeout,
        )
        .await;
        #[cfg(not(target_os = "windows"))]
        socket_client::connect_tcp_local(
            target,
            Some(SocketAddr::from((self.address, source_port))),
            timeout,
        )
        .await
    }
}

fn configured_server_ip(server: &str) -> Option<SocketAddr> {
    let (host, port) = server.rsplit_once(':')?;
    let configured = Config::get_rendezvous_server();
    let configured_host = configured.split(':').next()?;
    if !host.eq_ignore_ascii_case(configured_host) {
        return None;
    }
    let ip: Ipv4Addr = Config::get_option(keys::OPTION_P2P_SERVER_IP)
        .parse()
        .ok()?;
    if ip.is_unspecified() || ip.is_loopback() || ip.is_multicast() || ip.is_broadcast() {
        return None;
    }
    Some(SocketAddr::from((ip, port.parse::<u16>().ok()?)))
}

pub(crate) async fn connect_rendezvous(
    server: &str,
    local: Option<SocketAddr>,
    timeout: u64,
) -> hbb_common::ResultType<Stream> {
    if let Some((iface, endpoint)) = Interface::configured().zip(configured_server_ip(server)) {
        if local.map_or(true, |addr| {
            addr.ip() == std::net::IpAddr::V4(iface.address)
        }) {
            match iface
                .connect(
                    endpoint,
                    local.map_or(0, |addr| addr.port()),
                    timeout.min(1_500),
                )
                .await
            {
                Ok(conn) => return Ok(conn),
                Err(err) if local.is_some() => return Err(err),
                Err(err) => {
                    hbb_common::log::debug!("Physical rendezvous interface unavailable: {err}")
                }
            }
        }
    }
    match local {
        Some(local) => socket_client::connect_tcp_local(server, Some(local), timeout).await,
        None => socket_client::connect_tcp(server, timeout).await,
    }
}

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
    socket_client::connect_tcp_local(peer, Some(local), timeout).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lan_targets_are_on_the_selected_link() {
        let iface = Interface {
            address: Ipv4Addr::new(192, 168, 20, 9),
            prefix: 24,
            index: 1,
        };
        assert!(iface.on_link(Ipv4Addr::new(192, 168, 20, 10)));
        assert!(!iface.on_link(Ipv4Addr::new(192, 168, 21, 10)));
        assert!(!iface.on_link(Ipv4Addr::new(192, 168, 20, 255)));
        assert!(!iface.on_link(iface.address));
    }
}
