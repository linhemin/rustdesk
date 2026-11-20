use super::Interface;
use hbb_common::{
    config::Config,
    tokio::{sync::Semaphore, task::spawn_blocking},
    webrtc::{InterfaceStunConn, InterfaceStunProvider, WebRTCStream},
};
use std::{
    collections::HashMap,
    net::{Ipv4Addr, SocketAddrV4},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

pub(crate) fn configured_stun_provider() -> Option<Arc<dyn InterfaceStunProvider>> {
    Some(Arc::new(PhysicalStun::new(current_interface()?)))
}

struct PhysicalStun {
    interface: Interface,
    addresses: Mutex<HashMap<String, (Ipv4Addr, Instant)>>,
}

impl PhysicalStun {
    fn new(interface: Interface) -> Self {
        Self {
            interface,
            addresses: Mutex::new(HashMap::new()),
        }
    }
}

fn current_interface() -> Option<Interface> {
    if Config::get_option("force-always-relay") == "Y" {
        return None;
    }
    Interface::configured()
}

// Only globally routed A records may leave the chosen adapter for a built-in STUN endpoint.
// Reject special-use and benchmark ranges even if the adapter's resolver returns them.
fn public_stun_address(ip: Ipv4Addr) -> bool {
    let [a, b, c, d] = ip.octets();
    super::usable_server_ipv4(ip)
        && !ip.is_private()
        && !ip.is_documentation()
        && !(a == 100 && (64..=127).contains(&b))
        && !(a == 192 && b == 88 && c == 99)
        && !(a == 192 && b == 0 && c == 0 && !matches!(d, 9 | 10))
}

#[async_trait::async_trait]
impl InterfaceStunProvider for PhysicalStun {
    fn supports_source(&self, source: Ipv4Addr) -> bool {
        source == self.interface.address
    }

    async fn resolve_for_socket(
        &self,
        source: Ipv4Addr,
        host: &str,
        server_port: u16,
    ) -> Option<SocketAddrV4> {
        if !self.supports_source(source)
            || !WebRTCStream::is_default_stun_endpoint(host, server_port)
        {
            return None;
        }
        let index = self.interface.index;
        let still_selected =
            || current_interface().is_some_and(|i| i.index == index && i.address == source);
        if !still_selected() {
            return None;
        }
        // Gathering and measuring this ICE agent use the same observer. Reuse its
        // recent physical-DNS answer so the sockets needn't race for the four DNS slots.
        let host = host.trim_end_matches('.').to_ascii_lowercase();
        if let Some(&(ip, valid_until)) = self.addresses.lock().ok()?.get(&host) {
            if Instant::now() < valid_until {
                return Some(SocketAddrV4::new(ip, server_port));
            }
        }
        // DnsQueryEx is synchronous. A cancelled gather must still account for its worker
        // until the OS query returns. No queue is needed for a supplemental candidate.
        static DNS_SLOTS: Semaphore = Semaphore::const_new(4);
        let slot = DNS_SLOTS.try_acquire().ok()?;
        let query = host.clone();
        let (addr, ttl) = spawn_blocking(move || {
            let _slot = slot;
            crate::platform::resolve_p2p_ipv4(&query, index)
                .into_iter()
                .find(|(ip, _)| public_stun_address(*ip))
        })
        .await
        .ok()??;
        // The GUI or adapter may have changed while Windows was resolving this host.
        if !still_selected() {
            return None;
        }
        if ttl > 0 {
            let valid_until = Instant::now() + Duration::from_secs(ttl.min(15).into());
            self.addresses
                .lock()
                .ok()?
                .insert(host, (addr, valid_until));
        }
        Some(SocketAddrV4::new(addr, server_port))
    }

    async fn bind_and_resolve(
        &self,
        source: Ipv4Addr,
        host: &str,
        server_port: u16,
        local_port_min: u16,
        local_port_max: u16,
    ) -> Option<(Arc<dyn InterfaceStunConn + Send + Sync>, SocketAddrV4)> {
        let destination = self.resolve_for_socket(source, host, server_port).await?;
        let socket = crate::platform::bind_p2p_stun_udp(
            source,
            self.interface.index,
            local_port_min,
            local_port_max,
        )?;
        Some((Arc::new(socket), destination))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio;

    #[test]
    fn physical_stun_accepts_only_usable_public_a_and_builtin_ports() {
        assert!(public_stun_address(Ipv4Addr::new(1, 1, 1, 1)));
        for ip in [
            "0.0.0.0",
            "10.0.0.1",
            "100.64.0.1",
            "127.0.0.1",
            "169.254.1.1",
            "192.0.0.1",
            "192.0.2.1",
            "192.88.99.1",
            "198.18.0.1",
            "224.0.0.1",
            "255.255.255.255",
        ] {
            assert!(!public_stun_address(ip.parse().unwrap()));
        }
        assert!(WebRTCStream::is_default_stun_endpoint(
            "STUN.NEXTCLOUD.COM.",
            443
        ));
        assert!(!WebRTCStream::is_default_stun_endpoint(
            "stun.nextcloud.com",
            3478
        ));
        assert!(!WebRTCStream::is_default_stun_endpoint(
            "unconfigured.invalid",
            443
        ));
        let iface = Interface {
            address: Ipv4Addr::new(10, 0, 0, 1),
            prefix: 24,
            index: 1,
        };
        let provider = PhysicalStun::new(iface);
        assert!(provider.supports_source(iface.address));
        assert!(!provider.supports_source(Ipv4Addr::new(10, 0, 0, 2)));
    }

    #[tokio::test]
    async fn unsupported_source_or_destination_declines_without_opening_a_socket() {
        let iface = Interface {
            address: Ipv4Addr::new(10, 0, 0, 1),
            prefix: 24,
            index: 1,
        };
        let provider = PhysicalStun::new(iface);
        for (source, host, port) in [
            (Ipv4Addr::new(10, 0, 0, 2), "stun.cloudflare.com", 3478),
            (iface.address, "unconfigured.invalid", 3478),
            (iface.address, "stun.cloudflare.com", 1234),
        ] {
            assert!(provider
                .resolve_for_socket(source, host, port)
                .await
                .is_none());
            assert!(provider
                .bind_and_resolve(source, host, port, 0, 0)
                .await
                .is_none());
        }
    }
}
