use base::message_proto::{Message, Misc, UdpProbeDestination, UdpProbePort, UdpProbeReport};
use hbb_common::{sodiumoxide::crypto::auth, tokio::sync::oneshot};
use std::{
    collections::{BTreeMap, VecDeque},
    fmt::Write,
    net::SocketAddr,
    sync::{
        atomic::{AtomicU32, Ordering::Relaxed},
        Mutex,
    },
    time::{Duration, Instant},
};

pub(crate) type Id = [u8; 32];
const MAX_DESTINATIONS: usize = 32;

pub(crate) fn id(key: &auth::Key) -> Id {
    auth::authenticate(b"RustDesk native UDP peer report v1", key).0
}

pub(crate) fn label(id: &Id) -> String {
    // A display identifier, independent of the capability used to retrieve the report.
    let digest = hbb_common::sodiumoxide::crypto::hash::sha256::hash(id);
    hex::encode(&digest.0[..6])
}

#[derive(Default)]
pub(super) struct Port {
    pub local: u16,
    pub rx: AtomicU32,
    pub tx: AtomicU32,
    pub replies: AtomicU32,
    pub errors: AtomicU32,
    pub verified: AtomicU32,
    destinations: Mutex<BTreeMap<SocketAddr, (u32, u32)>>,
    unlisted: AtomicU32,
}

impl Port {
    pub(super) fn record_destination(&self, to: SocketAddr, sent: bool) {
        let mut rows = self.destinations.lock().unwrap();
        if rows.len() >= MAX_DESTINATIONS && !rows.contains_key(&to) {
            self.unlisted.fetch_add(1, Relaxed);
            return;
        }
        let (ok, errors) = rows.entry(to).or_default();
        if sent { *ok += 1; } else { *errors += 1; }
    }
}

type Pending = (Id, Instant, oneshot::Receiver<UdpProbeReport>);
static PENDING: Mutex<VecDeque<Pending>> = Mutex::new(VecDeque::new());

pub(crate) struct Recording {
    id: Id,
    pub(super) ports: Vec<Port>,
    finished: Option<oneshot::Sender<UdpProbeReport>>,
}

impl Recording {
    pub(super) fn start(id: Id, ports: impl Iterator<Item = u16>) -> Self {
        let (recording, rx) = Self::local(id, ports);
        let mut pending = PENDING.lock().unwrap();
        pending.retain(|(_, start, _)| start.elapsed() < Duration::from_secs(60));
        if pending.len() >= 64 {
            pending.pop_front();
        }
        pending.push_back((id, Instant::now(), rx));
        recording
    }

    pub(crate) fn local(id: Id, ports: impl Iterator<Item = u16>) -> (Self, oneshot::Receiver<UdpProbeReport>) {
        let (tx, rx) = oneshot::channel();
        (Self {
            id,
            ports: ports
                .map(|local| Port {
                    local,
                    ..Default::default()
                })
                .collect(),
            finished: Some(tx),
        }, rx)
    }
}

impl Drop for Recording {
    fn drop(&mut self) {
        if let Some(done) = self.finished.take() {
            let ports = self
                .ports
                .iter()
                .map(|p| UdpProbePort {
                    local_port: p.local.into(),
                    received: p.rx.load(Relaxed),
                    sent: p.tx.load(Relaxed),
                    replies: p.replies.load(Relaxed),
                    send_errors: p.errors.load(Relaxed),
                    verified: p.verified.load(Relaxed),
                    destinations: p.destinations.lock().unwrap().iter().map(|(to, &(sent, errors))| UdpProbeDestination {
                        endpoint: to.to_string(), sent, send_errors: errors, ..Default::default()
                    }).collect(),
                    unlisted_attempts: p.unlisted.load(Relaxed),
                    ..Default::default()
                })
                .collect();
            // The controller can disconnect without asking for this round.
            let _ = done.send(UdpProbeReport {
                round: self.id.to_vec().into(),
                ports,
                ..Default::default()
            });
        }
    }
}

pub(crate) fn take(raw: &[u8]) -> Option<oneshot::Receiver<UdpProbeReport>> {
    let id: &Id = raw.try_into().ok()?;
    let mut pending = PENDING.lock().unwrap();
    let index = pending
        .iter()
        .position(|(stored, start, _)| stored == id && start.elapsed() < Duration::from_secs(60))?;
    pending.remove(index).map(|(_, _, rx)| rx)
}

pub(crate) fn query(id: &Id) -> Message {
    let mut misc = Misc::new();
    misc.set_udp_probe_query(id.to_vec().into());
    let mut message = Message::new();
    message.set_misc(misc);
    message
}

pub(crate) fn display(id: &Id, report: &UdpProbeReport) -> Option<String> {
    if report.round.as_ref() != id || report.ports.is_empty() || report.ports.len() > super::udp_paths::MAX_LOCAL_SOCKETS {
        return None;
    }
    let mut out = format!("UDP #{}", label(id));
    let mut received = 0u64;
    let mut replies = 0u64;
    for row in &report.ports {
        if !(1..=65535).contains(&row.local_port)
            || row.replies > row.sent
            || row.verified > row.received
        {
            return None;
        }
        received += u64::from(row.received);
        replies += u64::from(row.replies);
    }
    writeln!(out, "  RX {received}  ACK TX {replies}").ok()?;
    out.push_str("local port | RX | valid RX | TX | ACK TX | TX err");
    for p in &report.ports {
        write!(
            out,
            "\n{} | {} | {} | {} | {} | {}",
            p.local_port, p.received, p.verified, p.sent, p.replies, p.send_errors
        )
        .ok()?;
    }
    if report.ports.iter().any(|p| !p.destinations.is_empty() || p.unlisted_attempts != 0) {
        out.push_str("\n\nlocal port → destination | TX | TX err");
        for p in &report.ports {
            if p.destinations.len() > MAX_DESTINATIONS { return None; }
            for d in &p.destinations {
                let to: SocketAddr = d.endpoint.parse().ok()?;
                write!(out, "\n{} → {} | {} | {}", p.local_port, to, d.sent, d.send_errors).ok()?;
            }
            if p.unlisted_attempts > 0 {
                write!(out, "\n{} · additional attempts: {}", p.local_port, p.unlisted_attempts).ok()?;
            }
        }
    }
    Some(out)
}
