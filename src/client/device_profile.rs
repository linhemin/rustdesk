use base::config::keys;
use hbb_common::config::{PeerConfig, UserDefaultConfig};
use serde::Deserialize;

#[cfg(feature = "flutter")]
use super::ConnType;

#[derive(Deserialize)]
struct DeviceProfile {
    quality: Option<String>,
    privacy: Option<bool>,
    audio: Option<bool>,
    #[serde(default)]
    force_relay: bool,
}

impl DeviceProfile {
    fn for_peer(profiles: &str, peer_id: &str) -> Option<Self> {
        let mut profiles: serde_json::Value = serde_json::from_str(profiles).ok()?;
        serde_json::from_value(profiles.as_object_mut()?.remove(peer_id)?).ok()
    }

    fn apply(&self, config: &mut PeerConfig) {
        match self.quality.as_deref() {
            Some(quality @ ("best" | "balanced" | "low")) => {
                config.image_quality = quality.to_owned();
            }
            Some("default") => {
                config.image_quality = UserDefaultConfig::load().get(keys::OPTION_IMAGE_QUALITY);
            }
            _ => {}
        }
        if let Some(privacy) = self.privacy {
            config.privacy_mode.v = privacy;
        }
        if let Some(audio) = self.audio {
            config.disable_audio.v = !audio;
        }
    }
}

#[cfg(feature = "flutter")]
pub(super) fn configure(
    peer_id: &str,
    conn_type: ConnType,
    mut config: PeerConfig,
) -> (PeerConfig, bool) {
    let profiles = hbb_common::config::LocalConfig::get_flutter_option("local-device-profiles-v1");
    let Some(profile) = DeviceProfile::for_peer(&profiles, peer_id) else {
        return (config, false);
    };
    if conn_type == ConnType::DEFAULT_CONN {
        profile.apply(&mut config);
    }
    (config, profile.force_relay)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saved_profile_sets_the_native_connection_fields() {
        let profiles =
            r#"{"123":{"quality":"best","privacy":true,"audio":false,"force_relay":true}}"#;
        let profile = DeviceProfile::for_peer(profiles, "123").expect("saved profile");
        let mut config = PeerConfig::default();
        profile.apply(&mut config);
        assert_eq!(config.image_quality, "best");
        assert!(config.privacy_mode.v);
        assert!(config.disable_audio.v);
        assert!(profile.force_relay);
        assert!(DeviceProfile::for_peer(profiles, "456").is_none());
    }
}
