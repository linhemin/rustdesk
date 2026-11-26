use base::config::keys::{OPTION_RELAY_SERVER, OPTION_RELAY_SERVERS};
use hbb_common::{
    config::{Config, RELAY_PORT},
    rendezvous_proto::SessionRelayList,
};
use std::net::{IpAddr, Ipv6Addr};

pub(super) const MAX_RELAYS: usize = 8;

fn normalize(input: &str) -> Option<String> {
    let input = input.trim();
    if input.is_empty()
        || input.len() > 255
        || !input.bytes().all(|b| b.is_ascii_graphic())
        || input.contains(['@', '?', '#', '\\'])
    {
        return None;
    }
    if input.contains("://") {
        let url = url::Url::parse(input).ok()?;
        if !matches!(url.scheme(), "ws" | "wss")
            || !url.has_host()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
            || url.port() == Some(0)
        {
            return None;
        }
        let endpoint = url.to_string();
        return (endpoint.len() <= 255).then_some(endpoint);
    }
    if let Ok(ip) = input.parse::<Ipv6Addr>() {
        return Some(format!("[{ip}]:{RELAY_PORT}"));
    }
    if input.starts_with('[') {
        let (ip, rest) = input.strip_prefix('[')?.split_once(']')?;
        let ip = ip.parse::<Ipv6Addr>().ok()?;
        let port = if rest.is_empty() {
            RELAY_PORT as u16
        } else {
            rest.strip_prefix(':')?.parse().ok()?
        };
        return (port != 0).then(|| format!("[{ip}]:{port}"));
    }
    let (host, port) = match input.split_once(':') {
        Some((host, port)) => (host, port.parse::<u16>().ok()?),
        None => (input, RELAY_PORT as u16),
    };
    let host = host.strip_suffix('.').unwrap_or(host).to_ascii_lowercase();
    if port == 0
        || host.is_empty()
        || !host.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        })
        || (host.bytes().all(|b| b.is_ascii_digit() || b == b'.')
            && host.parse::<IpAddr>().is_err())
    {
        return None;
    }
    let endpoint = format!("{host}:{port}");
    (endpoint.len() <= 255).then_some(endpoint)
}

fn normalized(raw: &[String]) -> Option<Vec<String>> {
    if raw.len() > MAX_RELAYS {
        return None;
    }
    let mut list = Vec::with_capacity(raw.len());
    for entry in raw {
        let endpoint = normalize(entry)?;
        if !list.contains(&endpoint) {
            list.push(endpoint);
        }
    }
    Some(list)
}

fn stored(list: &str, legacy: &str) -> Vec<String> {
    if list.is_empty() {
        return normalize(legacy).into_iter().collect();
    }
    serde_json::from_str::<Vec<String>>(list)
        .ok()
        .and_then(|raw| normalized(&raw))
        .unwrap_or_default()
}

pub(crate) fn configured() -> Vec<String> {
    stored(
        &Config::get_option(OPTION_RELAY_SERVERS),
        &Config::get_option(OPTION_RELAY_SERVER),
    )
}

pub(crate) fn allows(endpoint: &str) -> bool {
    normalize(endpoint).is_some_and(|value| configured().contains(&value))
}

pub(crate) fn intersection(local: &[String], peer: Option<&SessionRelayList>) -> Vec<String> {
    use sha2::{Digest, Sha256};
    let Some(peer) = peer else { return Vec::new() };
    if !peer.packed_hashes.is_empty() {
        let packed = peer.packed_hashes.as_ref();
        if !peer.servers.is_empty() || packed.len() > MAX_RELAYS * 16 || packed.len() % 16 != 0 {
            return Vec::new();
        }
        // Resolve compact UDP offers exclusively against locally configured addresses.
        return local
            .iter()
            .filter(|endpoint| {
                let hash = Sha256::digest(endpoint.as_bytes());
                packed.chunks_exact(16).any(|chunk| chunk == &hash[..16])
            })
            .cloned()
            .collect();
    }
    let Some(remote) = normalized(&peer.servers) else {
        return Vec::new();
    };
    local
        .iter()
        .filter(|node| remote.contains(node))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_or_invalid_policy_never_falls_back_to_a_previous_relay() {
        assert_eq!(stored("", "Old.EXAMPLE"), ["old.example:21117"]);
        for value in ["[]", "invalid", r#"["wss://user:pass@old.example/"]"#] {
            assert!(stored(value, "old.example").is_empty());
        }
    }

    #[test]
    fn only_matching_transports_and_ports_enter_the_intersection() {
        let local = stored(
            r#"["A.EXAMPLE","::1","wss://b.example/ws/relay","a.example:21117"]"#,
            "",
        );
        let peer = SessionRelayList {
            servers: vec![
                "a.example:21117".into(),
                "[::1]:21127".into(),
                "b.example".into(),
            ],
            ..Default::default()
        };
        assert_eq!(intersection(&local, Some(&peer)), ["a.example:21117"]);
        assert!(intersection(&local, None).is_empty());
    }

    #[test]
    fn compact_offers_only_resolve_known_local_nodes() {
        use sha2::{Digest, Sha256};
        let local = stored(r#"["A.example","B.example"]"#, "");
        let mut hashes = Vec::new();
        for name in ["b.example:21117", "unlisted.example:21117"] {
            hashes.extend_from_slice(&Sha256::digest(name.as_bytes())[..16]);
        }
        let mut offer = SessionRelayList {
            packed_hashes: hashes.into(),
            ..Default::default()
        };
        assert_eq!(intersection(&local, Some(&offer)), ["b.example:21117"]);
        offer.servers.push("a.example:21117".into());
        assert!(intersection(&local, Some(&offer)).is_empty());
    }
}
