use super::{decode, frame, native, Direct, Lane, Relay, PATH_TIMEOUT};
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

pub(crate) type Dials = [Option<native::Dial>; 2];
type Check = BoxFuture<'static, (u64, ResultType<Lane>)>;

#[derive(Default)]
pub(super) struct Race {
    caller: Option<([u8; 32], Dials)>,
    checks: FuturesUnordered<Check>,
    pending: Vec<u64>,
    ready: VecDeque<(u64, Lane)>,
    selected: Option<(u64, Instant)>,
    native_attempt: u64,
    native_retry: Option<Instant>,
}

impl Race {
    pub(super) fn caller(ticket: [u8; 32], dials: Dials) -> Self {
        Self {
            caller: Some((ticket, dials)),
            ..Self::default()
        }
    }

    pub(super) fn is_caller(&self) -> bool {
        self.caller.is_some()
    }

    fn busy(&self, family: u64) -> bool {
        self.pending.iter().any(|id| id & NATIVE == family)
            || self.ready.iter().any(|(id, _)| id & NATIVE == family)
    }

    pub(super) fn rtc_busy(&self) -> bool {
        self.busy(0) || self.selected.is_some()
    }

    pub(super) fn defer_native(&mut self, until: Instant) {
        self.native_retry = Some(self.native_retry.map_or(until, |retry| retry.max(until)));
    }

    pub(super) fn start_native(&mut self, now: Instant) {
        if self.selected.is_some()
            || self.busy(TCP)
            || self.busy(UDP)
            || self.native_retry.is_some_and(|retry| now < retry)
        {
            return;
        }
        let Some((ticket, dials)) = self.caller.as_ref() else {
            return;
        };
        self.native_attempt += 1;
        for (family, dial) in [TCP, UDP].into_iter().zip(dials) {
            let Some(dial) = dial else { continue };
            let dial = dial();
            let ticket = *ticket;
            let id = self.native_attempt | family;
            self.pending.push(id);
            let attempt = async move {
                let budget = if family == UDP { 75 } else { 45 };
                let lane = timeout(Duration::from_secs(budget), async {
                    native::attach(ticket, id, dial.await?).await
                })
                .await??;
                verify(Lane::Native(lane), id, true).await
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
        self.checks
            .push(async move { (id, verify(lane, id, caller).await) }.boxed());
    }

    pub(super) fn is_checking(&self) -> bool {
        !self.checks.is_empty()
    }

    pub(super) async fn checked(&mut self) {
        let Some((id, result)) = self.checks.next().await else {
            return;
        };
        self.pending.retain(|pending| *pending != id);
        if id & NATIVE != 0 {
            self.native_retry = Some(Instant::now() + Duration::from_secs(10));
        }
        match result {
            Ok(lane) => {
                #[cfg(target_os = "ios")]
                crate::ios_p2p_diagnostics::record_milestone(
                    "relay-upgrade-parallel",
                    match lane.label() {
                        "TCP" => "TCP passed the bidirectional path check",
                        "UDP" => "UDP passed the bidirectional path check",
                        "IPv6" => "IPv6 passed the bidirectional path check",
                        _ => "WebRTC passed the bidirectional path check",
                    },
                );
                self.ready
                    .retain(|(ready, _)| ready & NATIVE != id & NATIVE);
                self.ready.push_back((id, lane));
            }
            Err(err) => hbb_common::log::trace!("Parallel direct candidate {id} failed: {err}"),
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
        if caller {
            if let Some((id, started)) = self.selected {
                if started.elapsed() < PATH_TIMEOUT {
                    return Ok(None);
                }
                self.reset(id);
                relay.send(frame(super::RESET, id, &[])).await?;
            }
            if let Some((id, _)) = self.ready.front() {
                self.selected = Some((*id, Instant::now()));
                relay.send(frame(SELECT, *id, &[])).await?;
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

    pub(super) fn take(&mut self, id: u64) -> Option<Direct> {
        if self.selected.map(|(selected, _)| selected) != Some(id) {
            return None;
        }
        let index = self.ready.iter().position(|(ready, _)| *ready == id)?;
        let (_, lane) = self.ready.remove(index)?;
        self.selected = None;
        self.ready.clear();
        self.checks.clear();
        self.pending.clear();
        Some(Direct::new(id, lane))
    }

    pub(super) fn reset(&mut self, id: u64) {
        if self.selected.is_some_and(|(selected, _)| selected == id) {
            self.selected = None;
        }
        self.ready.retain(|(ready, _)| *ready != id);
    }
}

async fn verify(mut lane: Lane, id: u64, caller: bool) -> ResultType<Lane> {
    timeout(PATH_TIMEOUT, async {
        if caller {
            lane.write(frame(PROBE, id, &[]), false).await.1?;
        }
        let expected = if caller { REPLY } else { PROBE };
        let packet = lane.next().await.transpose()?;
        if packet.as_deref().and_then(decode) != Some((expected, id, &[][..])) {
            bail!("Parallel direct path did not answer its probe");
        }
        if !caller {
            lane.write(frame(REPLY, id, &[]), false).await.1?;
        }
        Ok(lane)
    })
    .await?
}
