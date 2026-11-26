use super::{frame, Relay};
use hbb_common::{
    bytes::Bytes,
    tokio::time::{Duration, Instant},
};

pub(crate) const CAPABILITY: &str = "rustdesk_live_path_quality_v1";
pub(crate) const START: &[u8] = b"\0RD-live-quality-v1-start";
pub(super) const PING: u8 = 36;
pub(super) const PONG: u8 = 37;
pub(super) const PAYLOAD: [u8; 1024] = [0; 1024];
pub(super) const COUNT: usize = 3;
const PROBE_INTERVAL: Duration = Duration::from_secs(3);
const SAMPLE_LIFETIME: Duration = Duration::from_secs(18);

#[derive(Default)]
pub(super) struct Samples {
    values: [Option<(Duration, Instant)>; COUNT],
    next: usize,
}

impl Samples {
    pub(super) fn record(&mut self, rtt: Duration, now: Instant) {
        self.values[self.next] = Some((rtt, now));
        self.next = (self.next + 1) % COUNT;
    }

    pub(super) fn score(&self, now: Instant) -> Option<Duration> {
        let mut rtts = [Duration::ZERO; COUNT];
        for (rtt, sample) in rtts.iter_mut().zip(self.values) {
            let (value, at) = sample?;
            if now.duration_since(at) > SAMPLE_LIFETIME {
                return None;
            }
            *rtt = value;
        }
        rtts.sort_unstable();
        // Include queuing variation, without letting a single outlier decide the route.
        Some(rtts[1] + (rtts[2] - rtts[1]) / 4)
    }
}

pub(super) fn faster(candidate: Duration, incumbent: Duration) -> bool {
    incumbent.saturating_sub(candidate) >= (incumbent / 10).max(Duration::from_millis(1))
}

struct Round {
    number: u64,
    started: Instant,
    direct_id: Option<u64>,
    relay_rtt: Option<Duration>,
    direct_rtt: Option<Duration>,
}

#[derive(Default)]
pub(super) struct Monitor {
    pub(super) relay: Samples,
    round: Option<Round>,
    next: Option<Instant>,
    number: u64,
    losses: u8,
    previous_direct: Option<u64>,
    write: Option<(u64, Bytes)>,
}

impl Monitor {
    pub(super) fn tick(&mut self, relay: &Relay, active: Option<u64>, now: Instant) -> bool {
        if active != self.previous_direct {
            self.previous_direct = active;
            self.losses = 0;
            self.write = None;
        }
        if let Some(round) = &self.round {
            let elapsed = now.duration_since(round.started);
            let complete = round.relay_rtt.is_some()
                && (round.direct_id.is_none() || round.direct_rtt.is_some());
            if !complete && elapsed < PROBE_INTERVAL {
                return false;
            }
            if active.is_some() && active == round.direct_id {
                // A timed-out direct echo is a lower bound. Count it only if a relay
                // echo really arrived in the same round and beat even that bound.
                let worse = round
                    .relay_rtt
                    .is_some_and(|rtt| faster(rtt, round.direct_rtt.unwrap_or(elapsed)));
                self.losses = if worse { self.losses + 1 } else { 0 };
            }
            self.round = None;
            if self.losses >= 3 {
                self.losses = 0;
                return true;
            }
        }
        if self.next.is_some_and(|at| now < at) {
            return false;
        }
        self.number = self.number.wrapping_add(1);
        let ping = frame(PING, self.number, &PAYLOAD);
        if relay.outgoing.try_send(ping.clone()).is_ok() {
            self.write = active.map(|id| (id, ping));
            self.round = Some(Round {
                number: self.number,
                started: now,
                direct_id: active,
                relay_rtt: None,
                direct_rtt: None,
            });
        }
        self.next = Some(
            now + if self.relay.score(now).is_some() {
                PROBE_INTERVAL
            } else {
                Duration::from_millis(500)
            },
        );
        false
    }

