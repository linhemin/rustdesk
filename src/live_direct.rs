//! Keep one authenticated remote-control session while trying and replacing its direct path.
use hbb_common::{
    anyhow::Context,
    bail,
    bytes::{BufMut, Bytes, BytesMut},
    config::Config,
    futures_util::{sink::SinkExt, stream::StreamExt},
    log,
    sodiumoxide::{crypto::secretbox, randombytes},
    tcp::{FramedStream, KxTranscript},
    tokio::{
        self,
        io::{duplex, join},
        sync::{mpsc, oneshot, watch, Semaphore},
        time::{interval, timeout, Duration, Instant, MissedTickBehavior},
    },
    webrtc::WebRTCStream,
    ResultType, Stream,
};
use std::{collections::VecDeque, future::pending, net::IpAddr};

pub(crate) const CAPABILITY: &str = "rustdesk_live_direct_v1";
pub(crate) const TRICKLE_CAPABILITY: &str = "rustdesk_live_direct_trickle_v1";
pub(crate) const START: &[u8] = b"\x00RD-live-v1-start";
pub(crate) const ACCEPT: &[u8] = b"\x00RD-live-v1-accept";
// Protobuf cannot begin with a zero field tag. Keep control frames unambiguous even when
// startup messages are still draining from the authenticated relay.
const MAGIC: &[u8] = b"\x00RD-live-v1";
const DATA: u8 = 1;
const ACK: u8 = 2;
const OFFER: u8 = 3;
const ANSWER: u8 = 4;
const RESET: u8 = 5;
const DATA_MORE: u8 = 6;
// The base handshake and framing stay compatible with deployed complete-SDP peers.
// Only send this offer to a peer that advertised the additional capability.
const TRICKLE_OFFER: u8 = 7;
const ICE_CANDIDATE: u8 = 8;
const MAX_SDP: usize = 16 * 1024;
const MAX_CANDIDATE: usize = 2048;
const MAX_CANDIDATES: usize = 128;
const MAX_APP_MESSAGE: usize = hbb_common::bytes_codec::MAX_FRAME_LENGTH;
const FRAGMENT: usize = 16 * 1024;
const MAX_IN_FLIGHT: u64 = 24;
const MAX_PENDING_BYTES: usize = 8 * 1024 * 1024;
const MAX_PENDING_FRAMES: usize = 128;
const PATH_TIMEOUT: Duration = Duration::from_secs(3);
const RTC_TIMEOUT: u64 = 18_000;
static NEGOTIATIONS: Semaphore = Semaphore::const_new(8);
#[cfg(test)]
static DROP_TEST_PATH: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub(crate) fn enabled() -> bool {
    // Both platforms use the OS route (including VPN) for WebRTC. iOS only builds the
    // controller; Windows also advertises the responder capability after authorization.
    cfg!(any(target_os = "windows", target_os = "ios"))
        && crate::get_webrtc_enabled()
        && !Config::is_proxy()
        && Config::get_option("force-always-relay") != "Y"
}

pub(crate) async fn next_path(status: &mut Option<watch::Receiver<bool>>) -> Option<bool> {
    let Some(path) = status.as_mut() else {
        return pending().await;
    };
    path.changed().await.ok()?;
    let direct = *path.borrow_and_update();
    Some(direct)
}

pub(crate) fn supported_transport(stream: &Stream) -> bool {
    matches!(stream, Stream::Tcp(_)) && stream.is_secured()
}

#[derive(Clone, Copy)]
pub(crate) enum Role {
    Answerer,
    Offerer { trickle: bool },
}

