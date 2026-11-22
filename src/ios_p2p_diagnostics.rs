//! Address-free summaries of this app run's most recent in-session ICE attempts.
use std::{collections::VecDeque, fs, io::Write, path::Path};

const FILENAME: &str = "RustDesk-P2P-diagnostics.txt";
const HEADER: &str = "RustDesk P2P diagnostics\nformat=udp-paths-v3\n";
const MAX_FILE: usize = 48 * 1024;
const MAX_ATTEMPTS: usize = 16;
const MAX_SNAPSHOT: usize = 6 * 1024;

// The ICE library builds fixed labels and counts, without copying candidate strings. Also
// enforce its vocabulary here, at the file boundary; a future human-readable error, changed
// stats schema or raw signaling value must never silently become part of a shared report.
fn safe_snapshot(text: &str) -> bool {
    const WORDS: &str = "ice dtls sctp pc selected checklist candidates public4 other4 ipv6 unknown \
        local remote pairs states traffic nominated host srflx prflx relay udp tcp none unavailable \
        stats limit no ICE reports timeout waiting checking succeeded failed reqSent reqSendError \
        reqReceivedValid respSent respSendError respReceivedMatched connected new connecting closed \
        disconnected completed unspecified Unspecified Unknown established closing \
        udpCandidate readers reads readErrors nonStun stunDecodeError bindingRequest bindingSuccess \
        bindingError bindingIndication otherStun udpRequest roleConflict usernameMissing usernameInvalid \
        integrityMissing integrityInvalid candidateFailed accepted udpResponse unknownRemote \
        unknownTransaction wrongEndpoint noPair udpGather matchedResponse udpNat64 sourceDrop bindingRequestDrop \
        bindingRequestHeader knownSource unlistedSource udpMapping sockets stable portChanged \
        addressChanged insufficient alternateTested alternateChanged orderedMappings constantStep irregular \
        udpFullSeed nativeIpv4 nat64 bindFailed sent sendFailed invalidReply mappingRejected verified \
        udpPunchMagic requests";
    if text.is_empty()
        || text.len() > MAX_SNAPSHOT
        || !text
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b" \n=,[]()/->".contains(&c))
    {
        return false;
    }
    for line in text.lines() {
        let mut remaining = line;
        while let Some(start) = remaining.find(char::is_alphanumeric) {
            let rest = &remaining[start..];
            let end = rest
                .find(|c: char| !c.is_alphanumeric())
                .unwrap_or(rest.len());
            let word = &rest[..end];
            if word.bytes().all(|b| b.is_ascii_digit()) {
                // Numbers belong only to counters, never selected endpoints or remote IDs.
                let prefix = &line[..line.len() - rest.len()].trim_end();
                if !(prefix.ends_with('[')
                    || prefix.ends_with(',')
                    || prefix.ends_with("pairs=")
                    || prefix.ends_with("nominated="))
                {
                    return false;
                }
            } else if !WORDS
                .split_ascii_whitespace()
                .any(|allowed| allowed == word)
            {
                return false;
            }
            remaining = &rest[end..];
        }
    }
    true
}

#[derive(Default)]
struct History(VecDeque<(u64, String)>);

