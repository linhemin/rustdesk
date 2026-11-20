use super::{frame, PunchStatus, SetupEvent, WebRTCStream};
use hbb_common::{
    anyhow::{anyhow, ensure, Context},
    tokio::{
        self,
        sync::{mpsc, watch},
        time::{timeout, Duration, Instant},
    },
    ResultType,
};
use std::{
    fmt,
    net::{Ipv4Addr, SocketAddrV4},
};

pub(super) const SELECT: u8 = 16;
const READY: u8 = 17;
const PING: u8 = 18;
const PONG: u8 = 19;
pub(super) const GO: u8 = 20;
pub(super) const RESULT: u8 = 21;
pub(super) const GROUP_SELECT: u8 = 23;
pub(super) const GROUP_RESULT: u8 = 24;
pub(super) const PROFILE: u8 = 25;
#[path = "groups.rs"]
mod groups;
pub(crate) use groups::GroupSample;
const BUDGET: Duration = Duration::from_secs(7);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Sample {
    state: u8,
    rtt_ms: u16,
    late_ms: u16,
}

impl Sample {
    fn bytes(self) -> [u8; 5] {
        let rtt = self.rtt_ms.to_be_bytes();
        let late = self.late_ms.to_be_bytes();
        [self.state, rtt[0], rtt[1], late[0], late[1]]
    }

    pub(super) fn decode(data: &[u8]) -> Option<Self> {
        let &[state, rh, rl, lh, ll] = <&[u8; 5]>::try_from(data).ok()?;
        (state <= 4).then(|| Self {
            state,
            rtt_ms: u16::from_be_bytes([rh, rl]),
            late_ms: u16::from_be_bytes([lh, ll]),
        })
    }
}

impl fmt::Display for Sample {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let status = match self.state {
            0 => "waiting",
            1 => "sent",
            2 => "notArmed",
            3 => "missedDeadline",
            _ => "writeFailed",
        };
        write!(
            f,
            "status={status} rttMs={} lateMs={}",
            self.rtt_ms, self.late_ms
        )
    }
}

struct Exchange<'a> {
    events: &'a mpsc::Sender<SetupEvent>,
    incoming: mpsc::Receiver<(u8, Vec<u8>)>,
    id: u64,
    origin: Instant,
}

