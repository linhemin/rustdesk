//! Paced, directional checks from fresh ports while ordinary ICE remains active.
use super::*;
use std::collections::HashSet;

pub(in crate::live_direct) const FULL_SELECT: u8 = 29;
pub(in crate::live_direct) const FULL_RESULT: u8 = 30;
pub(in crate::live_direct) const FULL_HINT: u8 = 31;
pub(in crate::live_direct) const MAX_FULL_ENDPOINTS: usize = 500;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct FullSample {
    local: u16,
    peer: u16,
    written: u16,
    ingress: Option<u16>,
    finished: bool,
}

impl FullSample {
    fn bytes(self) -> [u8; 9] {
        let mut data = [0; 9];
        for (slot, value) in data.chunks_exact_mut(2).zip([
            self.local,
            self.peer,
            self.written,
            self.ingress.unwrap_or(u16::MAX),
        ]) {
            slot.copy_from_slice(&value.to_be_bytes());
        }
        data[8] = u8::from(self.finished);
        data
    }

    pub(in crate::live_direct) fn decode(data: &[u8]) -> Option<Self> {
        let [a, b, c, d, e, f, g, h, finished] = *<&[u8; 9]>::try_from(data).ok()?;
        let local = u16::from_be_bytes([a, b]);
        let peer = u16::from_be_bytes([c, d]);
        let written = u16::from_be_bytes([e, f]);
        let ingress = u16::from_be_bytes([g, h]);
        if usize::from(local.max(peer)) > MAX_FULL_ENDPOINTS
            || ((local == 0 || peer == 0) && written > 0)
            || (ingress != u16::MAX && ingress > written)
            || finished > 1
        {
            return None;
        }
        Some(Self {
            local,
            peer,
            written,
            ingress: (ingress != u16::MAX).then_some(ingress),
            finished: finished == 1,
        })
    }
}

impl fmt::Display for FullSample {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "freshLocal={} freshPeer={} writes={} finished={} exactIngress=",
            self.local, self.peer, self.written, self.finished,
        )?;
        match self.ingress {
            Some(n) => write!(f, "{n}"),
            None => f.write_str("pending"),
        }
    }
}

fn endpoints(data: &[u8], limit: u16) -> ResultType<Vec<SocketAddrV4>> {
    ensure!(
        data.len() <= usize::from(limit) * 6 && data.len() % 6 == 0,
        "invalid full selection size"
    );
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for ep in data.chunks_exact(6) {
        let addr = SocketAddrV4::new(
            Ipv4Addr::new(ep[0], ep[1], ep[2], ep[3]),
            u16::from_be_bytes([ep[4], ep[5]]),
        );
        ensure!(
            WebRTCStream::valid_expanded_endpoint(addr) && seen.insert(addr),
            "invalid full selection member"
        );
        result.push(addr);
    }
    Ok(result)
}

