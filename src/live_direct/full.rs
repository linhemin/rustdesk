//! One paced pass over fresh sockets observed by the session's signed observer.
use super::*;
use std::collections::HashSet;

pub(in crate::live_direct) const FULL_SELECT: u8 = 29;
pub(in crate::live_direct) const FULL_RESULT: u8 = 30;
pub(in crate::live_direct) const MAX_FULL_ENDPOINTS: usize = 32;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct FullSample {
    local: u8,
    peer: u8,
    written: u8,
    ingress: Option<u8>,
    released: bool,
}

impl FullSample {
    fn bytes(self) -> [u8; 5] {
        [
            self.local,
            self.peer,
            self.written,
            self.ingress.unwrap_or(255),
            u8::from(self.released),
        ]
    }

    pub(in crate::live_direct) fn decode(data: &[u8]) -> Option<Self> {
        let &[local, peer, written, ingress, released] = <&[u8; 5]>::try_from(data).ok()?;
        let limit = local.max(peer);
        if limit as usize > MAX_FULL_ENDPOINTS
            || written > limit
            || ((local == 0 || peer == 0) && written > 0)
            || (ingress != 255 && ingress > written)
            || released > 1
        {
            return None;
        }
        Some(Self {
            local,
            peer,
            written,
            ingress: (ingress != 255).then_some(ingress),
            released: released != 0,
        })
    }
}

impl fmt::Display for FullSample {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "freshLocal={} freshPeer={} firstWrites={} released={} exactIngress=",
            self.local, self.peer, self.written, self.released
        )?;
        match self.ingress {
            Some(n) => write!(f, "{n}"),
            None => f.write_str("pending"),
        }
    }
}

fn endpoints(data: &[u8]) -> ResultType<Vec<SocketAddrV4>> {
    ensure!(
        data.len() <= MAX_FULL_ENDPOINTS * 6 && data.len() % 6 == 0,
        "invalid full selection size"
    );
    let mut result = Vec::new();
    for ep in data.chunks_exact(6) {
        let addr = SocketAddrV4::new(
            Ipv4Addr::new(ep[0], ep[1], ep[2], ep[3]),
            u16::from_be_bytes([ep[4], ep[5]]),
        );
        ensure!(
            addr.port() != 0 && !result.contains(&addr),
            "invalid full selection member"
        );
        result.push(addr);
    }
    Ok(result)
}

