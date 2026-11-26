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

const ID_SUFFIX: &str = "relay-id.invalid";

#[derive(serde::Deserialize)]
#[serde(untagged)]
enum StoredRelay {
    Address(String),
    WithKey(RelaySettings),
}

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct RelaySettings {
    address: String,
    #[serde(default)]
    key: String,
}

#[derive(Clone, PartialEq, Eq)]
pub(crate) struct Route {
    pub(crate) id: String,
    pub(crate) address: String,
    pub(crate) key: String,
}

fn reserved(address: &str) -> bool {
    let host = if address.contains("://") {
        url::Url::parse(address)
            .ok()
            .and_then(|url| url.host_str().map(str::to_owned))
    } else {
        address.rsplit_once(':').map(|(host, _)| host.to_owned())
    };
    host.is_some_and(|host| {
        let host = host.trim_end_matches('.');
        host == ID_SUFFIX
            || host
                .strip_suffix(ID_SUFFIX)
                .is_some_and(|s| s.ends_with('.'))
    })
}

fn scoped_id(address: &str, public_key: &[u8; 32]) -> String {
    use sha2::{Digest, Sha256};
    let mut hash = Sha256::new();
    hash.update(b"RustDesk relay identity v1\0");
    hash.update(address.as_bytes());
    hash.update([0]);
    hash.update(public_key);
    format!(
        "k1-{}.{ID_SUFFIX}:{RELAY_PORT}",
        hex::encode(&hash.finalize()[..24])
    )
}

struct ValidatedRelay {
    address: String,
    pin: Option<[u8; 32]>,
}

fn parse_settings(list: &str, legacy: &str) -> Option<Vec<ValidatedRelay>> {
    let entries: Vec<StoredRelay> = if list.is_empty() {
        if legacy.is_empty() {
            return Some(Vec::new());
        }
        vec![StoredRelay::Address(legacy.to_owned())]
    } else {
        serde_json::from_str(list).ok()?
    };
    if entries.len() > MAX_RELAYS {
        return None;
    }
    let mut settings: Vec<ValidatedRelay> = Vec::with_capacity(entries.len());
    for item in entries {
        let (address, key) = match item {
            StoredRelay::Address(address) => (address, String::new()),
            StoredRelay::WithKey(settings) => (settings.address, settings.key),
        };
        let address = normalize(&address)?;
        if reserved(&address) {
            return None;
        }
        let pin = if key.is_empty() {
            None
        } else {
            let bytes: [u8; 32] = crate::decode64(&key).ok()?.try_into().ok()?;
            if crate::encode64(bytes) != key {
                return None;
            }
            Some(bytes)
        };
        if let Some(previous) = settings.iter().find(|r| r.address == address) {
            if previous.pin != pin {
                return None;
            }
            continue;
        }
        settings.push(ValidatedRelay { address, pin });
    }
    Some(settings)
}

fn stored(list: &str, legacy: &str, id_key: &str) -> Vec<Route> {
    let mut routes = Vec::new();
    for entry in parse_settings(list, legacy).unwrap_or_default() {
        // Build 147 forwards membership identifiers as endpoints. A reserved DNS
        // name survives both that validation and its compact UDP representation.
        let (id, key) = match entry.pin {
            Some(pin) => {
                let key = crate::encode64(pin);
                let id = if key == id_key {
                    entry.address.clone()
                } else {
                    scoped_id(&entry.address, &pin)
                };
                (id, key)
            }
            None => (entry.address.clone(), id_key.to_owned()),
        };
        routes.push(Route {
            id,
            address: entry.address,
            key,
        });
    }
    routes
}

pub(crate) fn routes(id_key: &str) -> Vec<Route> {
    stored(
        &Config::get_option(OPTION_RELAY_SERVERS),
        &Config::get_option(OPTION_RELAY_SERVER),
        id_key,
    )
}

pub(crate) fn configured_for(id_key: &str) -> Vec<String> {
    routes(id_key).into_iter().map(|r| r.id).collect()
}

pub(crate) fn is_empty() -> bool {
    routes("").is_empty()
}

pub(crate) fn resolve(id: &str, id_key: &str) -> Option<Route> {
    let id = normalize(id)?;
    routes(id_key).into_iter().find(|r| r.id == id)
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

    fn ids(list: &str, legacy: &str) -> Vec<String> {
        stored(list, legacy, "").into_iter().map(|r| r.id).collect()
    }

    #[test]
    fn empty_or_invalid_policy_never_falls_back_to_a_previous_relay() {
        assert_eq!(ids("", "Old.EXAMPLE"), ["old.example:21117"]);
        for value in ["[]", "invalid", r#"["wss://user:pass@old.example/"]"#] {
            assert!(ids(value, "old.example").is_empty());
        }
    }

    #[test]
    fn only_matching_transports_and_ports_enter_the_intersection() {
        let local = ids(
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
        let local = ids(r#"["A.example","B.example"]"#, "");
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

    #[test]
    fn independent_keys_match_only_the_same_local_endpoint_and_pin() {
        use sha2::{Digest, Sha256};
        let pin = crate::encode64(std::array::from_fn::<_, 32, _>(|i| i as u8));
        let id_key = crate::encode64([42; 32]);
        let config = serde_json::json!([
            {"address": "RELAY.EXAMPLE", "key": pin},
            {"address": "shared.example", "key": id_key},
            "legacy.example"
        ]);
        let routes = stored(&config.to_string(), "", &id_key);
        let ids: Vec<_> = routes.iter().map(|r| r.id.clone()).collect();
        let expected = "k1-1eaab4e6f29d823f5ac07387f620bfe396f10b5e2b71fe81.relay-id.invalid:21117";
        assert_eq!(
            ids,
            [expected, "shared.example:21117", "legacy.example:21117"]
        );
        assert_eq!(routes[0].address, "relay.example:21117");
        assert_eq!(routes[0].key, pin);
        assert_eq!(routes[2].key, id_key);

        let offer_for = |key: &str| {
            let entry = serde_json::json!([{"address": "relay.example:21117", "key": key}]);
            SessionRelayList {
                servers: stored(&entry.to_string(), "", &id_key)
                    .into_iter()
                    .map(|r| r.id)
                    .collect(),
                ..Default::default()
            }
        };
        assert_eq!(intersection(&ids, Some(&offer_for(&pin))), [expected]);
        assert!(intersection(&ids, Some(&offer_for(&crate::encode64([15; 32])))).is_empty());
        assert!(intersection(&ids, Some(&offer_for(""))).is_empty());
        let compact = SessionRelayList {
            packed_hashes: Sha256::digest(expected.as_bytes())[..16].to_vec().into(),
            ..Default::default()
        };
        assert_eq!(intersection(&ids, Some(&compact)), [expected]);
    }

    #[test]
    fn invalid_pins_and_reserved_names_never_fall_back_to_another_credential() {
        for key in [
            String::from("invalid"),
            crate::encode64([0; 31]),
            crate::encode64([0; 64]),
        ] {
            let entries = serde_json::json!([{"address":"relay.example", "key": key}]);
            assert!(stored(&entries.to_string(), "fallback.example", "default").is_empty());
        }
        let conflict = serde_json::json!(["relay.example", {"address":"RELAY.example:21117","key":crate::encode64([0; 32])}]);
        assert!(stored(&conflict.to_string(), "", "default").is_empty());
        for name in [
            "relay-id.invalid",
            "custom.relay-id.invalid:99",
            "wss://X.relay-id.invalid./ws",
        ] {
            assert!(stored("", name, "default").is_empty());
        }
    }
}
