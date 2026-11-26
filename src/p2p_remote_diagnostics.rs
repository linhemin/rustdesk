use base::message_proto::p2p_diagnostic_command::Action;

const MAX_SAMPLE: usize = 12 * 1024;

fn valid_profile(action: Action, profile: u32) -> bool {
    match action {
        Action::APPLY_AND_RECONNECT => (1..=7).contains(&profile),
        Action::STATUS | Action::RECONNECT | Action::RESTORE_AND_RECONNECT => profile == 0,
        _ => false,
    }
}

#[cfg(windows)]
pub(crate) mod windows {
    use super::{valid_profile, Action, MAX_SAMPLE};
    use base::message_proto::{Message, Misc, P2pDiagnosticCommand, P2pDiagnosticReport};
    use std::sync::atomic::{AtomicU64, Ordering};

    pub const PREFIX: &str = "/p2p-test";
    pub const USAGE: &str =
        "Use /p2p-test status, reconnect, default, or a combination of tcp udp webrtc.";

    pub fn command(text: &str) -> Option<Message> {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let mut words = text.split_ascii_whitespace();
        if words.next()? != PREFIX {
            return None;
        }
        let first = words.next()?;
        let (action, profile) = match first {
            "status" if words.next().is_none() => (Action::STATUS, 0),
            "reconnect" if words.next().is_none() => (Action::RECONNECT, 0),
            "default" if words.next().is_none() => (Action::RESTORE_AND_RECONNECT, 0),
            _ => {
                let mut profile = 0;
                for name in std::iter::once(first).chain(words) {
                    let bit = match name {
                        "tcp" => 1,
                        "udp" => 2,
                        "webrtc" => 4,
                        _ => return None,
                    };
                    if profile & bit != 0 {
                        return None;
                    }
                    profile |= bit;
                }
                (Action::APPLY_AND_RECONNECT, profile)
            }
        };
        if !valid_profile(action, profile) {
            return None;
        }
        let mut misc = Misc::new();
        misc.set_p2p_diagnostic_command(P2pDiagnosticCommand {
            request_id: NEXT.fetch_add(1, Ordering::Relaxed),
            action: action.into(),
            profile,
            ..Default::default()
        });
        let mut msg = Message::new();
        msg.set_misc(misc);
        Some(msg)
    }

    pub fn report(report: P2pDiagnosticReport) -> Option<String> {
        if report.sample.len() > MAX_SAMPLE
            || !report
                .sample
                .bytes()
                .all(|byte| byte == b'\n' || (b' '..=b'~').contains(&byte))
        {
            return None;
        }
        Some(format!(
            "request={} {}",
            report.request_id,
            report.sample.replace('\n', "\\n")
        ))
    }
}

