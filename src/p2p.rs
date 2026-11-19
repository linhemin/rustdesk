use base::config::keys;
use hbb_common::{config::Config, socket_client, Stream};
use std::net::{Ipv4Addr, SocketAddr};

#[cfg(target_os = "windows")]
#[path = "p2p/stun.rs"]
mod stun;
#[cfg(target_os = "windows")]
pub(crate) use stun::configured_stun_provider;

#[cfg(target_os = "windows")]
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

#[cfg(target_os = "windows")]
fn physical_interfaces() -> impl Iterator<Item = default_net::Interface> {
    default_net::get_interfaces()
        .into_iter()
        .filter(|iface| crate::platform::is_physical_p2p_interface(iface.index))
}

#[cfg(all(target_os = "windows", feature = "flutter"))]
pub(crate) fn interface_choices() -> String {
    let mut choices = std::collections::BTreeMap::new();
    for iface in physical_interfaces() {
        let name = iface
            .friendly_name
            .or(iface.description)
            .unwrap_or(iface.name);
        for network in iface.ipv4 {
            if network.addr.is_private() && (1..=32).contains(&network.prefix_len) {
                choices.insert(network.addr.to_string(), name.clone());
            }
        }
    }
    serde_json::to_string(&choices).unwrap_or_else(|_| "{}".to_owned())
}

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
            let mut matches = physical_interfaces().filter_map(|iface| {
                let network = iface.ipv4.iter().find(|network| network.addr == address)?;
                (network.prefix_len > 0 && network.prefix_len <= 32).then_some(Self {
                    address,
                    prefix: network.prefix_len,
                    index: iface.index,
                })
            });
            // The GUI stores the source address. Two adapters with the same address do not
            // identify the user's choice, so let the ordinary route handle that case.
            let selected = matches.next()?;
            return matches.next().is_none().then_some(selected);
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

#[cfg(any(target_os = "windows", test))]
fn usable_server_ipv4(ip: Ipv4Addr) -> bool {
    let [first, second, ..] = ip.octets();
    first != 0
        && !ip.is_loopback()
        && !ip.is_link_local()
        && first < 224
        && !(first == 198 && (18..=19).contains(&second))
}

#[cfg(target_os = "windows")]
struct ResolvedServer {
    host: String,
    interface_index: u32,
    address: Ipv4Addr,
    expires_at: Instant,
}

#[cfg(target_os = "windows")]
async fn resolve_server_ipv4(host: &str, index: u32, timeout: u64) -> Option<Ipv4Addr> {
    static RESOLVED: Mutex<Option<ResolvedServer>> = Mutex::new(None);
    if let Ok(ip) = host.parse() {
        return usable_server_ipv4(ip).then_some(ip);
    }
    if let Some(address) = RESOLVED
        .lock()
        .ok()?
        .as_ref()
        .filter(|entry| {
            entry.interface_index == index
                && entry.host == host
                && entry.expires_at > Instant::now()
        })
        .map(|entry| entry.address)
    {
        return Some(address);
    }

    let query_name = host.to_owned();
    let query = hbb_common::tokio::task::spawn_blocking(move || {
        crate::platform::resolve_p2p_ipv4(&query_name, index)
    });
    let addresses = hbb_common::timeout(timeout.min(1_500), query)
        .await
        .ok()?
        .ok()?;
    let (address, ttl) = addresses
        .into_iter()
        .find(|(ip, _)| usable_server_ipv4(*ip) && !ip.is_private())?;
    hbb_common::log::debug!("Resolved {host} to {address} on physical interface {index}");
    *RESOLVED.lock().ok()? = Some(ResolvedServer {
        host: host.to_owned(),
        interface_index: index,
        address,
        expires_at: Instant::now() + Duration::from_secs(u64::from(ttl.clamp(1, 60))),
    });
    Some(address)
}