impl Exchange<'_> {
    fn now(&self) -> u32 {
        self.origin.elapsed().as_millis().min(u32::MAX as u128) as u32
    }

    async fn send(&self, kind: u8, data: &[u8]) -> ResultType<()> {
        self.events
            .send(SetupEvent::Send(frame(kind, self.id, data)))
            .await
            .map_err(|_| anyhow!("timed signaling closed"))
    }

    async fn read<const N: usize>(&mut self, expected: u8) -> ResultType<[u8; N]> {
        let (kind, data) = self
            .incoming
            .recv()
            .await
            .context("timed signaling ended")?;
        ensure!(kind == expected, "unexpected timed frame");
        data.try_into()
            .map_err(|_| anyhow!("invalid timed frame length"))
    }

    // Each clock is monotonic and relative to this attempt. The lowest RTT of three
    // echoes estimates their offset without depending on either device's wall clock.
    async fn deadline(&mut self, controller: bool) -> ResultType<(Instant, u16)> {
        if controller {
            self.read::<0>(READY).await?;
            let mut best = None;
            for seq in 0..3 {
                let start = self.now();
                self.send(PING, &[seq]).await?;
                let [echo, a, b, c, d] = self.read::<5>(PONG).await?;
                ensure!(echo == seq, "unexpected timed echo");
                let rtt = self.now() - start;
                let offset =
                    i64::from(u32::from_be_bytes([a, b, c, d])) - i64::from(start + rtt / 2);
                if best.map_or(true, |(old, _)| rtt < old) {
                    best = Some((rtt, offset));
                }
            }
            let (rtt, offset) = best.context("missing clock sample")?;
            ensure!(rtt <= 850, "timed relay RTT exceeds budget");
            let at = self.now() + (2 * rtt + 150).max(400);
            let remote = u32::try_from(i64::from(at) + offset)?;
            let mut go = [0u8; 6];
            go[..4].copy_from_slice(&remote.to_be_bytes());
            go[4..].copy_from_slice(&(rtt as u16).to_be_bytes());
            self.send(GO, &go).await?;
            Ok((self.origin + Duration::from_millis(at.into()), rtt as u16))
        } else {
            self.send(READY, &[]).await?;
            for seq in 0..3 {
                ensure!(
                    self.read::<1>(PING).await? == [seq],
                    "unexpected timed ping"
                );
                let mut pong = [0u8; 5];
                pong[0] = seq;
                pong[1..].copy_from_slice(&self.now().to_be_bytes());
                self.send(PONG, &pong).await?;
            }
            let [a, b, c, d, rh, rl] = self.read::<6>(GO).await?;
            let at = u32::from_be_bytes([a, b, c, d]);
            let rtt = u16::from_be_bytes([rh, rl]);
            ensure!(
                rtt <= 850 && at <= self.now() + 2000,
                "invalid timed deadline"
            );
            Ok((self.origin + Duration::from_millis(at.into()), rtt))
        }
    }

    async fn first_check(
        &mut self,
        pc: &WebRTCStream,
        controller: bool,
        remote: &mut mpsc::Receiver<String>,
        held: &mut Vec<String>,
    ) -> ResultType<Sample> {
        let (socket, local) = loop {
            if let Some(c) = pc.timed_local_candidate().await {
                break c;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        };
        let mut select = [0u8; 6];
        select[..4].copy_from_slice(&local.ip().octets());
        select[4..].copy_from_slice(&local.port().to_be_bytes());
        self.send(SELECT, &select).await?;
        let [a, b, c, d, ph, pl] = self.read::<6>(SELECT).await?;
        let address = SocketAddrV4::new(Ipv4Addr::new(a, b, c, d), u16::from_be_bytes([ph, pl]));
        // SELECT can only refer to a regular candidate from this very same relay
        // attempt. All remote candidates remain outside ICE until the first write.
        let candidate = loop {
            let json = remote.recv().await.context("timed trickle ended")?;
            let matches =
                WebRTCStream::public_udp_candidate_endpoint(json.as_bytes()) == Some(address);
            held.push(json);
            if matches {
                break held.last().context("missing timed candidate")?;
            }
        };
        let (at, rtt_ms) = self.deadline(controller).await?;
        tokio::time::sleep_until(at).await;
        let late = || {
            Instant::now()
                .saturating_duration_since(at)
                .as_millis()
                .min(u16::MAX as u128) as u16
        };
        let state = if late() > 60 {
            3
        } else if pc.timed_first_check(&socket, candidate).await {
            1
        } else {
            4
        };
        let sample = Sample {
            state,
            rtt_ms,
            late_ms: late(),
        };
        if state == 1 && pc.add_remote_ice_candidate(candidate).await.is_ok() {
            held.pop();
        }
        Ok(sample)
    }
}