#[cfg(any(target_os = "ios", test))]
pub(crate) mod ios {
    use super::{valid_profile, Action, MAX_SAMPLE};
    use base::{
        config::keys,
        message_proto::{P2pDiagnosticCommand, P2pDiagnosticReport},
    };
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex, Weak},
        time::{Duration, Instant},
    };

    pub const OPTION: &str = "p2p-remote-diagnostics-access";
    const LEASE: Duration = Duration::from_secs(15 * 60);
    const COOLDOWN: Duration = Duration::from_secs(3);
    const REPORT_INTERVAL: Duration = Duration::from_secs(4);

    #[derive(Clone, Default)]
    pub struct Access(Arc<()>);

    struct Grant {
        started: Instant,
        key: Vec<u8>,
        profile: Option<u32>,
        last_command: Option<Instant>,
        entries: VecDeque<(u64, String)>,
    }

    struct State {
        owner: Weak<()>,
        verified: Option<Vec<u8>>,
        grant: Option<Grant>,
    }

    static STATE: Mutex<Option<State>> = Mutex::new(None);

    impl State {
        fn grant(&mut self) -> Option<&mut Grant> {
            if self.owner.strong_count() == 0
                || self
                    .grant
                    .as_ref()
                    .is_some_and(|g| g.started.elapsed() >= LEASE)
            {
                self.grant = None;
            }
            self.grant.as_mut()
        }
    }

    impl Access {
        pub fn begin_round(&self) {
            let mut state = STATE.lock().unwrap();
            if let Some(state) = state.as_mut().filter(|state| self.owns(state)) {
                state.verified = None;
                return;
            }
            *state = Some(State {
                owner: Arc::downgrade(&self.0),
                verified: None,
                grant: None,
            });
        }

        fn owns(&self, state: &State) -> bool {
            state.owner.ptr_eq(&Arc::downgrade(&self.0))
        }

        pub fn authenticated(&self, key: Option<&[u8]>) {
            let mut state = STATE.lock().unwrap();
            let Some(state) = state.as_mut().filter(|state| self.owns(state)) else {
                return;
            };
            if state
                .grant
                .as_ref()
                .is_some_and(|grant| Some(grant.key.as_slice()) != key)
            {
                state.grant = None;
            }
            // The grant retains its own authenticated key across a diagnostic reconnect.
            state.verified = key.map(<[u8]>::to_vec);
        }

        pub fn allow(&self, allow: bool) {
            let mut state = STATE.lock().unwrap();
            let Some(state) = state.as_mut().filter(|state| self.owns(state)) else {
                return;
            };
            if !allow {
                state.grant = None;
            } else if let Some(key) = state.verified.clone().filter(|_| recording_enabled()) {
                state.grant = Some(Grant {
                    started: Instant::now(),
                    key,
                    profile: None,
                    last_command: None,
                    entries: VecDeque::new(),
                });
            }
        }

        pub fn allowed(&self) -> bool {
            let mut state = STATE.lock().unwrap();
            state
                .as_mut()
                .filter(|state| self.owns(state))
                .and_then(State::grant)
                .is_some()
                && recording_enabled()
        }

        pub fn close(&self) {
            let mut state = STATE.lock().unwrap();
            if state.as_ref().is_some_and(|state| self.owns(state)) {
                *state = None;
            }
        }
    }

    fn recording_enabled() -> bool {
        hbb_common::config::LocalConfig::get_option(keys::OPTION_RECORD_P2P_DIAGNOSTICS) == "Y"
    }

    pub fn revoke() {
        if let Some(state) = STATE.lock().unwrap().as_mut() {
            state.grant = None;
        }
    }

    pub fn option(key: &str) -> Option<String> {
        let bit = match key {
            keys::OPTION_ENABLE_TCP_PUNCH => 1,
            keys::OPTION_ENABLE_UDP_PUNCH => 2,
            keys::OPTION_ENABLE_WEBRTC => 4,
            _ => return None,
        };
        if !recording_enabled() {
            return None;
        }
        let profile = STATE.lock().unwrap().as_mut()?.grant()?.profile?;
        Some(if profile & bit != 0 { "Y" } else { "N" }.to_owned())
    }

    pub fn capture() -> Option<Instant> {
        STATE
            .lock()
            .unwrap()
            .as_mut()?
            .grant()
            .map(|grant| grant.started)
    }

    pub fn record(capture: Option<Instant>, id: u64, entry: &str) {
        let Some(capture) = capture else {
            return;
        };
        let mut state = STATE.lock().unwrap();
        let Some(grant) = state
            .as_mut()
            .and_then(State::grant)
            .filter(|g| g.started == capture)
        else {
            return;
        };
        grant.entries.retain(|(stored_id, _)| *stored_id != id);
        if entry.len() <= MAX_SAMPLE - 512 {
            grant.entries.push_back((id, entry.to_owned()));
        }
        while grant.entries.len() > 6
            || grant
                .entries
                .iter()
                .map(|(_, text)| text.len())
                .sum::<usize>()
                > MAX_SAMPLE - 512
        {
            grant.entries.pop_front();
        }
    }

    pub struct Round {
        pub key: Option<Vec<u8>>,
        started: Instant,
        initial: Option<Duration>,
        first_direct: Option<Duration>,
        path: &'static str,
        direct: bool,
        last_report: Option<Instant>,
    }

    impl Default for Round {
        fn default() -> Self {
            Self {
                key: None,
                started: Instant::now(),
                initial: None,
                first_direct: None,
                path: "unknown",
                direct: false,
                last_report: None,
            }
        }
    }

    impl Round {
        pub fn set_path(&mut self, transport: &'static str, direct: bool) {
            let elapsed = self.started.elapsed();
            self.initial.get_or_insert(elapsed);
            if direct {
                self.first_direct.get_or_insert(elapsed);
            }
            self.path = transport;
            self.direct = direct;
        }

        pub fn sample(
            &mut self,
            access: &Access,
            command: Option<P2pDiagnosticCommand>,
        ) -> Option<(P2pDiagnosticReport, bool)> {
            if !recording_enabled() || self.key.is_none() {
                return None;
            }
            let configured = (
                crate::get_tcp_punch_enabled(),
                crate::get_udp_punch_enabled(),
                crate::get_webrtc_enabled(),
                crate::get_ipv6_punch_enabled(),
            );
            let mut state = STATE.lock().unwrap();
            let state = state
                .as_mut()
                .filter(|state| access.owns(state) && state.verified == self.key)?;
            let grant = state.grant()?;
            let (request_id, result, reconnect) = if let Some(command) = command {
                let action = command.action.enum_value().ok()?;
                if command.request_id == 0 || !valid_profile(action, command.profile) {
                    return None;
                }
                if action == Action::STATUS {
                    if self
                        .last_report
                        .is_some_and(|at| at.elapsed() < Duration::from_secs(1))
                    {
                        return None;
                    }
                    self.last_report = Some(Instant::now());
                    (command.request_id, "status", false)
                } else if grant.last_command.is_some_and(|at| at.elapsed() < COOLDOWN) {
                    (command.request_id, "cooldown", false)
                } else {
                    grant.last_command = Some(Instant::now());
                    match action {
                        Action::APPLY_AND_RECONNECT => grant.profile = Some(command.profile),
                        Action::RESTORE_AND_RECONNECT => grant.profile = None,
                        _ => {}
                    }
                    (command.request_id, "reconnecting", true)
                }
            } else {
                if self
                    .last_report
                    .is_some_and(|at| at.elapsed() < REPORT_INTERVAL)
                {
                    return None;
                }
                self.last_report = Some(Instant::now());
                (0, "sample", false)
            };
            let timing = |d: Option<Duration>| {
                d.map_or_else(|| "pending".to_owned(), |d| d.as_millis().to_string())
            };
            let profile = grant
                .profile
                .map_or_else(|| "default".to_owned(), |bits| bits.to_string());
            let mut sample = format!("result={result} profile={profile} tcp={} udp={} webrtc={} ipv6={} transport={} direct={} initial_ms={} first_direct_ms={} elapsed_ms={}",
                configured.0, configured.1, configured.2, configured.3, self.path, self.direct,
                timing(self.initial), timing(self.first_direct), self.started.elapsed().as_millis());
            if matches!(result, "status" | "sample") {
                for (_, entry) in &grant.entries {
                    sample.push_str(entry);
                }
            }
            Some((
                P2pDiagnosticReport {
                    request_id,
                    sample,
                    ..Default::default()
                },
                reconnect,
            ))
        }
    }

    #[cfg(test)]
    #[test]
    fn reconnect_keeps_the_grant_only_for_the_same_authenticated_peer() {
        let access = Access::default();
        access.begin_round();
        access.authenticated(Some(&[1]));
        let grant = Grant {
            started: Instant::now(),
            key: vec![1],
            profile: Some(2),
            last_command: None,
            entries: VecDeque::new(),
        };
        STATE.lock().unwrap().as_mut().unwrap().grant = Some(grant);
        access.begin_round();
        access.authenticated(Some(&[1]));
        assert!(capture().is_some());
        access.begin_round();
        access.authenticated(Some(&[2]));
        assert!(capture().is_none());
        access.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_named_punch_combinations_and_well_formed_actions_are_accepted() {
        assert!(valid_profile(Action::APPLY_AND_RECONNECT, 7));
        assert!(!valid_profile(Action::APPLY_AND_RECONNECT, 0));
        assert!(!valid_profile(Action::APPLY_AND_RECONNECT, 8));
        assert!(!valid_profile(Action::UNKNOWN, 0));
        assert!(!valid_profile(Action::STATUS, 1));
    }

    #[cfg(windows)]
    #[test]
    fn command_parser_accepts_punch_profiles_and_rejects_generic_options() {
        let msg = windows::command("/p2p-test tcp webrtc").unwrap();
        assert_eq!(msg.misc().p2p_diagnostic_command().profile, 5);
        assert!(windows::command("/p2p-test tcp tcp").is_none());
        assert!(windows::command("/p2p-test default webrtc").is_none());
        assert!(windows::command("/p2p-test id-server example.com").is_none());
    }
}
