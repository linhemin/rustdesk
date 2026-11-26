use super::{decode, frame, native, quality, Direct, Lane, Relay, PATH_TIMEOUT};
use hbb_common::{
    bail,
    futures_util::{future::BoxFuture, stream::FuturesUnordered, FutureExt, StreamExt},
    tokio::time::{timeout, Duration, Instant},
    ResultType,
};
use std::collections::VecDeque;

pub(crate) const CAPABILITY: &str = "rustdesk_live_parallel_v1";
pub(crate) const START: &[u8] = b"\x00RD-live-parallel-v1-start";
pub(crate) const ACCEPT: &[u8] = b"\x00RD-live-parallel-v1-accept";
pub(super) const SELECT: u8 = 32;
pub(super) const SELECTED: u8 = 33;
const PROBE: u8 = 34;
const REPLY: u8 = 35;
const TCP: u64 = 1 << 63;
const UDP: u64 = 1 << 62;
const NATIVE: u64 = TCP | UDP;
const BASELINE_WAIT: Duration = Duration::from_secs(10);
const RECHECK: Duration = Duration::from_secs(15);

pub(crate) type Dials = [Option<native::Dial>; 2];
type Check = BoxFuture<'static, (u64, ResultType<Ready>)>;

struct Ready {
    id: u64,
    lane: Lane,
    samples: quality::Samples,
    checked: Instant,
    confirmed: bool,
}

#[derive(Default)]
pub(super) struct Race {
    caller: Option<([u8; 32], Dials)>,
    checks: FuturesUnordered<Check>,
    pending: Vec<u64>,
    ready: VecDeque<Ready>,
    selected: Option<(u64, Instant)>,
    native_attempt: u64,
    native_retry: [NativeRetry; 2],
    rtc_after: Option<Instant>,
    pub(super) quality: Option<quality::Monitor>,
}

#[derive(Default)]
struct NativeRetry {
    after: Option<Instant>,
    failures: u32,
}

impl NativeRetry {
    fn defer(&mut self, until: Instant) {
        self.after = Some(self.after.map_or(until, |at| at.max(until)));
    }

    fn failed(&mut self, now: Instant) {
        let delay = (2u64 << self.failures.min(3)).min(12);
        self.failures = self.failures.saturating_add(1);
        self.defer(now + Duration::from_secs(delay));
    }
}

impl Race {
    pub(super) fn caller(ticket: [u8; 32], dials: Dials) -> Self {
        Self {
            caller: Some((ticket, dials)),
            ..Self::default()
        }
    }

    pub(super) fn measured(mut self, enabled: bool) -> Self {
        self.quality = enabled.then(quality::Monitor::default);
        self
    }

    pub(super) fn is_caller(&self) -> bool {
        self.caller.is_some()
    }

    fn busy(&self, family: u64) -> bool {
        self.pending.iter().any(|id| id & NATIVE == family)
            || self.ready.iter().any(|ready| ready.id & NATIVE == family)
    }

    pub(super) fn rtc_busy(&self) -> bool {
        self.busy(0)
            || self.selected.is_some()
            || self.rtc_after.is_some_and(|at| Instant::now() < at)
    }

    pub(super) fn defer_native(&mut self, until: Instant) {
        for retry in &mut self.native_retry {
            retry.defer(until);
        }
    }

    pub(super) fn start_native(&mut self, now: Instant) {
        if self.selected.is_some() {
            return;
        }
        let Some((ticket, dials)) = self.caller.as_ref() else {
            return;
        };
        for (index, (family, dial)) in [TCP, UDP].into_iter().zip(dials).enumerate() {
            let Some(dial) = dial else { continue };
            if self.busy(family) || self.native_retry[index].after.is_some_and(|at| now < at) {
                continue;
            }
            self.native_attempt += 1;
            let dial = dial();
            let ticket = *ticket;
            let id = self.native_attempt | family;
            let measured = self.quality.is_some();
            self.pending.push(id);
            let attempt = async move {
                let budget = if family == UDP { 75 } else { 45 };
                let lane = timeout(Duration::from_secs(budget), async {
                    native::attach(ticket, id, dial.await?).await
                })
                .await??;
                verify(Lane::Native(lane), id, true, measured).await
            };
            self.checks.push(async move { (id, attempt.await) }.boxed());
        }
    }

    pub(super) fn verify(&mut self, id: u64, lane: Lane, caller: bool) {
        if self
            .pending
            .iter()
            .any(|pending| pending & NATIVE == id & NATIVE)
        {
            return;
        }
        self.pending.push(id);
        let measured = self.quality.is_some();
        self.checks
            .push(async move { (id, verify(lane, id, caller, measured).await) }.boxed());
    }