pub(super) async fn run(
    pc: &WebRTCStream,
    events: &mpsc::Sender<SetupEvent>,
    id: u64,
    controller: bool,
    control: mpsc::Receiver<(u8, Vec<u8>)>,
    remote: &mut mpsc::Receiver<String>,
    status: watch::Sender<PunchStatus>,
    grouped: bool,
) {
    let mut exchange = Exchange {
        events,
        incoming: control,
        id,
        origin: Instant::now(),
    };
    let mut held = Vec::new();
    let pending = Sample {
        state: 0,
        rtt_ms: 0,
        late_ms: 0,
    };
    status.send_modify(|s| s.timed_local = Some(pending));
    let mut exact = Vec::new();
    let sample = if grouped {
        let mut report = GroupSample::default();
        status.send_modify(|s| s.group_local = Some(report));
        let result = timeout(
            Duration::from_secs(10),
            exchange.group_checks(pc, controller, remote, &mut held, &mut exact, &mut report),
        )
        .await;
        status.send_modify(|s| s.group_local = Some(report));
        let _ = exchange.send(GROUP_RESULT, &report.bytes()).await;
        result.ok().and_then(Result::ok).unwrap_or(Sample {
            state: 2,
            ..pending
        })
    } else {
        match timeout(
            BUDGET,
            exchange.first_check(pc, controller, remote, &mut held),
        )
        .await
        {
            Ok(Ok(sample)) => sample,
            _ => Sample {
                state: 2,
                ..pending
            },
        }
    };
    status.send_modify(|s| s.timed_local = Some(sample));
    // Release ordinary ICE immediately after the timed write or bounded fallback.
    for candidate in held {
        if pc.add_remote_ice_candidate(&candidate).await.is_err() {
            hbb_common::log::trace!("timed attempt rejected a queued candidate");
        }
    }
    let _ = exchange.send(RESULT, &sample.bytes()).await;
    if !exact.is_empty() {
        tokio::time::sleep(Duration::from_millis(900)).await;
        let ingress = pc.grouped_pair_ingress(&exact).await;
        let report = status.borrow().group_local.map(|mut value| {
            value.ingress = ingress;
            value
        });
        if let Some(report) = report {
            status.send_modify(|s| s.group_local = Some(report));
            let _ = exchange.send(GROUP_RESULT, &report.bytes()).await;
            hbb_common::log::info!("RustDesk mapped pairs attempt {id}: {report}");
        }
    }
    if id <= 3 || id.is_power_of_two() {
        hbb_common::log::info!("RustDesk timed first pair attempt {id}: {sample}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::live_direct::decode;

    #[tokio::test]
    async fn both_roles_schedule_the_same_future_instant_on_offset_monotonic_clocks() {
        let (out_a, wire_a) = mpsc::channel(16);
        let (out_b, wire_b) = mpsc::channel(16);
        let (in_a, rx_a) = mpsc::channel(16);
        let (in_b, rx_b) = mpsc::channel(16);
        let forward = |mut wire: mpsc::Receiver<SetupEvent>, tx: mpsc::Sender<(u8, Vec<u8>)>| {
            tokio::spawn(async move {
                while let Some(SetupEvent::Send(b)) = wire.recv().await {
                    let (kind, _, bytes) = decode(&b).unwrap();
                    tokio::time::sleep(Duration::from_millis(12)).await;
                    if tx.send((kind, bytes.to_vec())).await.is_err() {
                        break;
                    }
                }
            })
        };
        let a_to_b = forward(wire_a, in_b);
        let b_to_a = forward(wire_b, in_a);
        let now = Instant::now();
        let mut a = Exchange {
            events: &out_a,
            incoming: rx_a,
            id: 1,
            origin: now - Duration::from_secs(3),
        };
        let mut b = Exchange {
            events: &out_b,
            incoming: rx_b,
            id: 1,
            origin: now,
        };
        let (a, b) = tokio::join!(a.deadline(true), b.deadline(false));
        let (a, ar) = a.unwrap();
        let (b, br) = b.unwrap();
        assert_eq!(ar, br);
        assert!(a > Instant::now() + Duration::from_millis(200));
        assert!(a.max(b) - a.min(b) < Duration::from_millis(35));
        a_to_b.abort();
        b_to_a.abort();
    }

    #[test]
    fn timed_result_frames_are_bounded_and_validated() {
        let s = Sample {
            state: 1,
            rtt_ms: 80,
            late_ms: 3,
        };
        assert_eq!(Sample::decode(&s.bytes()), Some(s));
        assert!(Sample::decode(&[5, 0, 0, 0, 0]).is_none());
        assert!(Sample::decode(&[1, 2]).is_none());
    }
}