async fn check_rounds(
    exchange: &mut Exchange<'_>,
    pc: &WebRTCStream,
    plan: Plan,
    controller: bool,
    linear_step: Option<u16>,
    status: &watch::Sender<PunchStatus>,
    report: &mut FullSample,
    checked: &mut HashSet<(String, SocketAddrV4)>,
) -> ResultType<()> {
    exchange
        .send(FULL_HINT, &linear_step.unwrap_or(0).to_be_bytes())
        .await?;
    let peer_step = u16::from_be_bytes(exchange.read::<2>(FULL_HINT).await?);
    let mut at = exchange.deadline(controller).await?.0;
    let end = at + plan.window();
    let send_end = at + plan.send_window(controller) + plan.lead_delay(controller, 0);
    let mut round = 0;
    let mut local = Vec::new();
    let mut peers = Vec::new();
    let mut seen = HashSet::new();
    let mut advertised = HashSet::new();
    while Instant::now() < end && pc.is_relayed().await.is_none() {
        let gathered = pc.expanded_udp_candidates().await;
        let mut wire = Vec::new();
        for (id, addr) in gathered {
            if local.len() == usize::from(plan.capacity(controller)) {
                break;
            }
            if seen.insert(addr) {
                local.push((id, addr));
                wire.extend_from_slice(&addr.ip().octets());
                wire.extend_from_slice(&addr.port().to_be_bytes());
            }
        }
        report.local = local.len() as u16;
        status.send_modify(|s| s.full = Some(*report));
        exchange.send(FULL_SELECT, &wire).await?;
        let (kind, data) = exchange
            .incoming
            .recv()
            .await
            .context("full selection missing")?;
        ensure!(kind == FULL_SELECT, "unexpected full selection");
        let remaining = plan.capacity(!controller) - peers.len() as u16;
        for ep in endpoints(&data, remaining)? {
            ensure!(advertised.insert(ep), "duplicate full selection");
            peers.push(ep);
        }
        report.peer = peers.len() as u16;
        status.send_modify(|s| s.full = Some(*report));
        if !local.is_empty() && !peers.is_empty() {
            let phase = at.max(Instant::now() + Duration::from_millis(40))
                + plan.lead_delay(controller, round);
            let mut next = phase;
            for i in 0..local.len().max(peers.len()) {
                if next >= send_end {
                    break;
                }
                tokio::time::sleep_until(next).await;
                if i % 8 == 0 && pc.is_relayed().await.is_some() {
                    return Ok(());
                }
                let (own, peer) = Plan::pair(controller, local.len(), peers.len(), i, round);
                let (id, _) = &local[own];
                let advertised = peers[peer];
                let latest = peers
                    .last()
                    .filter(|last| last.ip() == advertised.ip())
                    .map_or(advertised.port(), SocketAddrV4::port);
                let target = SocketAddrV4::new(
                    *advertised.ip(),
                    plan.target_port(controller, advertised.port(), latest, peer_step, i, round),
                );
                if pc.expanded_first_check(id, target).await {
                    report.written = report.written.saturating_add(1);
                    checked.insert((id.clone(), target));
                }
                // A stalled scheduler must not catch up with a burst.
                next = Instant::now() + plan.spacing();
            }
            round += 1;
        } else if local.is_empty() && pc.expanded_udp_pool_complete().await {
            break;
        }
        status.send_modify(|s| s.full = Some(*report));
        at = Instant::now() + Duration::from_millis(240);
        tokio::time::sleep_until(at).await;
    }
    Ok(())
}

pub(in crate::live_direct) async fn run_full(
    pc: &WebRTCStream,
    events: &mpsc::Sender<SetupEvent>,
    id: u64,
    controller: bool,
    control: mpsc::Receiver<(u8, Vec<u8>)>,
    status: watch::Sender<PunchStatus>,
    plan: Plan,
    linear_step: Option<u16>,
) {
    let mut exchange = Exchange {
        events,
        incoming: control,
        id,
        origin: Instant::now(),
    };
    let mut report = FullSample::default();
    let mut checked = HashSet::new();
    status.send_modify(|s| s.full = Some(report));
    let budget = plan.window() + Duration::from_secs(5);
    let checks = timeout(
        budget,
        check_rounds(
            &mut exchange,
            pc,
            plan,
            controller,
            linear_step,
            &status,
            &mut report,
            &mut checked,
        ),
    )
    .await;
    match checks {
        Ok(Ok(())) => {}
        Ok(Err(err)) => hbb_common::log::trace!("Full candidate exchange failed: {err}"),
        Err(_) => hbb_common::log::trace!("Full candidate exchange timed out"),
    }
    report.finished = true;
    report.ingress = pc.expanded_pair_ingress(&checked).await.map(|n| n as u16);
    status.send_modify(|s| s.full = Some(report));
    let _ = exchange.send(FULL_RESULT, &report.bytes()).await;
    if id <= 3 || id.is_power_of_two() {
        hbb_common::log::info!(
            "RustDesk expanded ports attempt {id} {:?}: {report}",
            plan.nats
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_malformed_or_private_candidate_batches() {
        let valid = [8, 8, 8, 8, 0xea, 0x61];
        assert_eq!(endpoints(&valid, 1).unwrap().len(), 1);
        assert!(endpoints(&[valid, valid].concat(), 2).is_err());
        assert!(endpoints(&valid, 0).is_err());
        assert!(endpoints(&[10, 0, 0, 1, 0xea, 0x61], 1).is_err());
        let sample = FullSample {
            local: 500,
            peer: 150,
            written: 900,
            ingress: Some(2),
            finished: true,
        };
        assert_eq!(FullSample::decode(&sample.bytes()).unwrap().written, 900);
    }
}