// READY carries only bounded anonymous counts for this attempt. Keep a missing peer READY
// distinguishable from a READY that actually reported zero measured sockets.
fn append_punch_status(out: &mut String, status: &crate::live_direct::PunchStatus) {
    if let Some((nats, limits, window_ms)) = status.plan {
        let labels = ["EIM", "linear", "random", "unknown"];
        let _ = writeln!(
            out,
            "fullPlan nat=[{},{}] limits={limits:?} windowMs={window_ms}",
            labels[usize::from(nats[0])],
            labels[usize::from(nats[1])],
        );
    }
    use std::fmt::Write;
    if let Some(full) = status.full {
        let _ = writeln!(out, "expandedPorts local {full}");
        if let Some(peer) = status.full_peer {
            let _ = writeln!(out, "expandedPorts peer {peer}");
        }
    }
    if let Some(group) = status.group_local {
        let _ = writeln!(out, "mappedPairs local {group}");
        if let Some(mask) = status.peer_group_aliases {
            let _ = writeln!(out, "peerObservedAliasMask={mask}");
        }
        if let Some(counts) = status.peer_profiles {
            let _ = writeln!(out, "peerOrderedMappings [stable,constantStep,irregular,insufficient]={counts:?}");
        }
        if let Some(peer) = status.group_peer {
            let _ = writeln!(out, "mappedPairs peer {peer}");
        } else {
            out.push_str("mappedPairs peer=unavailable\n");
        }
    }
    if let Some(local) = status.timed_local {
        let _ = writeln!(out, "timedFirst local {local}");
        if let Some(peer) = status.timed_peer {
            let _ = writeln!(out, "timedFirst peer {peer}");
        } else {
            out.push_str("timedFirst peer=unavailable\n");
        }
    } else {
        let state = if status.started { "started" } else { "waiting" };
        let _ = writeln!(out, "syncPunch={state} localWakes={}", status.local_wakes);
        match status.remote_wakes {
            Some(wakes) => {
                let _ = writeln!(out, "remoteWakes={wakes}");
            }
            None => out.push_str("remoteWakes=unavailable\n"),
        }
    }
    if let Some(sample) = status.remote_io {
        let _ = writeln!(out, "syncUdp peer elapsedMs={} [reads,bindingRequestHeader,reqAccepted,respSent,respSendError,respReceivedMatched]={:?}", sample.elapsed_ms, sample.counts);
    } else {
        out.push_str("syncUdp peer=unavailable\n");
    }
    if status.timed_local.is_some() { return; }
    for (side, mapping) in [
        ("local", status.local_mapping),
        ("peer", status.remote_mapping),
    ] {
        match mapping {
            Some(counts) => {
                let _ = writeln!(out, "syncMapping {side} [stable,portChanged,addressChanged,insufficient,alternateTested,alternateChanged]={counts:?}");
            }
            None => {
                let _ = writeln!(out, "syncMapping {side}=unavailable");
            }
        }
    }
}

impl History {
    fn update(&mut self, attempt: u64, entry: String) -> String {
        self.0.retain(|(id, _)| *id != attempt);
        self.0.push_back((attempt, entry));
        let mut size = HEADER.len() + self.0.iter().map(|(_, text)| text.len()).sum::<usize>();
        while self.0.len() > MAX_ATTEMPTS || size > MAX_FILE {
            size -= self.0.pop_front().unwrap().1.len();
        }
        let mut file = String::with_capacity(size);
        file.push_str(HEADER);
        for (_, entry) in &self.0 {
            file.push_str(entry);
        }
        file
    }
}

fn save(path: &Path, contents: &str, seq: u64) -> std::io::Result<()> {
    // Files can read this document during a write. Rename only after the full new report
    // exists. Never follow an existing temporary file in this user-visible directory.
    let tmp = path.with_file_name(format!(".rd-p2p-{}-{}.tmp", std::process::id(), seq));
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)?;
    let written = file.write_all(contents.as_bytes());
    drop(file);
    let result = written.and_then(|()| fs::rename(&tmp, path));
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

#[cfg(target_os = "ios")]
pub(crate) use recorder::{disable, record_fallback, record_milestone, Observation};

#[cfg(target_os = "ios")]
mod recorder {
    use super::*;
    use base::config::keys::OPTION_RECORD_P2P_DIAGNOSTICS;
    use hbb_common::{
        anyhow, config::Config, futures_util::FutureExt, log, tokio,
        tokio::sync::watch, webrtc::WebRTCStream,
    };
    use std::{
        sync::{
            atomic::{AtomicU32, AtomicU64, AtomicU8, Ordering},
            mpsc::{sync_channel, SyncSender},
            Arc, Mutex,
        },
        time::{Duration, Instant},
    };

    static DEFAULT_PATH: AtomicU8 = AtomicU8::new(0);
    static BUILD: AtomicU32 = AtomicU32::new(0);

    // Written by NWPathMonitor. Do not infer the interface of an individual ICE socket.
    #[no_mangle]
    pub extern "C" fn rustdesk_ios_diagnostic_path(kind: u8, build: u32) {
        DEFAULT_PATH.store(kind, Ordering::Relaxed);
        BUILD.store(build, Ordering::Relaxed);
    }