    pub(super) fn is_checking(&self) -> bool {
        !self.checks.is_empty()
    }

    pub(super) async fn checked(&mut self) {
        let Some((id, result)) = self.checks.next().await else {
            return;
        };
        self.pending.retain(|pending| *pending != id);
        if self.is_caller() && id & NATIVE != 0 {
            let retry = &mut self.native_retry[usize::from(id & NATIVE == UDP)];
            if result.is_err() {
                retry.failed(Instant::now());
                #[cfg(target_os = "ios")]
                crate::ios_p2p_diagnostics::record_milestone(
                    "relay-upgrade-parallel",
                    if id & NATIVE == UDP {
                        "UDP attempt ended, waiting for UDP retry"
                    } else {
                        "TCP attempt ended, waiting for TCP retry"
                    },
                );
            } else {
                *retry = NativeRetry::default();
            }
        }
        match result {
            Ok(ready) => {
                if ready.confirmed {
                    if self.is_caller()
                        && !self.selected.is_some_and(|(selected, _)| selected == id)
                    {
                        return;
                    }
                    self.request(id);
                }
                #[cfg(target_os = "ios")]
                if !ready.confirmed || !self.is_caller() {
                    crate::ios_p2p_diagnostics::record_milestone(
                        "relay-upgrade-parallel",
                        match ready.lane.label() {
                            "TCP" => "TCP passed the bidirectional path check",
                            "UDP" => "UDP passed the bidirectional path check",
                            "IPv6" => "IPv6 passed the bidirectional path check",
                            "WebSocket" => "WebSocket passed the bidirectional path check",
                            _ => "WebRTC passed the bidirectional path check",
                        },
                    );
                }
                self.ready.retain(|ready| ready.id & NATIVE != id & NATIVE);
                self.ready.push_back(ready);
            }
            Err(err) => {
                if self.quality.is_some() {
                    self.reset(id);
                }
                hbb_common::log::trace!("Parallel direct candidate {id} failed: {err}");
            }
        }
    }

    pub(super) fn request(&mut self, id: u64) {
        if self.selected.is_none() {
            self.selected = Some((id, Instant::now()));
        }
    }

    pub(super) async fn advance(
        &mut self,
        relay: &Relay,
        caller: bool,
    ) -> ResultType<Option<Direct>> {
        if self.quality.is_some() {
            if let Some((id, _)) = self.selected {
                return Ok(self.take(id));
            }
            if caller {
                if let Some(ready) = self.candidate() {
                    let id = ready.id;
                    self.request(id);
                    self.pending.push(id);
                    self.checks
                        .push(async move { (id, confirm(ready, true).await) }.boxed());
                }
            }
            return Ok(None);
        }
        if caller {
            if let Some((id, started)) = self.selected {
                if started.elapsed() < PATH_TIMEOUT {
                    return Ok(None);
                }
                self.reset(id);
                relay.send(frame(super::RESET, id, &[])).await?;
            }
            if let Some(id) = self.ready.front().map(|r| r.id) {
                self.selected = Some((id, Instant::now()));
                relay.send(frame(SELECT, id, &[])).await?;
            }
            return Ok(None);
        }
        if let Some((id, _)) = self.selected {
            if let Some(direct) = self.take(id) {
                relay.send(frame(SELECTED, id, &[])).await?;
                return Ok(Some(direct));
            }
        }
        Ok(None)
    }

    fn candidate(&mut self) -> Option<Ready> {
        if self.ready.is_empty() {
            return None;
        }
        let monitor = self.quality.as_ref()?;
        let now = Instant::now();
        let baseline = monitor.relay.score(now);
        let mut winner = None;
        let mut index = 0;
        while index < self.ready.len() {
            let ready = &self.ready[index];
            match (ready.samples.score(now), baseline) {
                (Some(direct), Some(relay)) if quality::faster(direct, relay) => {
                    if winner.map_or(true, |(_, best, _)| direct < best) {
                        winner = Some((ready.id, direct, ready.lane.label()));
                    }
                }
                (_, None) if now.duration_since(ready.checked) < BASELINE_WAIT => {}
                (direct, baseline) => {
                    let id = ready.id;
                    hbb_common::throttled_log!(Duration::from_secs(10), info,
                        "Keeping relay after {} quality check: direct={direct:?} relay={baseline:?}", ready.lane.label());
                    #[cfg(target_os = "ios")]
                    crate::ios_p2p_diagnostics::record_path_quality(
                        ready.lane.label(),
                        direct,
                        baseline,
                        false,
                    );
                    self.ready.remove(index);
                    let next = now + RECHECK;
                    match id & NATIVE {
                        TCP => self.native_retry[0].defer(next),
                        UDP => self.native_retry[1].defer(next),
                        _ => self.rtc_after = Some(next),
                    }
                    continue;
                }
            }
            index += 1;
        }
        if let Some((id, score, label)) = winner {
            hbb_common::throttled_log!(
                Duration::from_secs(10),
                info,
                "Selecting {label} after quality check: direct={score:?} relay={baseline:?}"
            );
            #[cfg(target_os = "ios")]
            crate::ios_p2p_diagnostics::record_path_quality(label, Some(score), baseline, true);
            let index = self.ready.iter().position(|r| r.id == id)?;
            return self.ready.remove(index);
        }
        None
    }