    pub(super) fn received(
        &mut self,
        relay: &Relay,
        lane: Option<u64>,
        caller: bool,
        kind: u8,
        number: u64,
        payload: &[u8],
    ) {
        if payload != PAYLOAD {
            return;
        }
        if kind == PING && !caller {
            let reply = frame(PONG, number, payload);
            if let Some(id) = lane {
                // At most one echo can wait behind the current application write.
                self.write = Some((id, reply));
            } else {
                let _ = relay.outgoing.try_send(reply);
            }
        } else if kind == PONG && caller {
            let Some(round) = self.round.as_mut().filter(|r| r.number == number) else {
                return;
            };
            let now = Instant::now();
            let elapsed = now.duration_since(round.started);
            if lane.is_none() && round.relay_rtt.is_none() {
                round.relay_rtt = Some(elapsed);
                self.relay.record(elapsed, now);
            } else if lane.is_some() && lane == round.direct_id {
                round.direct_rtt.get_or_insert(elapsed);
            }
        }
    }

    pub(super) fn take_write(&mut self, id: u64) -> Option<Bytes> {
        self.write
            .take()
            .filter(|(route, _)| *route == id)
            .map(|(_, packet)| packet)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::live_direct::{native, parallel, wrap_parallel, wrap_with, Role};
    use hbb_common::{
        futures_util::FutureExt,
        sodiumoxide::crypto::secretbox,
        tcp::FramedStream,
        tokio::{
            self,
            io::{self, AsyncReadExt, AsyncWriteExt},
            time::timeout,
        },
        Stream,
    };
    use std::sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    };

    fn delayed_pair(delay: Arc<AtomicU64>) -> (Stream, Stream) {
        let (a, near) = io::duplex(65536);
        let (far, b) = io::duplex(65536);
        let ((mut near_rx, mut near_tx), (mut far_rx, mut far_tx)) =
            (io::split(near), io::split(far));
        tokio::spawn(async move {
            let _ = io::copy(&mut far_rx, &mut near_tx).await;
            let _ = near_tx.shutdown().await;
        });
        tokio::spawn(async move {
            let mut buf = [0u8; 8192];
            while let Ok(n @ 1..) = near_rx.read(&mut buf).await {
                tokio::time::sleep(Duration::from_millis(delay.load(Ordering::Relaxed))).await;
                if far_tx.write_all(&buf[..n]).await.is_err() {
                    break;
                }
            }
            let _ = far_tx.shutdown().await;
        });
        let addr = "127.0.0.1:1111".parse().unwrap();
        let (mut a, mut b) = (
            Stream::Tcp(FramedStream::from(a, addr)),
            Stream::Tcp(FramedStream::from(b, addr)),
        );
        let key = secretbox::gen_key();
        a.set_key(key.clone());
        b.set_key(key);
        (a, b)
    }

    #[tokio::test(start_paused = true)]
    async fn session_uses_the_faster_route_and_returns_when_direct_deteriorates() {
        let relay_delay = Arc::new(AtomicU64::new(40));
        let direct_delay = Arc::new(AtomicU64::new(140));
        let (mut controller, mut controlled) = delayed_pair(relay_delay.clone());
        let listener = native::Listener::with_capacity(2);
        let ticket = listener.response_with(parallel::ACCEPT)[parallel::ACCEPT.len()..]
            .try_into()
            .unwrap();
        let mut host = wrap_with(
            &mut controlled,
            Role::Answerer,
            Some(native::Mode::Listen(listener)),
            Some(parallel::Race::default().measured(true)),
        )
        .unwrap();
        let delay = direct_delay.clone();
        let relay_on_retry = relay_delay.clone();
        let (started_retry, mut retry) = tokio::sync::watch::channel(false);
        let attempts = AtomicU64::new(0);
        let tcp: native::Dial = Box::new(move || {
            if attempts.fetch_add(1, Ordering::Relaxed) == 1 {
                relay_on_retry.store(6500, Ordering::Relaxed);
                started_retry.send_replace(true);
            }
            let (caller, peer) = delayed_pair(delay.clone());
            async move {
                tokio::spawn(async move {
                    native::accept(peer).await.unwrap().await.ok();
                });
                Ok((caller, None, "TCP"))
            }
            .boxed()
        });
        let mut path = wrap_parallel(
            &mut controller,
            Role::Answerer,
            ticket,
            [Some(tcp), None],
            true,
        )
        .unwrap();
        assert!(timeout(Duration::from_secs(8), path.changed())
            .await
            .is_err());
        controller
            .send_raw(b"input over relay".to_vec())
            .await
            .unwrap();
        assert_eq!(
            &controlled.next_timeout(1000).await.unwrap().unwrap()[..],
            b"input over relay"
        );

        direct_delay.store(5, Ordering::Relaxed);
        timeout(Duration::from_secs(20), retry.wait_for(|started| *started))
            .await
            .unwrap()
            .unwrap();
        timeout(Duration::from_secs(5), async {
            path.changed().await.unwrap();
            host.changed().await.unwrap();
        })
        .await
        .unwrap();
        assert_eq!(
            (*path.borrow_and_update(), *host.borrow_and_update()),
            (Some("TCP"), Some("TCP"))
        );
        controlled
            .send_raw(b"video over direct".to_vec())
            .await
            .unwrap();
        assert_eq!(
            &controller.next_timeout(1000).await.unwrap().unwrap()[..],
            b"video over direct"
        );
        tokio::time::sleep(Duration::from_secs(4)).await;
        assert!(!path.has_changed().unwrap() && !host.has_changed().unwrap());
        relay_delay.store(40, Ordering::Relaxed);

        direct_delay.store(180, Ordering::Relaxed);
        tokio::time::sleep(Duration::from_secs(4)).await;
        assert!(!path.has_changed().unwrap() && !host.has_changed().unwrap());
        direct_delay.store(5, Ordering::Relaxed);
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert!(!path.has_changed().unwrap() && !host.has_changed().unwrap());

        direct_delay.store(180, Ordering::Relaxed);
        timeout(Duration::from_secs(16), async {
            path.changed().await.unwrap();
            host.changed().await.unwrap();
        })
        .await
        .unwrap();
        assert_eq!((*path.borrow(), *host.borrow()), (None, None));
        controller
            .send_raw(b"input after fallback".to_vec())
            .await
            .unwrap();
        assert_eq!(
            &controlled.next_timeout(1000).await.unwrap().unwrap()[..],
            b"input after fallback"
        );
    }