    fn path_label() -> &'static str {
        match DEFAULT_PATH.load(Ordering::Relaxed) {
            1 => "wifi",
            2 => "cellular",
            3 => "other",
            _ => "unknown",
        }
    }

    struct Writer {
        generation: u64,
        entries: SyncSender<(u64, String)>,
        stop: watch::Sender<()>,
    }

    static WRITER: Mutex<Option<Writer>> = Mutex::new(None);

    pub(crate) fn disable() {
        let mut writer = WRITER.lock().unwrap();
        *writer = None;
        let path = Config::path(FILENAME);
        if path.is_absolute() {
            if let Err(err) = fs::remove_file(path) {
                if err.kind() != std::io::ErrorKind::NotFound {
                    log::warn!("Could not remove P2P diagnostics: {err}");
                }
            }
        }
    }

    fn recording() -> Option<(SyncSender<(u64, String)>, watch::Receiver<()>)> {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let mut writer = WRITER.lock().unwrap();
        if crate::get_local_option(OPTION_RECORD_P2P_DIAGNOSTICS) != "Y" {
            return None;
        }
        if let Some(writer) = writer.as_ref() {
            return Some((writer.entries.clone(), writer.stop.subscribe()));
        }
        let generation = NEXT.fetch_add(1, Ordering::Relaxed);
        let (entries, rx) = sync_channel(16);
        let (stop, stop_rx) = watch::channel(());
        let started = std::thread::Builder::new()
            .name("p2p-diagnostics".into())
            .spawn(move || {
                let mut history = History::default();
                for (seq, (id, entry)) in rx.into_iter().enumerate() {
                    // Serialize saving with disable so a queued report cannot reappear after
                    // removal, including when the user quickly enables recording again.
                    let writer = WRITER.lock().unwrap();
                    if !writer.as_ref().is_some_and(|w| w.generation == generation) {
                        return;
                    }
                    let path = Config::path(FILENAME);
                    if path.is_absolute() {
                        if let Err(err) = save(&path, &history.update(id, entry), seq as u64) {
                            hbb_common::throttled_log!(
                                Duration::from_secs(30), warn, "Could not save P2P diagnostics: {err}"
                            );
                        }
                    }
                }
            });
        if let Err(err) = started {
            log::warn!("Could not start P2P diagnostics: {err}");
            return None;
        }
        *writer = Some(Writer { generation, entries: entries.clone(), stop });
        Some((entries, stop_rx))
    }

    #[derive(Clone)]
    struct Attempt {
        id: u64,
        entries: SyncSender<(u64, String)>,
        started: Instant,
        start_path: &'static str,
        offerer: bool,
        phase: &'static str,
    }

    struct Progress {
        latest: Option<(Instant, String)>,
        punch: Option<tokio::sync::watch::Receiver<crate::live_direct::PunchStatus>>,
        stage: &'static str,
        ended: bool,
    }

    impl Progress {
        fn update(&mut self, text: String) {
            if !safe_snapshot(&text) {
                return;
            }
            // Closing a PC can discard the agent before the final snapshot. Keep the last
            // measured socket counters, with their actual age, instead of replacing them.
            let measured = |s: &str| s.lines().any(|line| line.starts_with("udpCandidate ["));
            if !measured(&text) && self.latest.as_ref().map_or(false, |(_, s)| measured(s)) {
                return;
            }
            self.latest = Some((Instant::now(), text));
        }
    }

    impl Attempt {
        fn publish(&self, progress: &Progress, result: &str) {
            let side = if self.offerer {
                "controller"
            } else {
                "controlled"
            };
            let written = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
            let mut entry = format!(
                "\n{written} version={} build={} role={side} phase={} default_path_start={} default_path_end={} duration_ms={} result={result} stage={}\n",
                env!("CARGO_PKG_VERSION"), BUILD.load(Ordering::Relaxed), self.phase, self.start_path,
                path_label(), self.started.elapsed().as_millis(), progress.stage,
            );
            match &progress.latest {
                Some((at, text)) => {
                    entry.push_str(&format!("sample_age_ms={}\n", at.elapsed().as_millis()));
                    entry.push_str(text.trim_end());
                    entry.push('\n');
                }
                None => entry.push_str("sample=unavailable\n"),
            }
            if let Some(punch) = &progress.punch {
                append_punch_status(&mut entry, &punch.borrow());
            }
            let _ = self.entries.try_send((self.id, entry));
        }
    }

    pub(crate) struct Observation {
        attempt: Attempt,
        result: &'static str,
        progress: Arc<Mutex<Progress>>,
        sampler: Option<tokio::task::JoinHandle<()>>,
        stop: watch::Receiver<()>,
    }

    impl Observation {
        pub(crate) fn new(offerer: bool, phase: &'static str) -> Option<Self> {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let (entries, stop) = recording()?;
            let attempt = Attempt {
                id: NEXT.fetch_add(1, Ordering::Relaxed),
                entries,
                started: Instant::now(),
                start_path: path_label(),
                offerer,
                phase,
            };
            let progress = Progress {
                latest: None,
                punch: None,
                stage: "starting",
                ended: false,
            };
            attempt.publish(&progress, "in-progress");
            Some(Self {
                attempt,
                result: "cancelled",
                progress: Arc::new(Mutex::new(progress)),
                sampler: None,
                stop,
            })
        }

        pub(crate) fn observe(&mut self, pc: &WebRTCStream) {
            self.set_stage("negotiating");
            let pc = pc.clone();
            let progress = self.progress.clone();
            let attempt = self.attempt.clone();
            let mut stop = self.stop.clone();
            self.sampler = Some(tokio::spawn(async move {
                let mut ticker = tokio::time::interval(Duration::from_secs(2));
                ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                loop {
                    let text = tokio::select! {
                        biased;
                        _ = stop.changed() => break,
                        text = async {
                            ticker.tick().await;
                            pc.ice_path_diagnostics().await
                        } => text,
                    };
                    if let Ok(mut state) = progress.lock() {
                        if state.ended {
                            return;
                        }
                        state.update(text);
                        attempt.publish(&state, "in-progress");
                    }
                }
                if let Ok(mut state) = progress.lock() {
                    state.latest = None;
                    state.punch = None;
                }
            }));
        }

        pub(crate) fn set_stage(&mut self, stage: &'static str) {
            if let Ok(mut state) = self.progress.lock() {
                state.stage = stage;
            }
        }

        pub(crate) fn finish_udp_probe(&mut self, err: &anyhow::Error) {
            self.finish("peer probe not acknowledged", Some(err));
            if let Some(counts) = err.downcast_ref::<crate::common::UdpPunchTimeout>() {
                self.result = "timeout";
                if let Ok(mut state) = self.progress.lock() {
                    state.latest = Some((Instant::now(), format!(
                        "nativeUdp [sent,sendErrors,peerProbes,receiveErrors]=[{},{},{},{}]",
                        counts.sent, counts.send_errors, counts.received, counts.recv_errors
                    )));
                }
            }
        }

        pub(crate) fn finish_candidates(&mut self, err: &anyhow::Error) {
            self.finish("no verified UDP pair", Some(err));
            if let Some(c) = err.downcast_ref::<crate::p2p::udp_paths::Counts>() {
                self.result = "timeout";
                if let Ok(mut state) = self.progress.lock() {
                    state.latest = Some((Instant::now(), format!(
                        "nativeUdp [localSockets,nasPorts,sent,sendErrors,authenticatedPairs]=[{},{},{},{},{}]",
                        c.sockets, c.ports, c.sent, c.errors, c.authenticated
                    )));
                }
            }
        }

        pub(crate) fn set_punch_status(
            &mut self,
            status: tokio::sync::watch::Receiver<crate::live_direct::PunchStatus>,
        ) {
            if let Ok(mut state) = self.progress.lock() {
                state.punch = Some(status);
            }
        }

        // On the terminal transition try the same snapshot once without waiting. If it
        // needs to await a lock, keep the last live snapshot with its visible age. An aborted
        // attempt uses that same snapshot and releases the sampler when this guard drops.
        pub(crate) fn sample_now(&mut self, pc: &WebRTCStream) {
            if let Some(sampler) = self.sampler.take() {
                sampler.abort();
            }
            if self.stop.has_changed().is_err() {
                return;
            }
            if let Some(text) = pc.ice_path_diagnostics().now_or_never() {
                if let Ok(mut state) = self.progress.lock() {
                    state.update(text);
                }
            }
        }

        pub(crate) fn finish(&mut self, stage: &'static str, err: Option<&anyhow::Error>) {
            self.set_stage(stage);
            self.result = match err {
                None => "direct-ready",
                Some(e)
                    if e.is::<tokio::time::error::Elapsed>()
                        || e.to_string() == "WebRTC wait_connected timeout" =>
                {
                    "timeout"
                }
                Some(_) => "failed",
            };
        }

        pub(crate) fn finish_initial(&mut self, direct_webrtc: bool, failed: bool) {
            self.result = if direct_webrtc {
                "direct-ready"
            } else if failed {
                "failed"
            } else {
                "other-transport"
            };
        }
    }

    pub(crate) fn record_fallback(reason: &'static str) {
        if let Some(mut observation) = Observation::new(true, "relay-fallback") {
            observation.set_stage(reason);
            observation.result = "fallback";
        }
    }

    pub(crate) fn record_milestone(phase: &'static str, stage: &'static str) {
        if let Some(mut observation) = Observation::new(true, phase) {
            observation.set_stage(stage);
            observation.result = "observed";
        }
    }

    impl Drop for Observation {
        fn drop(&mut self) {
            if let Some(sampler) = self.sampler.take() {
                sampler.abort();
            }
            if let Ok(mut state) = self.progress.lock() {
                state.ended = true;
                self.attempt.publish(&state, self.result);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relay_ready_summaries_keep_missing_and_observed_results_distinct() {
        let mut status = crate::live_direct::PunchStatus::default();
        status.local_mapping = Some([1, 0, 0, 2, 0, 0]);
        let mut text = String::new();
        append_punch_status(&mut text, &status);
        assert!(
            text.contains("syncPunch=waiting") && text.contains("syncMapping peer=unavailable")
        );
        assert!(text.contains("syncUdp peer=unavailable"));
        status.started = true;
        status.remote_mapping = Some([0, 1, 0, 0, 1, 1]);
        status.local_wakes = 2;
        status.remote_wakes = Some(1);
        status.remote_io = Some(crate::live_direct::PunchIo {
            elapsed_ms: 4210,
            counts: [15, 8, 7, 6, 1, 3],
        });
        text.clear();
        append_punch_status(&mut text, &status);
        assert!(text.contains("syncPunch=started localWakes=2\nremoteWakes=1"));
        assert!(text.contains("syncUdp peer elapsedMs=4210 [reads,bindingRequestHeader,reqAccepted,respSent,respSendError,respReceivedMatched]=[15, 8, 7, 6, 1, 3]"));
        assert!(text
            .lines()
            .any(|s| s.starts_with("syncMapping peer [") && s.ends_with("=[0, 1, 0, 0, 1, 1]")));
        assert!(safe_snapshot("udpMapping [sockets,stable,portChanged,addressChanged,insufficient,alternateTested,alternateChanged]=[4,1,1,0,2,1,1]\n"));
    }

    #[test]
    fn rejects_identifiers_and_accepts_count_only_snapshots() {
        let valid = "ice=checking dtls=new sctp=connecting pc=connecting\nselected=none\npublic4 local=[0, 1, 0, 0, 0] remote=[0, 1, 0, 0, 0]\nlocal=public4->remote=public4 pairs=12 traffic=[753, 0, 0, 0, 0, 0]\n";
        assert!(safe_snapshot(valid));
        assert!(safe_snapshot("orderedMappings [stable,constantStep,irregular,insufficient]=[0,2,1,4]\n"));
        assert!(safe_snapshot("udpFullSeed [nativeIpv4,nat64,bindFailed,sent,sendFailed,timeout,invalidReply,mappingRejected,verified]=[1,1,0,3,0,1,0,0,1]\n"));
        assert!(safe_snapshot(
            "udpCandidate [readers,reads,bindingRequest,bindingRequestHeader]=[2,4,3,4]\nudpRequest [usernameInvalid,knownSource,unlistedSource]=[1,2,1]\n"
        ));
        for unsafe_input in [
            "ice=10.0.0.1:53047",
            "selected=2001:db8::1",
            "password=ASecret",
            "remote=my-device-ID",
            "remote=534217888",
            "selected=58119",
            "a=ice-ufrag",
            "abc\0",
            "",
            &"x".repeat(5000),
        ] {
            assert!(!safe_snapshot(unsafe_input));
        }
    }

    #[test]
    fn live_samples_replace_the_same_attempt_without_repeating_its_counts() {
        let mut history = History::default();
        history.update(1, "first running\n".into());
        history.update(2, "second running\n".into());
        let report = history.update(1, "first completed\n".into());
        assert_eq!(report, format!("{HEADER}second running\nfirst completed\n"));
    }

    #[test]
    fn keeps_complete_bounded_records_and_replaces_the_shared_file() {
        let mut history = History::default();
        let mut report = String::new();
        for i in 0..30 {
            report = history.update(i, format!("attempt-{i} {}\n", "x".repeat(4000)));
        }
        assert!(report.starts_with(HEADER));
        assert!(report.len() <= MAX_FILE && history.0.len() <= MAX_ATTEMPTS);
        assert!(!report.contains("attempt-0 "));
        assert!(report.contains("attempt-29 "));
        let dir = std::env::temp_dir().join(format!("rd-p2p-storage-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join(FILENAME);
        fs::write(&file, "untrusted previous text").unwrap();
        save(&file, &report, 1).unwrap();
        assert_eq!(fs::read_to_string(&file).unwrap(), report);
        fs::remove_file(file).unwrap();
        fs::remove_dir(dir).unwrap();
    }
}