async fn first_checks(
    exchange: &mut Exchange<'_>,
    pc: &WebRTCStream,
    controller: bool,
    remote: &mut mpsc::Receiver<String>,
    held: &mut Vec<String>,
    exact: &mut Vec<(String, SocketAddrV4)>,
    status: &watch::Sender<PunchStatus>,
    report: &mut FullSample,
) -> ResultType<()> {
    let gather_until = Instant::now() + Duration::from_secs(11);
    let mut local = loop {
        // Check completion first: a completed epoch's snapshot includes its final socket.
        let complete = pc.expanded_udp_pool_complete().await;
        let batch = pc.expanded_udp_candidates().await;
        if complete || batch.len() >= MAX_FULL_ENDPOINTS || Instant::now() >= gather_until {
            break batch;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    };
    let mut unique = HashSet::new();
    local.retain(|(_, ep)| unique.insert(*ep));
    local.truncate(MAX_FULL_ENDPOINTS);
    report.local = local.len() as u8;
    status.send_modify(|s| s.full = Some(*report));
    let mut wire = Vec::with_capacity(6 * local.len());
    for (_, ep) in &local {
        wire.extend_from_slice(&ep.ip().octets());
        wire.extend_from_slice(&ep.port().to_be_bytes());
    }
    exchange.send(FULL_SELECT, &wire).await?;
    let (kind, bytes) = exchange
        .incoming
        .recv()
        .await
        .context("full selection missing")?;
    ensure!(kind == FULL_SELECT, "unexpected full selection");
    let peers = endpoints(&bytes)?;
    report.peer = peers.len() as u8;
    status.send_modify(|s| s.full = Some(*report));
    if local.is_empty() || peers.is_empty() {
        return Ok(());
    }

    // A SELECT cannot introduce destinations. Every member must also be a public
    // server-reflexive candidate trickled on this authenticated ICE generation.
    let mut indices = vec![None; peers.len()];
    while indices.iter().any(Option::is_none) {
        let candidate = remote.recv().await.context("full trickle ended")?;
        if let Some(ep) = WebRTCStream::public_srflx_endpoint(candidate.as_bytes()) {
            if let Some(pos) = peers.iter().position(|v| *v == ep) {
                indices[pos] = Some(held.len());
            }
        }
        held.push(candidate);
    }
    let (at, _) = exchange.deadline(controller).await?;
    // Both sides apply the same schedule even if their observer coverage differs.
    // A single linear pass tries every advertised socket without an N*M burst.
    for i in 0..local.len().max(peers.len()) {
        tokio::time::sleep_until(at + Duration::from_millis(10 * i as u64)).await;
        let id = &local[i % local.len()].0;
        let n = i % peers.len();
        let index = indices[n].context("full candidate unavailable")?;
        if pc.timed_first_check(id, &held[index]).await {
            report.written += 1;
            exact.push((id.clone(), peers[n]));
            status.send_modify(|s| s.full = Some(*report));
        }
    }
    Ok(())
}

pub(in crate::live_direct) async fn run_full(
    pc: &WebRTCStream,
    events: &mpsc::Sender<SetupEvent>,
    id: u64,
    controller: bool,
    control: mpsc::Receiver<(u8, Vec<u8>)>,
    remote: &mut mpsc::Receiver<String>,
    status: watch::Sender<PunchStatus>,
) {
    let mut exchange = Exchange {
        events,
        incoming: control,
        id,
        origin: Instant::now(),
    };
    let mut report = FullSample::default();
    let mut held = Vec::new();
    let mut exact = Vec::new();
    status.send_modify(|s| s.full = Some(report));
    // A silent observer/peer must not starve IPv6, LAN or ordinary ICE for this attempt.
    let checks = timeout(
        Duration::from_secs(17),
        first_checks(
            &mut exchange,
            pc,
            controller,
            remote,
            &mut held,
            &mut exact,
            &status,
            &mut report,
        ),
    )
    .await;
    match checks {
        Ok(Ok(())) => {}
        Ok(Err(err)) => hbb_common::log::trace!("Full candidate exchange failed: {err}"),
        Err(_) => hbb_common::log::trace!("Full candidate exchange timed out"),
    }
    for candidate in held {
        if pc.add_remote_ice_candidate(&candidate).await.is_err() {
            hbb_common::log::trace!("Full attempt rejected a queued candidate");
        }
    }
    report.released = true;
    status.send_modify(|s| s.full = Some(report));
    if exchange.send(FULL_RESULT, &report.bytes()).await.is_err() {
        return;
    }
    if !exact.is_empty() {
        tokio::time::sleep(Duration::from_millis(900)).await;
        report.ingress = pc.expanded_pair_ingress(&exact).await.map(|n| n as u8);
        status.send_modify(|s| s.full = Some(report));
        if exchange.send(FULL_RESULT, &report.bytes()).await.is_err() {
            return;
        }
    }
    if id <= 3 || id.is_power_of_two() {
        hbb_common::log::info!("RustDesk expanded ports attempt {id}: {report}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expanded_selection_and_reports_are_bounded() {
        let valid = [8, 8, 8, 8, 0, 80];
        assert!(endpoints(&[]).unwrap().is_empty());
        assert_eq!(endpoints(&valid).unwrap().len(), 1);
        assert!(endpoints(&[valid, valid].concat()).is_err());
        assert!(endpoints(&[0; 193]).is_err());
        assert!(FullSample::decode(&[32, 8, 32, 255, 1]).is_some());
        assert!(FullSample::decode(&[0, 8, 1, 1, 1]).is_none());
        assert!(FullSample::decode(&[32, 32, 4, 5, 1]).is_none());
    }
}