#[cfg(target_os = "windows")]
async fn configured_server_endpoint(
    server: &str,
    iface: Interface,
    timeout: u64,
) -> Option<SocketAddr> {
    let (host, port) = server.rsplit_once(':')?;
    let configured = Config::get_rendezvous_server();
    let (configured_host, _) = configured.rsplit_once(':')?;
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if !host.eq_ignore_ascii_case(configured_host.trim_end_matches('.')) {
        return None;
    }
    let ip = resolve_server_ipv4(&host, iface.index, timeout)
        .await
        .or_else(|| {
            Config::get_option(keys::OPTION_P2P_SERVER_IP)
                .parse()
                .ok()
                .filter(|ip| usable_server_ipv4(*ip))
        })?;
    Some(SocketAddr::from((ip, port.parse::<u16>().ok()?)))
}

pub(crate) async fn connect_rendezvous(
    server: &str,
    local: Option<SocketAddr>,
    timeout: u64,
) -> hbb_common::ResultType<Stream> {
    #[cfg(target_os = "windows")]
    if let Some(iface) = Interface::configured().filter(|iface| {
        local.map_or(true, |addr| {
            addr.ip() == std::net::IpAddr::V4(iface.address)
        })
    }) {
        if let Some(endpoint) = configured_server_endpoint(server, iface, timeout).await {
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

// The controller and controlled side reuse their local rendezvous TCP port for the punch.
// A v6 registration on one side and a v4-only peer on the other do not form a TCP pair.
pub(crate) const FAMILY_RETRY_MS: u64 = 1_350;

async fn connect_family(server: &str, ipv4: bool) -> hbb_common::ResultType<Stream> {
    #[cfg(target_os = "windows")]
    if let Some(iface) = Interface::configured().filter(|_| ipv4) {
        // A physical pin has its own DNS. Do not bind a system resolver's Clash FakeIP
        // to the physical interface. Unpinned connections below use the system route.
        if let Some(endpoint) = configured_server_endpoint(server, iface, 400).await {
            if let Ok(conn) = iface.connect(endpoint, 0, 350).await {
                return Ok(conn);
            }
        }
    }
    // Only addresses returned by the system for this hbbs. An iPhone VPN and DNS64
    // retain control of routing and resolution; do not synthesize a DNS name here.
    let endpoints = hbb_common::tokio::net::lookup_host(server).await?;
    for endpoint in endpoints.filter(|addr| addr.is_ipv4() == ipv4).take(4) {
        if let Ok(conn) = socket_client::connect_tcp_local(endpoint, None, 350).await {
            if matches!(conn, Stream::Tcp(_)) && conn.local_addr().is_ipv4() == ipv4 {
                return Ok(conn);
            }
        }
    }
    hbb_common::bail!("No usable rendezvous TCP address in the peer's address family");
}

pub(crate) async fn authenticated_family_rendezvous(
    server: &str,
    ipv4: bool,
    key: &str,
    deadline_ms: u64,
) -> hbb_common::ResultType<Stream> {
    if Config::is_proxy() || hbb_common::config::use_ws() {
        hbb_common::bail!("Direct TCP rendezvous is disabled");
    }
    hbb_common::timeout(deadline_ms, async {
        let mut conn = connect_family(server, ipv4).await?;
        crate::secure_tcp_required(&mut conn, key).await?;
        if !conn.is_secured() {
            hbb_common::bail!("Rendezvous key exchange was not authenticated");
        }
        Ok(conn)
    })
    .await?
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
    use hbb_common::tokio;

    #[tokio::test]
    async fn family_selection_uses_only_the_requested_tcp_address_family() {
        for (listen, ipv4) in [("127.0.0.1:0", true), ("[::1]:0", false)] {
            let listener = tokio::net::TcpListener::bind(listen).await.unwrap();
            let endpoint = listener.local_addr().unwrap().to_string();
            assert!(connect_family(&endpoint, !ipv4).await.is_err());
            let conn = connect_family(&endpoint, ipv4).await.unwrap();
            let (_, source) = listener.accept().await.unwrap();
            assert_eq!(source.is_ipv4(), ipv4);
            assert_eq!(conn.local_addr(), source);
        }
    }

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

    #[test]
    fn fake_ipv4_is_never_a_direct_server_candidate() {
        assert!(!usable_server_ipv4(Ipv4Addr::new(198, 18, 0, 1)));
        assert!(!usable_server_ipv4(Ipv4Addr::new(198, 19, 255, 254)));
        assert!(usable_server_ipv4(Ipv4Addr::new(8, 8, 8, 8)));
    }
}