pub(crate) fn wrap(stream: &mut Stream, role: Role) -> ResultType<watch::Receiver<bool>> {
    if !supported_transport(stream) {
        bail!("A live direct path requires an encrypted TCP session");
    }
    let addr = stream.local_addr();
    let (app_write, read_pipe) = duplex(1024 * 1024);
    let (app_read, write_pipe) = duplex(1024 * 1024);
    let mut app = FramedStream::from(join(app_read, app_write), addr);
    let mut read_pipe = FramedStream::from(read_pipe, addr);
    let mut write_pipe = FramedStream::from(write_pipe, addr);
    // Maintain Stream::is_secured() for the existing session code. These two keys only
    // protect the in-process pipe. The two network paths use their existing encryption.
    let seed = secretbox::gen_key();
    let transcript = KxTranscript {
        initiator_pk: &randombytes::randombytes(32),
        responder_pk: &randombytes::randombytes(32),
        advertised: 1,
        picked: 1,
    };
    app.set_key_split(seed.clone(), true, &transcript)?;
    read_pipe.set_key_split(seed.clone(), false, &transcript)?;
    write_pipe.set_key_split(seed, false, &transcript)?;
    app.set_send_timeout(8_000);
    write_pipe.set_send_timeout(8_000);
    let Stream::Tcp(tcp) = stream else {
        unreachable!()
    };
    let relay = std::mem::replace(tcp, app);
    let (path, status) = watch::channel(false);
    tokio::spawn(async move {
        if let Err(err) = run(read_pipe, write_pipe, Relay::new(relay), role, path).await {
            log::debug!("Live direct bridge closed: {err}");
        }
    });
    Ok(status)
}

fn frame(kind: u8, number: u64, payload: &[u8]) -> Bytes {
    let mut bytes = BytesMut::with_capacity(MAGIC.len() + 9 + payload.len());
    bytes.put_slice(MAGIC);
    bytes.put_u8(kind);
    bytes.put_u64(number);
    bytes.put_slice(payload);
    bytes.freeze()
}

fn decode(bytes: &[u8]) -> Option<(u8, u64, &[u8])> {
    let bytes = bytes.strip_prefix(MAGIC)?;
    let number = u64::from_be_bytes(bytes.get(1..9)?.try_into().ok()?);
    Some((bytes[0], number, &bytes[9..]))
}

struct Rtc(WebRTCStream);

impl Drop for Rtc {
    fn drop(&mut self) {
        self.0.close_detached();
    }
}

struct Direct {
    id: u64,
    rtc: Rtc,
    since: Instant,
    active: bool,
}

struct PendingFrame {
    number: u64,
    bytes: Bytes,
    sent: Instant,
}

#[derive(Default)]
struct Sequence {
    sent: u64,
    received: u64,
    acked: u64,
    pending: VecDeque<PendingFrame>,
    pending_bytes: usize,
    assembling: BytesMut,
}

impl Sequence {
    fn acknowledge(&mut self, ack: u64) {
        if ack <= self.acked || ack > self.sent {
            return;
        }
        self.acked = ack;
        while self.pending.front().map_or(false, |f| f.number <= ack) {
            if let Some(packet) = self.pending.pop_front() {
                self.pending_bytes -= packet.bytes.len();
            }
        }
    }

    fn track(&mut self, bytes: Bytes) {
        self.pending_bytes += bytes.len();
        self.pending.push_back(PendingFrame {
            number: self.sent,
            bytes,
            sent: Instant::now(),
        });
    }

    fn can_send_direct(&self, bytes: usize) -> bool {
        self.pending.len() < MAX_PENDING_FRAMES && bytes <= MAX_PENDING_BYTES - self.pending_bytes
    }
}

enum SetupEvent {
    Send(Bytes),
    Finished(u64, Option<Rtc>, &'static str),
}

struct SetupTask(tokio::task::JoinHandle<()>);

impl Drop for SetupTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

struct Relay {
    incoming: mpsc::Receiver<BytesMut>,
    outgoing: mpsc::Sender<Bytes>,
    _reader: SetupTask,
    _writer: SetupTask,
}

impl Relay {
    fn new(relay: FramedStream) -> Self {
        let FramedStream(io, _, encryption, timeout_ms) = relay;
        let (mut writer, mut reader) = io.split();
        let mut receive_key = encryption.expect("encrypted TCP session");
        let mut send_key = receive_key.clone();
        let (read, incoming) = mpsc::channel(64);
        let (outgoing, mut write) = mpsc::channel::<Bytes>(64);
        let reader = SetupTask(tokio::spawn(async move {
            while let Some(Ok(mut frame)) = reader.next().await {
                if receive_key.dec(&mut frame).is_err() || read.send(frame).await.is_err() {
                    break;
                }
            }
        }));
        let writer = SetupTask(tokio::spawn(async move {
            while let Some(frame) = write.recv().await {
                let encrypted = send_key.enc(&frame);
                let written = timeout(
                    Duration::from_millis(timeout_ms.max(5_000)),
                    writer.send(Bytes::from(encrypted)),
                )
                .await;
                if !matches!(written, Ok(Ok(()))) {
                    break;
                }
            }
        }));
        Self {
            incoming,
            outgoing,
            _reader: reader,
            _writer: writer,
        }
    }