    pub(super) fn take(&mut self, id: u64) -> Option<Direct> {
        if self.selected.map(|(selected, _)| selected) != Some(id) {
            return None;
        }
        let index = self
            .ready
            .iter()
            .position(|ready| ready.id == id && (self.quality.is_none() || ready.confirmed))?;
        let ready = self.ready.remove(index)?;
        self.selected = None;
        self.ready.clear();
        self.checks.clear();
        self.pending.clear();
        Some(Direct::new(id, ready.lane))
    }

    pub(super) fn reset(&mut self, id: u64) {
        if self.selected.is_some_and(|(selected, _)| selected == id) {
            self.selected = None;
        }
        self.ready.retain(|ready| ready.id != id);
    }
}

async fn verify(mut lane: Lane, id: u64, caller: bool, measured: bool) -> ResultType<Ready> {
    let mut samples = quality::Samples::default();
    let payload: &[u8] = if measured { &quality::PAYLOAD } else { &[] };
    for _ in 0..if measured { quality::COUNT } else { 1 } {
        let started = Instant::now();
        timeout(PATH_TIMEOUT, async {
            if caller {
                lane.write(frame(PROBE, id, payload), false).await.1?;
            }
            let expected = if caller { REPLY } else { PROBE };
            let packet = lane.next().await.transpose()?;
            if packet.as_deref().and_then(decode) != Some((expected, id, payload)) {
                bail!("Parallel direct path did not answer its probe");
            }
            if !caller {
                lane.write(frame(REPLY, id, payload), false).await.1?;
            }
            Ok::<_, hbb_common::anyhow::Error>(())
        })
        .await??;
        if caller && measured {
            let now = Instant::now();
            samples.record(now.duration_since(started), now);
        }
    }
    let ready = Ready {
        id,
        lane,
        samples,
        checked: Instant::now(),
        confirmed: false,
    };
    if measured && !caller {
        confirm(ready, false).await
    } else {
        Ok(ready)
    }
}

async fn confirm(mut ready: Ready, caller: bool) -> ResultType<Ready> {
    // This lane already exchanged authenticated round trips. Keep election traffic
    // off the relay's ordered video queue. Application data still obey the drain barrier.
    let budget = if caller {
        (ready.samples.score(Instant::now()).unwrap_or(PATH_TIMEOUT) * 4
            + Duration::from_millis(500))
        .clamp(PATH_TIMEOUT, Duration::from_secs(8))
    } else {
        // Retire an abandoned lane before the next attempt, even if its FIN was lost.
        BASELINE_WAIT + PATH_TIMEOUT
    };
    timeout(budget, async {
        if caller {
            ready
                .lane
                .write(frame(SELECT, ready.id, &[]), false)
                .await
                .1?;
        }
        let expected = if caller { SELECTED } else { SELECT };
        let packet = ready.lane.next().await.transpose()?;
        if packet.as_deref().and_then(decode) != Some((expected, ready.id, &[][..])) {
            bail!("Direct candidate selection was not confirmed");
        }
        if !caller {
            ready
                .lane
                .write(frame(SELECTED, ready.id, &[]), false)
                .await
                .1?;
        }
        ready.confirmed = true;
        Ok(ready)
    })
    .await?
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };

    #[tokio::test(start_paused = true)]
    async fn a_failed_native_transport_retries_while_the_other_is_still_dialing() {
        for failed in 0..2 {
            let attempts = Arc::new(AtomicUsize::new(0));
            let dials: Dials = [0, 1].map(|index| {
                let attempts = attempts.clone();
                let dial: native::Dial = Box::new(move || {
                    if index == failed {
                        attempts.fetch_add(1, Ordering::Relaxed);
                        async { bail!("dial failed") }.boxed()
                    } else {
                        std::future::pending().boxed()
                    }
                });
                Some(dial)
            });
            let mut race = Race::caller([0; 32], dials);
            race.start_native(Instant::now());
            race.checked().await;
            assert_eq!(attempts.load(Ordering::Relaxed), 1);
            tokio::time::advance(Duration::from_secs(2)).await;
            race.start_native(Instant::now());
            assert_eq!(attempts.load(Ordering::Relaxed), 2);
        }
    }
}
