use super::{auth, bind_observed_port, check_socket, Counts, Port, Recording, MAX_LOCAL_SOCKETS};
use hbb_common::{
    bytes::BytesMut,
    futures_util::{stream::FuturesUnordered, StreamExt},
    tokio::{
        self,
        net::UdpSocket,
        sync::Semaphore,
        time::{Duration, Instant},
    },
    ResultType,
};
use std::{
    net::SocketAddr,
    sync::{
        atomic::{AtomicBool, Ordering::Relaxed},
        Arc,
    },
};

const TIERS: [(u64, usize); 4] = [(6, 48), (16, 128), (28, 256), (40, MAX_LOCAL_SOCKETS)];
static ACTIVE: Semaphore = Semaphore::const_new(1);

pub(super) struct Plan {
    source: SocketAddr,
    sockets: Vec<Arc<UdpSocket>>,
    verified: Vec<SocketAddr>,
}

impl Plan {
    pub(super) fn new(
        primary: &Arc<UdpSocket>,
        extra: &[Arc<UdpSocket>],
        peer: SocketAddr,
        ports: &[u32],
    ) -> Option<Self> {
        // Only these supplementary ports carry the NAS's mapping receipts.
        let mut verified = Vec::new();
        for &port in ports.iter().take(super::WIDE_EXTRA_SOCKETS) {
            if let Ok(port) = u16::try_from(port) {
                let mut addr = peer;
                addr.set_port(port);
                if port != 0 && !verified.contains(&addr) {
                    verified.push(addr);
                }
            }
        }
        if verified.is_empty() {
            return None;
        }
        let sockets = std::iter::once(primary.clone())
            .chain(extra.iter().cloned())
            .collect();
        Some(Self {
            source: primary.local_addr().ok()?,
            sockets,
            verified,
        })
    }

    pub(super) async fn run(
        self,
        start: Instant,
        listen: bool,
        key: &auth::Key,
        report: Option<&Recording>,
        mut totals: Counts,
    ) -> ResultType<(Arc<UdpSocket>, Option<BytesMut>)> {
        let Ok(_slot) = ACTIVE.try_acquire() else {
            return Err(totals.into());
        };
        let end = start + Duration::from_secs(60);
        let seen = AtomicBool::new(false);
        let mut jobs = FuturesUnordered::new();
        let make_job = |socket, i: usize, row: Option<Arc<Port>>| {
            let peers = vec![self.verified[i % self.verified.len()]];
            let seen = &seen;
            async move {
                check_socket(
                    socket,
                    peers,
                    listen,
                    key,
                    row.as_deref(),
                    Some((end, seen)),
                )
                .await
            }
        };
        for (i, socket) in self.sockets.into_iter().enumerate() {
            jobs.push(make_job(
                socket,
                i,
                report.and_then(|r| r.ports.get(i)).cloned(),
            ));
        }
        let mut tier = 0;
        let mut next = start + Duration::from_secs(TIERS[0].0);
        while !jobs.is_empty() {
            tokio::select! {
                result = jobs.next() => match result {
                    Some(Ok(path)) => return Ok(path),
                    Some(Err(err)) => if let Some(c) = err.downcast_ref::<Counts>() {
                        totals.sent += c.sent;
                        totals.errors += c.errors;
                        totals.received += c.received;
                        totals.authenticated += c.authenticated;
                        totals.valid_foreign += c.valid_foreign;
                        totals.verified_foreign += c.verified_foreign;
                    } else { hbb_common::log::trace!("UDP candidate socket closed: {err}") },
                    None => break,
                },
                _ = tokio::time::sleep_until(next), if tier < TIERS.len() && !seen.load(Relaxed) && next < end => {
                    if Instant::now() >= end || seen.load(Relaxed) {
                        tier = TIERS.len();
                        continue;
                    }
                    if let Some(socket) = bind_observed_port(self.source, 0).await {
                        let port = socket.local_addr()?.port();
                        let row = report.map(|r| r.add_socket(port));
                        jobs.push(make_job(Arc::new(socket), totals.sockets, row));
                        totals.sockets += 1;
                    } else {
                        // Keep the existing candidates alive if the OS is out of descriptors.
                        tier = TIERS.len();
                        continue;
                    }
                    if totals.sockets >= TIERS[tier].1 {
                        tier += 1;
                        next = TIERS.get(tier).map_or(end, |t| start + Duration::from_secs(t.0));
                    } else {
                        next = Instant::now() + Duration::from_millis(12);
                    }
                }
            }
        }
        Err(totals.into())
    }
}