    async fn send(&self, bytes: Bytes) -> ResultType<()> {
        self.outgoing
            .send(bytes)
            .await
            .map_err(|_| hbb_common::anyhow::anyhow!("The relay closed"))
    }
}

#[derive(Debug, Default)]
struct CandidateCounts {
    v4: usize,
    v6: usize,
    host: usize,
    srflx: usize,
    prflx: usize,
    relay: usize,
}

impl CandidateCounts {
    // An RFC 8445 candidate begins foundation component transport priority address port typ type.
    // Store only counts. In particular, do not log candidate strings, SDP, credentials or IPs.
    fn record(&mut self, bytes: &[u8]) {
        let Ok(value) = hbb_common::serde_json::from_slice::<hbb_common::serde_json::Value>(bytes)
        else {
            return;
        };
        let Some(line) = value.get("candidate").and_then(|v| v.as_str()) else {
            return;
        };
        let mut fields = line.split_ascii_whitespace().skip(4);
        let Some(address) = fields.next() else { return };
        match fields.nth(2) {
            Some("host") => self.host += 1,
            Some("srflx") => self.srflx += 1,
            Some("prflx") => self.prflx += 1,
            Some("relay") => self.relay += 1,
            _ => return,
        }
        match address.parse::<IpAddr>() {
            Ok(IpAddr::V4(_)) => self.v4 += 1,
            Ok(IpAddr::V6(_)) => self.v6 += 1,
            Err(_) => {} // mDNS host candidates do not reveal their address family.
        }
    }
}

struct Attempt {
    _task: SetupTask,
    answer: Option<oneshot::Sender<String>>,
    candidates: Option<mpsc::Sender<String>>,
    candidates_received: usize,
    local: CandidateCounts,
    remote: CandidateCounts,
}

impl Attempt {
    fn receive_candidate(&mut self, bytes: &[u8]) {
        if bytes.len() > MAX_CANDIDATE || self.candidates_received >= MAX_CANDIDATES {
            return;
        }
        if let (Some(tx), Ok(candidate)) = (self.candidates.as_ref(), std::str::from_utf8(bytes)) {
            if tx.try_send(candidate.to_owned()).is_ok() {
                self.candidates_received += 1;
                self.remote.record(bytes);
            }
        }
    }
}

fn make_attempt(
    events: &mpsc::Sender<SetupEvent>,
    id: u64,
    offer: Option<String>,
    trickle: bool,
) -> Attempt {
    let offerer = offer.is_none();
    let (answer, wait_for_answer) = oneshot::channel::<String>();
    let (candidates, mut remote_candidates) = mpsc::channel::<String>(MAX_CANDIDATES);
    let events = events.clone();
    let task = tokio::spawn(async move {
        let mut stage = "capacity";
        let outcome: ResultType<Rtc> = async {
            let _slot = NEGOTIATIONS.try_acquire()?;
            stage = "create peer connection";
            let mut rtc =
                Rtc(WebRTCStream::new(offer.as_deref().unwrap_or(""), false, RTC_TIMEOUT).await?);
            stage = "prepare local description";
            let sdp = if trickle {
                rtc.0.local_endpoint().to_owned()
            } else {
                rtc.0
                    .get_local_endpoint_within(Duration::from_secs(3))
                    .await?
            };
            if sdp.len() > MAX_SDP {
                bail!("The ICE description exceeded the live signaling limit");
            }
            let kind = match (offerer, trickle) {
                (true, true) => TRICKLE_OFFER,
                (true, false) => OFFER,
                (false, _) => ANSWER,
            };
            events
                .send(SetupEvent::Send(frame(kind, id, sdp.as_bytes())))
                .await
                .map_err(|_| hbb_common::anyhow::anyhow!("The session closed"))?;

            // Queue SDP first on the ordered authenticated relay. Local candidates can then
            // reach the answerer even while we are waiting for its SDP.
            let _send_ice = if trickle {
                let mut rx = rtc
                    .0
                    .take_local_ice_rx()
                    .context("ICE candidate receiver unavailable")?;
                let events = events.clone();
                Some(SetupTask(tokio::spawn(async move {
                    let mut sent = 0;
                    while let Some(candidate) = rx.recv().await {
                        if candidate.is_empty() || candidate.len() > MAX_CANDIDATE {
                            continue;
                        }
                        if events
                            .send(SetupEvent::Send(frame(
                                ICE_CANDIDATE,
                                id,
                                candidate.as_bytes(),
                            )))
                            .await
                            .is_err()
                        {
                            break;
                        }
                        sent += 1;
                        if sent >= MAX_CANDIDATES {
                            break;
                        }
                    }
                })))
            } else {
                None
            };
            if offerer {
                stage = "receive answer";
                let sdp = timeout(Duration::from_millis(RTC_TIMEOUT), wait_for_answer)
                    .await?
                    .context("The peer did not answer")?;
                stage = "set remote description";
                rtc.0.set_remote_endpoint(&sdp).await?;
            }
            // Remote candidates that arrived early remain queued until the peer's SDP is set.
            let _receive_ice = if trickle {
                let pc = rtc.0.clone();
                Some(SetupTask(tokio::spawn(async move {
                    while let Some(candidate) = remote_candidates.recv().await {
                        if pc.add_remote_ice_candidate(&candidate).await.is_err() {
                            log::trace!("Live direct attempt {id} rejected a remote ICE candidate");
                        }
                    }
                })))
            } else {
                None
            };
            stage = "ICE/DTLS/data-channel checks";
            rtc.0.wait_connected(RTC_TIMEOUT).await?;
            stage = "verify direct selected pair";
            if rtc.0.is_relayed().await != Some(false) {
                bail!("ICE did not select a direct candidate pair");
            }
            // The authenticated relay carried both DTLS fingerprints. DTLS has verified that
            // each received certificate matches the fingerprint we got on that session.
            rtc.0.set_key(secretbox::gen_key());
            rtc.0.set_send_timeout(1_500);
            stage = "direct channel ready";
            Ok(rtc)
        }
        .await;
        let _ = events
            .send(SetupEvent::Finished(id, outcome.ok(), stage))
            .await;
    });
    Attempt {
        _task: SetupTask(task),
        answer: offerer.then_some(answer),
        candidates: trickle.then_some(candidates),
        candidates_received: 0,
        local: CandidateCounts::default(),
        remote: CandidateCounts::default(),
    }
}

async fn relay_pending(
    relay: &Relay,
    direct: &mut Option<Direct>,
    seq: &mut Sequence,
    path: &watch::Sender<bool>,
    notify: bool,
) -> ResultType<()> {
    if let Some(direct) = direct.take() {
        path.send_replace(false);
        if notify {
            relay.send(frame(RESET, direct.id, &[])).await?;
        }
    }
    while let Some(packet) = seq.pending.pop_front() {
        relay.send(packet.bytes).await?;
    }
    seq.pending_bytes = 0;
    Ok(())
}

async fn receive_data(
    app: &mpsc::Sender<Bytes>,
    relay: &Relay,
    seq: &mut Sequence,
    number: u64,
    payload: &[u8],
    last: bool,
) -> ResultType<()> {
    if number == seq.received + 1 {
        if payload.len() > FRAGMENT || seq.assembling.len() + payload.len() > MAX_APP_MESSAGE {
            bail!("Live direct frame limit exceeded");
        }
        seq.assembling.put_slice(payload);
        seq.received = number;
        if last {
            app.send(seq.assembling.split().freeze())
                .await
                .map_err(|_| hbb_common::anyhow::anyhow!("The local session closed"))?;
        }
    }
    // A failed direct write may have been delivered after all. A replay is acknowledged without
    // dispatching desktop input or other application frames twice.
    relay.send(frame(ACK, seq.received, &[])).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::{TcpListener, TcpStream};

    #[test]
    fn candidate_diagnostics_report_only_type_and_family() {
        let mut counts = CandidateCounts::default();
        for line in [
            "candidate:a 1 udp 1 192.0.2.1 51234 typ host",
            "candidate:b 1 udp 1 2001:db8::2 51235 typ srflx raddr :: rport 0",
            "candidate:c 1 udp 1 mask.local 51236 typ host",
            "candidate:d 1 udp 1 192.0.2.8 12345 typ invalid",
        ] {
            counts.record(
                hbb_common::serde_json::json!({ "candidate": line })
                    .to_string()
                    .as_bytes(),
            );
        }
        counts.record(b"invalid json");
        assert_eq!(
            (counts.v4, counts.v6, counts.host, counts.srflx),
            (1, 1, 2, 1)
        );
    }

    async fn encrypted_pair() -> (Stream, Stream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (first, second) = tokio::join!(TcpStream::connect(addr), listener.accept());
        let (first, second) = (first.unwrap(), second.unwrap().0);
        first.set_nodelay(true).unwrap();
        second.set_nodelay(true).unwrap();
        let mut first = Stream::from(first, addr);
        let mut second = Stream::from(second, addr);
        let kx = KxTranscript {
            initiator_pk: &[1; 32],
            responder_pk: &[2; 32],
            advertised: 1,
            picked: 1,
        };
        let key = secretbox::gen_key();
        first.set_negotiated_key(key.clone(), true, &kx).unwrap();
        second.set_negotiated_key(key, false, &kx).unwrap();
        (first, second)
    }

    #[tokio::test]
    async fn relayed_session_keeps_legacy_and_large_bidirectional_frames() {
        let (mut first, mut second) = encrypted_pair().await;
        first
            .send_raw(b"before the upgrade".to_vec())
            .await
            .unwrap();
        let one = wrap(&mut first, Role::Answerer).unwrap();
        let two = wrap(&mut second, Role::Answerer).unwrap();
        assert!(first.is_secured() && second.is_secured());
        assert_eq!(
            second.next().await.unwrap().unwrap(),
            &b"before the upgrade"[..]
        );
        let left = async {
            first.send_raw(vec![1; 2 * 1024 * 1024]).await.unwrap();
            assert_eq!(
                first.next().await.unwrap().unwrap(),
                vec![2; 2 * 1024 * 1024]
            );
        };
        let right = async {
            second.send_raw(vec![2; 2 * 1024 * 1024]).await.unwrap();
            assert_eq!(
                second.next().await.unwrap().unwrap(),
                vec![1; 2 * 1024 * 1024]
            );
        };
        timeout(Duration::from_secs(5), async { tokio::join!(left, right) })
            .await
            .unwrap();
        assert!(!*one.borrow() && !*two.borrow());
    }

    #[tokio::test]
    async fn packet_replay_does_not_dispatch_input_twice() {
        let (mut sender, mut receiver) = encrypted_pair().await;
        let _path = wrap(&mut receiver, Role::Answerer).unwrap();
        for (kind, n, data) in [
            (DATA_MORE, 1, &b"action "[..]),
            (DATA_MORE, 1, &b"action "[..]),
            (DATA, 2, &b"one"[..]),
            (DATA, 2, &b"one"[..]),
            (DATA, 3, &b"action two"[..]),
        ] {
            sender
                .send_raw(frame(kind, n, data).to_vec())
                .await
                .unwrap();
        }
        assert_eq!(receiver.next().await.unwrap().unwrap(), &b"action one"[..]);
        assert_eq!(receiver.next().await.unwrap().unwrap(), &b"action two"[..]);
    }

    #[tokio::test]
    #[ignore = "requires two working local UDP/ICE peers"]
    async fn active_session_survives_relay_direct_relay_and_retry() {
        use std::sync::atomic::Ordering;

        async fn wait_for_path(path: &mut watch::Receiver<bool>, direct: bool) {
            timeout(Duration::from_secs(30), async {
                loop {
                    if *path.borrow_and_update() == direct {
                        break;
                    }
                    path.changed().await.unwrap();
                }
            })
            .await
            .expect("the session should change paths");
        }

        async fn exchange(from: &mut Stream, to: &mut Stream, value: &[u8]) {
            from.send_raw(value.to_vec()).await.unwrap();
            let got = timeout(Duration::from_secs(10), to.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            assert_eq!(got.as_ref(), value);
        }

        let (mut first, mut second) = encrypted_pair().await;
        let mut responder = wrap(&mut second, Role::Answerer).unwrap();
        let mut initiator = wrap(&mut first, Role::Offerer { trickle: true }).unwrap();
        exchange(&mut first, &mut second, b"before direct").await;
        tokio::join!(
            wait_for_path(&mut initiator, true),
            wait_for_path(&mut responder, true)
        );
        exchange(&mut first, &mut second, b"on direct").await;
        DROP_TEST_PATH.store(true, Ordering::Release);
        tokio::join!(
            wait_for_path(&mut initiator, false),
            wait_for_path(&mut responder, false)
        );
        exchange(&mut second, &mut first, b"after direct failed").await;
        tokio::join!(
            wait_for_path(&mut initiator, true),
            wait_for_path(&mut responder, true)
        );
        exchange(&mut first, &mut second, b"on direct again").await;
    }
}

async fn run(
    mut read_pipe: FramedStream,
    mut write_pipe: FramedStream,
    mut relay: Relay,
    role: Role,
    path: watch::Sender<bool>,
) -> ResultType<()> {
    // App TX and RX can both exceed the pipe buffer (e.g. video and a clipboard image).
    // Pump them independently so an inbound delivery never blocks draining the app's writes.
    let (to_app, mut write_queue) = mpsc::channel::<Bytes>(1);
    let (read_queue, mut from_app) = mpsc::channel(1);
    let _write_task = SetupTask(tokio::spawn(async move {
        while let Some(bytes) = write_queue.recv().await {
            if write_pipe.send_raw(bytes.to_vec()).await.is_err() {
                break;
            }
        }
    }));
    let _read_task = SetupTask(tokio::spawn(async move {
        while let Some(Ok(bytes)) = read_pipe.next().await {
            if read_queue.send(bytes).await.is_err() {
                break;
            }
        }
    }));
    let (event_tx, mut events) = mpsc::channel(8);
    let mut setup: Option<Attempt> = None;
    let mut attempt = 0;
    let offerer = matches!(role, Role::Offerer { .. });
    let mut retry_delay = 2;
    let mut next_attempt = Instant::now() + Duration::from_secs(1);
    let mut direct: Option<Direct> = None;
    let mut seq = Sequence::default();
    let mut message: Option<BytesMut> = None;
    let mut tick = interval(Duration::from_millis(500));
    tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    loop {
        // A direct frame must never overtake a relay frame at the switch.
        let switching = direct.as_ref().map_or(false, |d| !d.active);
        tokio::select! {
            from_relay = relay.incoming.recv() => {
                let Some(packet) = from_relay else { break };
                match decode(&packet) {
                    Some((kind @ (DATA | DATA_MORE), number, payload)) => {
                        receive_data(&to_app, &relay, &mut seq, number, payload, kind == DATA).await?;
                    }
                    Some((ACK, number, [])) => seq.acknowledge(number),
                    Some((kind @ (OFFER | TRICKLE_OFFER), number, data))
                        if !offerer && direct.is_none() && number > attempt
                            && data.len() <= MAX_SDP && Instant::now() >= next_attempt =>
                    {
                        if let Ok(sdp) = std::str::from_utf8(data) {
                            attempt = number;
                            next_attempt = Instant::now() + Duration::from_secs(3);
                            setup = Some(make_attempt(&event_tx, number, Some(sdp.to_owned()), kind == TRICKLE_OFFER));
                        }
                    }
                    Some((ANSWER, number, data))
                        if offerer && number == attempt && data.len() <= MAX_SDP =>
                    {
                        if let (Some(setup), Ok(sdp)) = (setup.as_mut(), std::str::from_utf8(data)) {
                            if let Some(answer) = setup.answer.take() {
                                let _ = answer.send(sdp.to_owned());
                            }
                        }
                    }
                    Some((ICE_CANDIDATE, number, data)) if number == attempt => {
                        if let Some(setup) = setup.as_mut() {
                            setup.receive_candidate(data);
                        }
                    }
                    Some((RESET, number, [])) if number == attempt => {
                        setup = None;
                        relay_pending(&relay, &mut direct, &mut seq, &path, false).await?;
                    }
                    Some(_) => {}
                    None if !packet.starts_with(MAGIC) && seq.received == 0 => {
                        // Messages written before the peer wrapped its side of the session.
                        to_app.send(packet.freeze()).await
                            .map_err(|_| hbb_common::anyhow::anyhow!("The local session closed"))?;
                    }
                    None => {}
                }
            }
            from_direct = async {
                match direct.as_mut() {
                    Some(direct) => direct.rtc.0.next().await,
                    None => pending().await,
                }
            } => {
                if let Some(Ok(packet)) = from_direct {
                    if let Some((kind @ (DATA | DATA_MORE), number, payload)) = decode(&packet) {
                        receive_data(&to_app, &relay, &mut seq, number, payload, kind == DATA).await?;
                    }
                } else {
                    relay_pending(&relay, &mut direct, &mut seq, &path, true).await?;
                }
            }
            payload = from_app.recv(), if message.is_none() => {
                let Some(payload) = payload else { break };
                message = Some(payload);
            }
            _ = std::future::ready(()),
                if !switching && message.is_some() && seq.sent - seq.acked < MAX_IN_FLIGHT =>
            {
                let payload = message.as_mut().expect("pending application message");
                let length = payload.len().min(FRAGMENT);
                let last = length == payload.len();
                seq.sent += 1;
                let bytes = frame(if last { DATA } else { DATA_MORE }, seq.sent, &payload.split_to(length));
                if last {
                    message = None;
                }
                if !seq.can_send_direct(bytes.len()) {
                    relay_pending(&relay, &mut direct, &mut seq, &path, true).await?;
                }
                if let Some(route) = direct.as_mut() {
                    seq.track(bytes.clone());
                    if route.rtc.0.send_raw(bytes.to_vec()).await.is_err() {
                        relay_pending(&relay, &mut direct, &mut seq, &path, true).await?;
                    }
                } else {
                    relay.send(bytes).await?;
                }
            }
            Some(event) = events.recv() => match event {
                SetupEvent::Send(bytes) => {
                    if let Some((kind, id, data)) = decode(&bytes) {
                        if id != attempt || setup.is_none() {
                            continue;
                        }
                        if kind == ICE_CANDIDATE {
                            if let Some(current) = setup.as_mut() {
                                current.local.record(data);
                            }
                        }
                        relay.send(bytes).await?;
                    }
                }
                SetupEvent::Finished(id, rtc, stage) if id == attempt && setup.is_some() => {
                    let current = setup.take().unwrap();
                    if id <= 3 || id.is_power_of_two() || rtc.is_some() {
                        let side = if offerer { "controller" } else { "controlled" };
                        if current.candidates.is_some() {
                            log::info!("Live direct {side} attempt {id} (trickle): {stage}; local {:?}, remote {:?}", current.local, current.remote);
                        } else {
                            log::info!("Live direct {side} attempt {id} (complete SDP): {stage}");
                        }
                    }
                    if let Some(rtc) = rtc {
                        direct = Some(Direct { id, rtc, since: Instant::now(), active: false });
                    } else if offerer {
                        next_attempt = Instant::now() + Duration::from_secs(retry_delay);
                        retry_delay = (retry_delay * 2).min(30);
                    }
                }
                SetupEvent::Finished(_, _, _) => {}
            },
            _ = tick.tick() => {
                #[cfg(test)]
                if direct.is_some() && DROP_TEST_PATH.swap(false, std::sync::atomic::Ordering::AcqRel) {
                    relay_pending(&relay, &mut direct, &mut seq, &path, true).await?;
                }
                if direct.as_ref().map_or(false, |d| {
                    !d.active && d.since.elapsed() >= PATH_TIMEOUT || d.rtc.0.is_disconnected()
                }) || seq.pending.front().map_or(false, |p| p.sent.elapsed() >= PATH_TIMEOUT) {
                    relay_pending(&relay, &mut direct, &mut seq, &path, true).await?;
                }
                if let Role::Offerer { trickle } = role {
                    if direct.is_none() && Instant::now() >= next_attempt && setup.is_none() {
                        attempt += 1;
                        setup = Some(make_attempt(&event_tx, attempt, None, trickle));
                    }
                }
            }
        }
        if let Some(direct) = direct.as_mut() {
            if !direct.active && seq.acked == seq.sent {
                direct.active = true;
                path.send_replace(true);
                retry_delay = 2;
                log::info!("Active RustDesk session switched to direct WebRTC");
            }
        }
    }
    Ok(())
}