    #[test]
    fn promotion_requires_a_fresh_measurable_gain() {
        let now = Instant::now();
        let mut relay = Samples::default();
        for ms in [90, 98] {
            relay.record(Duration::from_millis(ms), now);
        }
        assert!(relay.score(now).is_none());
        relay.record(Duration::from_millis(106), now);
        let incumbent = relay.score(now).unwrap();
        assert_eq!(incumbent, Duration::from_millis(100));
        assert!(!faster(Duration::from_millis(95), incumbent));
        assert!(faster(Duration::from_millis(80), incumbent));
        assert!(faster(Duration::from_millis(1), Duration::from_millis(4)));
        assert!(!faster(Duration::from_micros(600), Duration::from_micros(850)));
        assert!(relay
            .score(now + SAMPLE_LIFETIME + Duration::from_secs(1))
            .is_none());
    }

    #[tokio::test]
    async fn rtc_only_session_compares_the_data_channel_with_its_relay() {
        use hbb_common::config::{keys::OPTION_ICE_SERVERS, OVERWRITE_SETTINGS};
        // Both real ICE agents are in this test process. Host candidates suffice;
        // prevent default STUN lookups without writing the user's settings.
        let previous = OVERWRITE_SETTINGS
            .write()
            .unwrap()
            .insert(OPTION_ICE_SERVERS.to_owned(), "stun:127.0.0.1:9".to_owned());
        let (mut controller, mut controlled) = delayed_pair(Arc::new(AtomicU64::new(60)));
        let mut host = wrap_with(
            &mut controlled,
            Role::Answerer,
            None,
            Some(parallel::Race::default().measured(true)),
        )
        .unwrap();
        let mut path = wrap_parallel(
            &mut controller,
            Role::Offerer { trickle: true },
            [1; 32],
            [None, None],
            true,
        )
        .unwrap();
        let connected = timeout(Duration::from_secs(30), async {
            path.changed().await.unwrap();
            host.changed().await.unwrap();
        })
        .await;
        {
            let mut settings = OVERWRITE_SETTINGS.write().unwrap();
            if let Some(value) = previous {
                settings.insert(OPTION_ICE_SERVERS.to_owned(), value);
            } else {
                settings.remove(OPTION_ICE_SERVERS);
            }
        }
        connected.unwrap();
        assert_eq!(
            (*path.borrow(), *host.borrow()),
            (Some("WebRTC"), Some("WebRTC"))
        );
        controlled
            .send_raw(b"direct desktop".to_vec())
            .await
            .unwrap();
        assert_eq!(
            &controller.next_timeout(1000).await.unwrap().unwrap()[..],
            b"direct desktop"
        );
    }
}
