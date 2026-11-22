//! Keep one authenticated remote-control session while trying and replacing its direct path.
use hbb_common::{
    anyhow::Context,
    bail,
    bytes::{BufMut, Bytes, BytesMut},
    config::Config,
    futures_util::{future::BoxFuture, sink::SinkExt, stream::StreamExt, FutureExt},
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
pub(crate) mod native;
pub(crate) const TRICKLE_CAPABILITY: &str = "rustdesk_live_direct_trickle_v1";
pub(crate) const PUNCH_CAPABILITY: &str = "rustdesk_live_direct_punch_v1";
pub(crate) const FULL_CAPABILITY: &str = "rustdesk_lite_full_punch_v2";
pub(crate) const GROUP_CAPABILITY: &str = "rustdesk_mapped_pair_groups_v1";
pub(crate) const TIMED_CAPABILITY: &str = "rustdesk_timed_first_pair_v1";
#[path = "live_direct/timed.rs"]
mod timed;
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
// A controller sends this offer only after reading PUNCH_CAPABILITY in the peer's
// authenticated PeerInfo. The offer opts both endpoints into coordinated trickle.
const PUNCH_OFFER: u8 = 9;
const PUNCH_READY: u8 = 10;
const PUNCH_GO: u8 = 11;
const PUNCH_DONE: u8 = 12;
// Optional counters requested by the controller. Build 78 ignores unknown control kinds.
const PUNCH_IO_REQUEST: u8 = 13;
const PUNCH_IO: u8 = 14;
const TIMED_OFFER: u8 = 15;
const GROUP_OFFER: u8 = 22;
const LITE_OFFER: u8 = 27;
const FULL_OFFER: u8 = 28;
const IO_SAMPLE_INTERVAL: Duration = Duration::from_secs(2);
const PUNCH_DELAYS_MS: [u64; 3] = [0, 180, 320];
// The agent waits up to 680 ms for trickled sockets, then up to 3 s for observers.
// Keep its partial results while bounding the independent READY task.
const PUNCH_MEASUREMENT_BUDGET: Duration = Duration::from_secs(4);
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
const LITE_TIMEOUT: u64 = 12_000;
const LITE_IDLE_WINDOW: Duration = Duration::from_secs(5);
const CHECK_STAGE: &str = "ICE/DTLS/data-channel checks";
const EMPTY_POOL_STAGE: &str = "full UDP port pool exhausted";
const TCP53_STAGE: &str = "configured TCP 53 gate refused full punching";
static NEGOTIATIONS: Semaphore = Semaphore::const_new(8);
static FULL_PORT_POOLS: Semaphore = Semaphore::const_new(2);
#[cfg(test)]
static DROP_TEST_PATH: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub(crate) fn enabled() -> bool {
    crate::get_webrtc_enabled()
        && !Config::is_proxy()
        && Config::get_option("force-always-relay") != "Y"
}

pub(crate) fn responder_enabled() -> bool {
    cfg!(any(target_os = "windows", target_os = "ios")) && enabled()
}

type Path = Option<&'static str>;

pub(crate) async fn next_path(status: &mut Option<watch::Receiver<Path>>) -> Option<Path> {
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
    CoordinatedOfferer,
    TimedOfferer,
    GroupOfferer,
    FullOfferer,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum OfferMode {
    Complete,
    Trickle,
    Coordinated,
    Timed,
    Grouped,
    Lite,
    Full,
}

impl OfferMode {
    fn timed(self) -> bool {
        matches!(self, Self::Timed | Self::Grouped | Self::Lite | Self::Full)
    }

    fn grouped(self) -> bool {
        matches!(self, Self::Grouped | Self::Lite)
    }

    fn for_attempt(self, id: u64) -> Self {
        if self.timed() && id % 2 == 1 { return Self::Coordinated; }
        if self == Self::Grouped && id % 4 == 0 { return Self::Timed; }
        self
    }

    fn frame_kind(self) -> u8 {
        match self {
            Self::Complete => OFFER,
            Self::Trickle => TRICKLE_OFFER,
            Self::Coordinated => PUNCH_OFFER,
            Self::Timed => TIMED_OFFER,
            Self::Grouped => GROUP_OFFER,
            Self::Lite => LITE_OFFER,
            Self::Full => FULL_OFFER,
        }
    }
}

struct RetrySchedule {
    next_profile: Option<OfferMode>,
    delay_seconds: u64,
}

impl Default for RetrySchedule {
    fn default() -> Self {
        Self {
            next_profile: None,
            delay_seconds: 2,
        }
    }
}

impl RetrySchedule {
    fn next(&mut self, preferred: OfferMode, id: u64) -> OfferMode {
        if preferred != OfferMode::Full {
            return preferred.for_attempt(id);
        }
        match self.next_profile.take() {
            Some(OfferMode::Full) => OfferMode::Full,
            // Keep both the older coordinated gateway check and the timed single
            // pair available after an unsuccessful full generation.
            Some(OfferMode::Timed) => OfferMode::Timed.for_attempt(id),
            _ => OfferMode::Lite,
        }
    }

    fn failed(&mut self, mode: OfferMode, stage: &str) -> Duration {
        if mode == OfferMode::Lite && stage == CHECK_STAGE {
            self.next_profile = Some(OfferMode::Full);
            return Duration::from_millis(250);
        }
        let skip_legacy = matches!(stage, EMPTY_POOL_STAGE | TCP53_STAGE);
        self.next_profile = (mode == OfferMode::Full && !skip_legacy).then_some(OfferMode::Timed);
        let delay = self.delay_seconds;
        self.delay_seconds = (delay * 2).min(30);
        // Answerers rate-limit replacement offers for three seconds after accepting one.
        Duration::from_secs(if skip_legacy { delay.max(3) } else { delay })
    }
}

impl Role {
    pub(crate) fn offerer(trickle: bool, punch: bool, timed: bool, groups: bool, full: bool) -> Self {
        match (trickle, punch, timed, groups, full) {
            (true, true, true, true, true) => Self::FullOfferer,
            (true, true, true, true, _) => Self::GroupOfferer,
            (true, true, true, _, _) => Self::TimedOfferer,
            (true, true, _, _, _) => Self::CoordinatedOfferer,
            _ => Self::Offerer { trickle },
        }
    }

    fn offer_mode(self) -> Option<OfferMode> {
        match self {
            Self::Answerer => None,
            Self::Offerer { trickle: false } => Some(OfferMode::Complete),
            Self::Offerer { trickle: true } => Some(OfferMode::Trickle),
            Self::CoordinatedOfferer => Some(OfferMode::Coordinated),
            Self::TimedOfferer => Some(OfferMode::Timed),
            Self::GroupOfferer => Some(OfferMode::Grouped),
            Self::FullOfferer => Some(OfferMode::Full),
        }
    }
}

pub(crate) fn wrap(stream: &mut Stream, role: Role) -> ResultType<watch::Receiver<Path>> {
    wrap_with(stream, role, None)
}

pub(crate) fn wrap_native(stream: &mut Stream, mode: native::Mode) -> ResultType<watch::Receiver<Path>> {
    wrap_with(stream, Role::Answerer, Some(mode))
}

fn wrap_with(stream: &mut Stream, role: Role, native: Option<native::Mode>) -> ResultType<watch::Receiver<Path>> {
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
    let (path, status) = watch::channel(None);
    tokio::spawn(async move {
        if let Err(err) = run(read_pipe, write_pipe, Relay::new(relay), role, path, native).await {
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

fn candidate_frame(id: u64, json: &str) -> Option<Bytes> {
    if json.is_empty() || json.len() > MAX_CANDIDATE {
        return None;
    }
    Some(frame(ICE_CANDIDATE, id, json.as_bytes()))
}

struct Rtc(WebRTCStream);

impl Drop for Rtc {
    fn drop(&mut self) {
        self.0.close_detached();
    }
}

struct Direct {
    id: u64,
    lane: Lane,
    since: Instant,
    active: bool,
    ice_silent_since: Option<Instant>,
    last_rx_progress: u64,
    first_sent: Option<Instant>,
    first_received: Option<Instant>,
    reported: bool,
}

enum Lane {
    WebRtc(Rtc),
    Native(native::Lane),
}

impl Lane {
    fn label(&self) -> &'static str {
        match self { Self::WebRtc(_) => "WebRTC", Self::Native(n) => n.label }
    }

    async fn next(&mut self) -> Option<std::io::Result<BytesMut>> {
        match self {
            Self::WebRtc(rtc) => rtc.0.next().await,
            Self::Native(n) => n.io.incoming.recv().await.map(Ok),
        }
    }

    fn write(&self, bytes: Bytes, last: bool) -> BoxFuture<'static, (bool, ResultType<()>)> {
        match self {
            Self::WebRtc(rtc) => {
                let mut stream = rtc.0.clone();
                async move { (last, stream.send_bytes(bytes).await) }.boxed()
            }
            Self::Native(n) => {
                let sender = n.io.outgoing.clone();
                async move { (last, sender.send(bytes).await.map_err(|_| hbb_common::anyhow::anyhow!("Native path closed"))) }.boxed()
            }
        }
    }
}

impl Direct {
    fn new(id: u64, lane: Lane) -> Self {
        let last_rx_progress = match &lane { Lane::WebRtc(rtc) => rtc.0.rx_progress(), Lane::Native(_) => 0 };
        Self { id, lane, since: Instant::now(), active: false, ice_silent_since: None,
            last_rx_progress, first_sent: None, first_received: None, reported: false }
    }
}

fn ice_stalled(
    since: &mut Option<Instant>,
    now: Instant,
    disconnected: bool,
    progressed: bool,
) -> bool {
    if !disconnected || progressed {
        *since = None;
        return false;
    }
    now.duration_since(*since.get_or_insert(now)) >= PATH_TIMEOUT
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
    Native(u64, Option<native::Lane>),
    Send(Bytes),
    StartPunch(u64),
    Finished(u64, Option<Rtc>, &'static str),
}

// Some NATs assign a different port if the peer reaches the advertised tuple
// before our first outbound check. Buffer only public IPv4 UDP advertisements
// on alternating coordinated retries. This task never handles application data.
async fn advertise_after_check(
    pc: WebRTCStream,
    mut input: mpsc::Receiver<SetupEvent>,
    output: mpsc::Sender<SetupEvent>,
    id: u64,
) {
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut waiting = Vec::new();
    let mut check = interval(Duration::from_millis(80));
    check.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut released = 0;
    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(deadline) => break,
            _ = check.tick(), if !waiting.is_empty() => {
                let checked = pc.checked_public_udp_endpoints().await;
                let pending = std::mem::take(&mut waiting);
                for (address, event) in pending {
                    if checked.contains(&address) {
                        if output.send(event).await.is_err() { return; }
                        released += 1;
                    } else {
                        waiting.push((address, event));
                    }
                }
            }
            next = input.recv() => {
                let Some(event) = next else { break };
                let address = match &event {
                    SetupEvent::Send(bytes) => decode(bytes).and_then(|(kind, _, data)| {
                        if kind == ICE_CANDIDATE {
                            WebRTCStream::public_udp_candidate_endpoint(data)
                        } else { None }
                    }),
                    _ => None,
                };
                if let Some(address) = address {
                    // All candidate producers are bounded by the attempt protocol.
                    waiting.push((address, event));
                } else if output.send(event).await.is_err() {
                    return;
                }
            }
        }
    }
    if id <= 3 || id.is_power_of_two() {
        log::info!("Windows outbound-first ICE attempt {id}: checked before advertising {released}, released at deadline {}", waiting.len());
    }
    for (_, event) in waiting {
        if output.send(event).await.is_err() { return; }
    }
    while let Some(event) = input.recv().await {
        if output.send(event).await.is_err() { return; }
    }
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
    v4_host: usize,
    v4_srflx_v4_base: usize,
    v4_srflx_v6_base: usize,
    v4_srflx_unknown_base: usize,
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
        let fields: Vec<_> = line.split_ascii_whitespace().collect();
        let [foundation, component, transport, priority, address, port, "typ", kind, extensions @ ..] =
            fields.as_slice()
        else {
            return;
        };
        if !foundation
            .strip_prefix("candidate:")
            .is_some_and(|f| !f.is_empty())
            || !component
                .parse::<u16>()
                .is_ok_and(|v| (1..=256).contains(&v))
            || !(transport.eq_ignore_ascii_case("udp") || transport.eq_ignore_ascii_case("tcp"))
            || priority.parse::<u32>().is_err()
            || !port.parse::<u16>().is_ok_and(|v| v > 0)
            || extensions.len() % 2 != 0
        {
            return;
        }
        let mut related = None;
        for pair in extensions.chunks_exact(2) {
            if pair[0] == "raddr" && related.replace(pair[1]).is_some() {
                return;
            }
        }
        match *kind {
            "host" => self.host += 1,
            "srflx" => self.srflx += 1,
            "prflx" => self.prflx += 1,
            "relay" => self.relay += 1,
            _ => return,
        }
        match address.parse::<IpAddr>() {
            Ok(ip @ IpAddr::V4(_)) => {
                self.v4 += 1;
                if Self::usable_unicast(ip).is_none() {
                    return;
                }
                match *kind {
                    "host" => self.v4_host += 1,
                    "srflx" => match related
                        .and_then(|base| base.parse().ok())
                        .and_then(Self::usable_unicast)
                    {
                        Some(IpAddr::V4(_)) => self.v4_srflx_v4_base += 1,
                        Some(IpAddr::V6(_)) => self.v4_srflx_v6_base += 1,
                        None => self.v4_srflx_unknown_base += 1,
                    },
                    _ => {}
                }
            }
            Ok(IpAddr::V6(_)) => self.v6 += 1,
            Err(_) => {} // mDNS names do not reveal the candidate's address family.
        }
    }

    fn usable_unicast(mut ip: IpAddr) -> Option<IpAddr> {
        if let IpAddr::V6(v6) = ip {
            // An IPv4-mapped socket address alone is no evidence of a translated IPv6 path.
            if let Some(v4) = v6.to_ipv4_mapped() {
                ip = IpAddr::V4(v4);
            }
        }
        if ip.is_unspecified()
            || ip.is_loopback()
            || ip.is_multicast()
            || matches!(ip, IpAddr::V4(v4) if v4.is_broadcast())
        {
            return None;
        }
        Some(ip)
    }
}

// Counts only; neither a STUN endpoint nor an address chosen by a peer is carried in
// these messages. The actual destinations are the current ICE agent's existing pairs.
type MappingCounts = [u8; 6];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct PunchIo {
    pub(crate) elapsed_ms: u32,
    pub(crate) counts: [u32; 6],
}

impl PunchIo {
    fn payload(self) -> [u8; 28] {
        let mut bytes = [0; 28];
        for (slot, value) in bytes
            .chunks_exact_mut(4)
            .zip(std::iter::once(self.elapsed_ms).chain(self.counts))
        {
            slot.copy_from_slice(&value.to_be_bytes());
        }
        bytes
    }

    fn decode(bytes: &[u8]) -> Option<Self> {
        let bytes: &[u8; 28] = bytes.try_into().ok()?;
        let mut words = [0; 7];
        for (value, bytes) in words.iter_mut().zip(bytes.chunks_exact(4)) {
            *value = u32::from_be_bytes(bytes.try_into().ok()?);
        }
        Some(Self {
            elapsed_ms: words[0],
            counts: words[1..].try_into().ok()?,
        })
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct PunchStatus {
    pub(crate) plan: Option<([u8; 2], [u16; 2], u32)>,
    pub(crate) full: Option<timed::FullSample>,
    pub(crate) full_peer: Option<timed::FullSample>,
    pub(crate) group_local: Option<timed::GroupSample>,
    pub(crate) group_peer: Option<timed::GroupSample>,
    pub(crate) local_profiles: Option<[u8; 4]>,
    local_linear_step: Option<u16>,
    local_primary_profile: Option<timed::Nat>,
    peer_primary_profile: Option<timed::Nat>,
    pub(crate) peer_profiles: Option<[u8; 4]>,
    pub(crate) peer_group_aliases: Option<u8>,
    pub(crate) timed_local: Option<timed::Sample>,
    pub(crate) timed_peer: Option<timed::Sample>,
    pub(crate) local_mapping: Option<MappingCounts>,
    pub(crate) remote_mapping: Option<MappingCounts>,
    pub(crate) started: bool,
    pub(crate) local_wakes: u8,
    pub(crate) remote_wakes: Option<u8>,
    pub(crate) remote_io: Option<PunchIo>,
}

struct PunchControl {
    status: watch::Sender<PunchStatus>,
    peer_ready: Option<oneshot::Sender<()>>,
    start: Option<oneshot::Sender<()>>,
    ready_sent: bool,
    report_io: watch::Sender<bool>,
}

impl PunchControl {
    fn new() -> (Self, oneshot::Receiver<()>, oneshot::Receiver<()>) {
        let (status, _) = watch::channel(PunchStatus::default());
        let (peer_ready, ready_rx) = oneshot::channel();
        let (start, start_rx) = oneshot::channel();
        let (report_io, _) = watch::channel(false);
        (
            Self {
                status,
                peer_ready: Some(peer_ready),
                start: Some(start),
                ready_sent: false,
                report_io,
            },
            ready_rx,
            start_rx,
        )
    }

    fn receive_ready(&mut self, payload: &[u8]) {
        if let Ok(counts) = MappingCounts::try_from(payload) {
            if let Some(ready) = self.peer_ready.take() {
                self.status.send_modify(|s| s.remote_mapping = Some(counts));
                let _ = ready.send(());
            }
        }
    }

    fn can_start(&self) -> bool {
        self.ready_sent && self.peer_ready.is_none() && self.start.is_some()
    }

    fn start(&mut self) {
        if self.can_start() {
            if let Some(start) = self.start.take() {
                self.status.send_modify(|s| s.started = true);
                let _ = start.send(());
            }
        }
    }

    fn receive(&mut self, kind: u8, data: &[u8], offerer: bool) {
        match (kind, data) {
            (PUNCH_IO_REQUEST, []) if !offerer => {
                self.report_io.send_replace(true);
            }
            (PUNCH_IO, data) if offerer => {
                if let Some(sample) = PunchIo::decode(data) {
                    self.status.send_if_modified(|s| {
                        if s.remote_io
                            .is_some_and(|old| old.elapsed_ms >= sample.elapsed_ms)
                        {
                            return false;
                        }
                        s.remote_io = Some(sample);
                        true
                    });
                }
            }
            (PUNCH_READY, _) => self.receive_ready(data),
            (PUNCH_GO, []) if !offerer => self.start(),
            (PUNCH_DONE, [count])
                if self.start.is_none() && usize::from(*count) <= PUNCH_DELAYS_MS.len() =>
            {
                self.status.send_modify(|s| {
                    s.remote_wakes.get_or_insert(*count);
                });
            }
            _ => {}
        }
    }
}

async fn report_punch_io(
    pc: WebRTCStream,
    events: mpsc::Sender<SetupEvent>,
    id: u64,
    mut requested: watch::Receiver<bool>,
) {
    let started = Instant::now();
    if requested.wait_for(|yes| *yes).await.is_err() {
        return;
    }
    let mut sampling = interval(IO_SAMPLE_INTERVAL);
    sampling.set_missed_tick_behavior(MissedTickBehavior::Skip);
    loop {
        sampling.tick().await;
        if let Some(counts) = pc.direct_punch_io().await {
            let elapsed_ms = u32::try_from(started.elapsed().as_millis()).unwrap_or(u32::MAX);
            let sample = PunchIo { elapsed_ms, counts };
            // Never delay candidate signaling or relay application data for diagnostics.
            let _ = events.try_send(SetupEvent::Send(frame(PUNCH_IO, id, &sample.payload())));
        }
    }
}

// This task runs alongside normal candidate trickle and ICE/DTLS. Its readiness wait,
// missing frames, or an inconclusive measurement cannot hold back an already usable path.
async fn coordinated_punch(
    pc: WebRTCStream,
    events: mpsc::Sender<SetupEvent>,
    id: u64,
    offerer: bool,
    status: watch::Sender<PunchStatus>,
    peer_ready: oneshot::Receiver<()>,
    start: oneshot::Receiver<()>,
) {
    let mapping = timeout(PUNCH_MEASUREMENT_BUDGET, pc.wait_for_punch_ready())
        .await
        .unwrap_or_default();
    status.send_modify(|s| s.local_mapping = Some(mapping));
    // The agent shares only mappings observed on the sockets it is currently using.
    // Emit these before READY so the other side can enqueue them before the GO checks.
    for json in pc
        .observed_udp_candidates()
        .await
        .into_iter()
        .take(MAX_CANDIDATES)
    {
        if let Some(bytes) = candidate_frame(id, &json) {
            if events.send(SetupEvent::Send(bytes)).await.is_err() {
                return;
            }
        }
    }
    if events
        .send(SetupEvent::Send(frame(PUNCH_READY, id, &mapping)))
        .await
        .is_err()
    {
        return;
    }
    if peer_ready.await.is_err() {
        return;
    }
    if offerer {
        // Wait until GO actually entered the relay writer before waking this side.
        if events.send(SetupEvent::StartPunch(id)).await.is_err() {
            return;
        }
    }
    if start.await.is_err() {
        return;
    }
    for ms in PUNCH_DELAYS_MS {
        if ms > 0 {
            tokio::time::sleep(Duration::from_millis(ms)).await;
        }
        if pc.request_punch_check().await {
            status.send_modify(|s| s.local_wakes += 1);
        }
    }
    let wakes = status.borrow().local_wakes;
    let _ = events
        .send(SetupEvent::Send(frame(PUNCH_DONE, id, &[wakes])))
        .await;
}

struct Attempt {
    mode: OfferMode,
    timed: Option<mpsc::Sender<(u8, Vec<u8>)>>,
    _task: SetupTask,
    answer: Option<oneshot::Sender<String>>,
    candidates: Option<mpsc::Sender<String>>,
    candidates_received: usize,
    local: CandidateCounts,
    remote: CandidateCounts,
    punch: Option<PunchControl>,
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

fn ice_needs_confirmed_path(io: Option<[u32; 6]>, direct_selected: bool) -> bool {
    matches!(io, Some([_, _, _, _, _, 0])) && !direct_selected
}

async fn ice_has_no_confirmed_path(pc: &WebRTCStream) -> bool {
    let (io, pair) = tokio::join!(
        pc.direct_punch_io(),
        timeout(Duration::from_millis(250), pc.is_relayed()),
    );
    // An inbound Binding request can be one-way. A matched reply or a selected
    // direct pair is enough to keep waiting for nomination and DTLS.
    pair.is_ok_and(|selected| ice_needs_confirmed_path(io, selected == Some(false)))
}

async fn wait_lite_connected(pc: &mut WebRTCStream) -> ResultType<()> {
    let probe = pc.clone();
    let idle = async {
        tokio::time::sleep(LITE_IDLE_WINDOW).await;
        if !ice_has_no_confirmed_path(&probe).await {
            pending::<()>().await;
        }
    };
    tokio::select! {
        biased;
        connected = pc.wait_connected(LITE_TIMEOUT) => connected,
        _ = idle => bail!("No matched ICE reply or selected direct pair during the lightweight window"),
    }
}

async fn wait_full_connected(
    pc: &mut WebRTCStream,
    ms: u64,
    mut status: watch::Receiver<PunchStatus>,
) -> Option<ResultType<()>> {
    let probe = pc.clone();
    let exhausted = async {
        let reported = status.wait_for(|status|
            status.full.is_some_and(|sample| sample.empty_pool)
                || status.full_peer.is_some_and(|sample| sample.empty_pool)).await.is_ok();
        if !reported || !ice_has_no_confirmed_path(&probe).await {
            pending::<()>().await;
        }
    };
    tokio::select! {
        biased;
        connected = pc.wait_connected(ms) => Some(connected),
        _ = exhausted => None,
    }
}

fn make_attempt(
    events: &mpsc::Sender<SetupEvent>,
    id: u64,
    offer: Option<String>,
    mode: OfferMode,
    plan: Option<timed::Plan>,
    linear_step: Option<u16>,
) -> Attempt {
    let offerer = offer.is_none();
    let base_timeout = if mode == OfferMode::Lite { LITE_TIMEOUT } else { RTC_TIMEOUT };
    let rtc_timeout = plan.map_or(base_timeout, |plan| plan.window().as_millis() as u64 + 8_000);
    let trickle = mode != OfferMode::Complete;
    let (timed, timed_rx) = mode.timed().then(|| mpsc::channel(12)).unzip();
    let (punch, coordination) = if mode == OfferMode::Coordinated || mode.timed() {
        let (control, ready, start) = PunchControl::new();
        let channel = (mode == OfferMode::Coordinated).then(|| (control.status.clone(), ready, start));
        (Some(control), channel)
    } else {
        (None, None)
    };
    let (answer, wait_for_answer) = oneshot::channel::<String>();
    let (candidates, mut remote_candidates) = mpsc::channel::<String>(MAX_CANDIDATES);
    let events = events.clone();
    let timed_job = timed_rx.zip(punch.as_ref().map(|p| p.status.clone()));
    let full_status = punch.as_ref().filter(|_| plan.is_some()).map(|p| p.status.subscribe());
    if let (Some(plan), Some(punch)) = (plan, &punch) {
        punch.status.send_modify(|s| {
            s.plan = Some((
                plan.header(),
                [plan.capacity(true), plan.capacity(false)],
                plan.window().as_millis() as u32,
            ));
        });
    }
    #[cfg(target_os = "ios")]
    let feedback = full_status.clone();
    let io_requested = punch
        .as_ref()
        .filter(|_| !offerer)
        .map(|c| c.report_io.subscribe());
    #[cfg(target_os = "ios")]
    let mut observation = crate::ios_p2p_diagnostics::Observation::new(offerer, match mode {
        OfferMode::Lite => "relay-upgrade-lite",
        OfferMode::Full => "relay-upgrade-full",
        _ => "relay-upgrade",
    });
    #[cfg(target_os = "ios")]
    if let (Some(observation), Some(control)) = (observation.as_mut(), &punch) {
        observation.set_punch_status(control.status.subscribe());
    }
    let task = tokio::spawn(async move {
        #[cfg(target_os = "ios")]
        let started = Instant::now();
        #[cfg(target_os = "ios")]
        let mut observer_counts = Vec::new();
        let mut stage = "capacity";
        let outcome: ResultType<Rtc> = async {
            if offerer && plan.is_some() {
                let target = Config::get_option(base::config::keys::OPTION_P2P_TCP53_TARGET);
                if !target.is_empty() {
                    stage = TCP53_STAGE;
                    #[cfg(target_os = "ios")]
                    if let Some(observation) = observation.as_mut() {
                        observation.set_stage(stage);
                    }
                    let ip = target.parse::<IpAddr>().context("TCP 53 check requires a public DNS IP")?;
                    let public = match ip {
                        IpAddr::V4(ip) => WebRTCStream::valid_expanded_endpoint(std::net::SocketAddrV4::new(ip, 53)),
                        IpAddr::V6(ip) => ip.segments()[0] & 0xe000 == 0x2000,
                    };
                    if !public {
                        bail!("TCP 53 check requires a public DNS IP");
                    }
                    timeout(Duration::from_millis(800), tokio::net::TcpStream::connect((ip, 53)))
                        .await.context("TCP 53 probe timed out")??;
                    stage = "capacity";
                }
            }
            let _slot = NEGOTIATIONS.try_acquire()?;
            let _pool = plan.map(|_| FULL_PORT_POOLS.try_acquire()).transpose()?;
            if let Some(plan) = plan.filter(|_| id <= 3 || id.is_power_of_two()) {
                log::info!("RustDesk full ports attempt {id} {:?}; localBudget={} peerBudget={} windowMs={}",
                    plan.nats, plan.capacity(offerer), plan.capacity(!offerer), plan.window().as_millis());
            }
            stage = "create peer connection";
            if mode.timed() && offer.as_ref().is_some_and(|s| !WebRTCStream::endpoint_has_no_candidates(s)) {
                bail!("Timed ICE requires a candidate-free trickle offer");
            }
            let mut rtc =
                Rtc(WebRTCStream::new_with_punch_profile(offer.as_deref().unwrap_or(""), false, rtc_timeout, mode.grouped(), plan.map_or(0, |plan| plan.capacity(offerer))).await?);
            let outbound_first = cfg!(target_os = "windows") && !offerer
                && mode == OfferMode::Coordinated && id % 2 == 1;
            let (events, _advertisements) = if outbound_first {
                let (tx, rx) = mpsc::channel(MAX_CANDIDATES);
                let task = tokio::spawn(advertise_after_check(rtc.0.clone(), rx, events.clone(), id));
                (tx, Some(SetupTask(task)))
            } else {
                (events.clone(), None)
            };
            #[cfg(target_os = "ios")]
            if let Some(observation) = observation.as_mut() {
                observation.observe(&rtc.0);
            }
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
            let kind = if offerer { mode.frame_kind() } else { ANSWER };
            let full_offer;
            let offer_bytes = if let Some(plan) = plan.filter(|_| offerer) {
                full_offer = [plan.header().as_slice(), sdp.as_bytes()].concat();
                full_offer.as_slice()
            } else {
                sdp.as_bytes()
            };
            events
                .send(SetupEvent::Send(frame(kind, id, offer_bytes)))
                .await
                .map_err(|_| hbb_common::anyhow::anyhow!("The session closed"))?;

            // A Build 78 controller will never request these samples. A Build 78
            // responder ignores the request and continues normal trickle and punching.
            if offerer && (mode == OfferMode::Coordinated || mode.timed()) && cfg!(any(target_os = "ios", test)) {
                let _ = events.try_send(SetupEvent::Send(frame(PUNCH_IO_REQUEST, id, &[])));
            }
            let _io_reporter = io_requested.map(|requested| {
                SetupTask(tokio::spawn(report_punch_io(
                    rtc.0.clone(),
                    events.clone(),
                    id,
                    requested,
                )))
            });

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
                        let Some(bytes) = candidate_frame(id, &candidate) else {
                            continue;
                        };
                        if events.send(SetupEvent::Send(bytes)).await.is_err() {
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
                if mode.timed() && !WebRTCStream::endpoint_has_no_candidates(&sdp) {
                    bail!("Timed ICE requires a candidate-free trickle answer");
                }
                rtc.0.set_remote_endpoint(&sdp).await?;
            }
            let (full_job, timed_job) = if plan.is_some() {
                (timed_job, None)
            } else {
                (None, timed_job)
            };
            let _full_task = full_job.zip(plan).map(|((control, status), plan)| {
                let pc = rtc.0.clone();
                let events = events.clone();
                SetupTask(tokio::spawn(async move {
                    timed::run_full(&pc, &events, id, offerer, control, status, plan, linear_step).await;
                }))
            });
            // Remote candidates that arrived early remain queued until the peer's SDP is set.
            let (first_candidate, peer_candidate) = oneshot::channel();
            let _receive_ice = if trickle {
                let pc = rtc.0.clone();
                let events = events.clone();
                Some(SetupTask(tokio::spawn(async move {
                    let mut first_candidate = Some(first_candidate);
                    if let Some((control, status)) = timed_job {
                        timed::run(&pc, &events, id, offerer, control, &mut remote_candidates, status, mode.grouped(), mode == OfferMode::Lite).await;
                    }
                    while let Some(candidate) = remote_candidates.recv().await {
                        if pc.add_remote_ice_candidate(&candidate).await.is_err() {
                            log::trace!("Live direct attempt {id} rejected a remote ICE candidate");
                        } else if let Some(first) = first_candidate.take() {
                            let _ = first.send(());
                        }
                    }
                })))
            } else {
                None
            };
            let _gateway = (mode == OfferMode::Coordinated).then(|| {
                let pc = rtc.0.clone();
                let events = events.clone();
                SetupTask(tokio::spawn(async move {
                    if peer_candidate.await.is_ok() {
                        if let Some(json) = pc.gather_gateway_candidate().await {
                            if let Some(bytes) = candidate_frame(id, &json) {
                                let _ = events.send(SetupEvent::Send(bytes)).await;
                            }
                        }
                    }
                }))
            });
            let _coordinator = coordination.map(|(status, ready, start)| {
                SetupTask(tokio::spawn(coordinated_punch(
                    rtc.0.clone(),
                    events.clone(),
                    id,
                    offerer,
                    status,
                    ready,
                    start,
                )))
            });
            stage = CHECK_STAGE;
            #[cfg(target_os = "ios")]
            if let Some(observation) = observation.as_mut() {
                observation.set_stage(stage);
            }
            let connected = if let Some(status) = full_status {
                match wait_full_connected(&mut rtc.0, rtc_timeout, status).await {
                    Some(result) => result,
                    None => {
                        stage = EMPTY_POOL_STAGE;
                        Err(hbb_common::anyhow::anyhow!("A peer finished without fresh UDP endpoints"))
                    }
                }
            } else if offerer && mode == OfferMode::Lite {
                wait_lite_connected(&mut rtc.0).await
            } else {
                rtc.0.wait_connected(rtc_timeout).await
            };
            #[cfg(target_os = "ios")]
            if let Some(observation) = observation.as_mut() {
                observation.sample_now(&rtc.0);
            }
            #[cfg(target_os = "ios")]
            if plan.is_some() && offerer
                && crate::get_local_option(base::config::keys::OPTION_RECORD_P2P_DIAGNOSTICS) == "Y"
            {
                if let Some(counts) = rtc.0.expanded_seed_counters().await {
                    observer_counts = counts.to_vec();
                }
            }
            connected?;
            stage = "verify direct selected pair";
            if rtc.0.is_relayed().await != Some(false) {
                bail!("ICE did not select a direct candidate pair");
            }
            // The authenticated relay carried both DTLS fingerprints. DTLS has verified that
            // each received certificate matches the fingerprint we got on that session.
            if plan.is_some() {
                rtc.0.release_unused_expanded_ports().await;
            }
            rtc.0.set_key(secretbox::gen_key());
            rtc.0.set_send_timeout(1_500);
            stage = "direct channel ready";
            Ok(rtc)
        }
        .await;
        #[cfg(target_os = "ios")]
        if let Some(observation) = observation.as_mut() {
            observation.finish(stage, outcome.as_ref().err());
        }
        #[cfg(target_os = "ios")]
        if let Some(status) = feedback.filter(|_| offerer && (id <= 3 || id.is_power_of_two() || outcome.is_ok())) {
            let [local_candidates, peer_candidates, probes_written] =
                status.borrow().full.unwrap_or_default().feedback_counts();
            let outcome = match (outcome.is_ok(), stage) {
                (true, _) => 1,
                (_, EMPTY_POOL_STAGE) => 2,
                (_, TCP53_STAGE) => 4,
                _ => 3,
            };
            crate::p2p::feedback::submit(hbb_common::rendezvous_proto::P2pFeedback {
                revision: 1,
                phase: 1,
                outcome,
                elapsed_ms: started.elapsed().as_millis().min(90_000) as u32,
                local_candidates,
                peer_candidates,
                probes_written,
                observer_counts,
                ..Default::default()
            });
        }
        let _ = events
            .send(SetupEvent::Finished(id, outcome.ok(), stage))
            .await;
    });
    Attempt {
        mode,
        timed,
        _task: SetupTask(task),
        answer: offerer.then_some(answer),
        candidates: trickle.then_some(candidates),
        candidates_received: 0,
        local: CandidateCounts::default(),
        remote: CandidateCounts::default(),
        punch,
    }
}

async fn relay_pending(
    relay: &Relay,
    direct: &mut Option<Direct>,
    seq: &mut Sequence,
    path: &watch::Sender<Path>,
    reason: Option<&'static str>,
) -> ResultType<()> {
    if let Some(direct) = direct.take() {
        path.send_replace(None);
        if direct.active {
            let reason = reason.unwrap_or("peer requested fallback");
            #[cfg(target_os = "ios")]
            crate::ios_p2p_diagnostics::record_fallback(reason);
            hbb_common::throttled_log!(
                Duration::from_secs(2), info, "Live direct returned to relay: {reason}"
            );
        }
        if reason.is_some() {
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
    fn a_recovering_ice_path_survives_a_transient_disconnect() {
        let now = Instant::now();
        let mut loss = None;
        assert!(!ice_stalled(&mut loss, now, true, false));
        assert!(!ice_stalled(&mut loss, now + PATH_TIMEOUT, true, true));
        assert!(!ice_stalled(&mut loss, now + PATH_TIMEOUT, true, false));
        assert!(ice_stalled(&mut loss, now + PATH_TIMEOUT * 2, true, false));
        assert!(!ice_stalled(&mut loss, now + PATH_TIMEOUT * 2, false, false));
    }

    #[tokio::test]
    async fn outbound_first_keeps_private_candidates_moving_and_releases_unchecked_public_one() {
        let pc = Rtc(WebRTCStream::new("", false, RTC_TIMEOUT).await.unwrap());
        let (input, rx) = mpsc::channel(4);
        let (output, mut received) = mpsc::channel(4);
        let worker = SetupTask(tokio::spawn(advertise_after_check(pc.0.clone(), rx, output, 1)));
        let candidate = |address: &str| {
            let json = format!(r#"{{"candidate":"candidate:x 1 udp 100 {address} 54321 typ srflx","sdpMid":"0","sdpMLineIndex":0}}"#);
            candidate_frame(1, &json).unwrap()
        };
        let public = candidate("8.8.8.8");
        let private = candidate("192.168.1.2");
        input.send(SetupEvent::Send(public.clone())).await.unwrap();
        input.send(SetupEvent::Send(private.clone())).await.unwrap();
        assert!(matches!(received.recv().await, Some(SetupEvent::Send(b)) if b == private));
        assert!(timeout(Duration::from_millis(150), received.recv()).await.is_err());
        assert!(matches!(timeout(Duration::from_secs(4), received.recv()).await,
            Ok(Some(SetupEvent::Send(b))) if b == public));
        drop(worker);
    }

    #[test]
    fn new_offer_is_sent_only_to_a_peer_advertising_both_capabilities() {
        for (trickle, punch, expected) in [
            (false, false, OFFER),
            (false, true, OFFER),
            (true, false, TRICKLE_OFFER),
            (true, true, PUNCH_OFFER),
        ] {
            assert_eq!(
                Role::offerer(trickle, punch, false, false, false)
                    .offer_mode()
                    .unwrap()
                    .frame_kind(),
                expected
            );
        }
    }

    #[test]
    fn full_requires_trickle_punch_timed_groups_and_full_capabilities() {
        for bits in 0u8..32 {
            let on = |n: u8| bits & (1 << n) != 0;
            let role = Role::offerer(on(0), on(1), on(2), on(3), on(4));
            assert_eq!(matches!(role, Role::FullOfferer), bits == 31);
        }
        assert!(matches!(Role::offerer(true, true, true, true, false), Role::GroupOfferer));
    }

    #[tokio::test]
    async fn quiet_lightweight_ice_ends_before_the_handshake_deadline() {
        let mut rtc = Rtc(WebRTCStream::new("", false, LITE_TIMEOUT).await.unwrap());
        let result = timeout(Duration::from_secs(8), wait_lite_connected(&mut rtc.0))
            .await
            .expect("quiet ICE did not release the lightweight attempt");
        assert!(result.is_err());
    }

    #[test]
    fn one_way_requests_do_not_extend_punching_but_a_confirmed_path_does() {
        assert!(ice_needs_confirmed_path(Some([28, 24, 24, 24, 0, 0]), false));
        assert!(!ice_needs_confirmed_path(Some([28, 24, 24, 24, 0, 1]), false));
        assert!(!ice_needs_confirmed_path(Some([28, 24, 24, 24, 0, 0]), true));
        assert!(!ice_needs_confirmed_path(None, false));
    }

    #[test]
    fn tcp53_refusal_does_not_fall_through_to_legacy_full_attempt() {
        let mut retries = RetrySchedule::default();
        assert!(retries.failed(OfferMode::Full, TCP53_STAGE) >= Duration::from_secs(3));
        assert!(retries.next(OfferMode::Full, 3) == OfferMode::Lite);
    }

    #[test]
    fn only_failed_lite_connectivity_checks_escalate_to_full_once() {
        use OfferMode::*;
        let mut retries = RetrySchedule::default();
        assert!(retries.next(Full, 1) == Lite);
        assert_eq!(retries.failed(Lite, "set remote description"), Duration::from_secs(2));
        assert!(retries.next(Full, 2) == Lite);
        assert!(retries.failed(Lite, CHECK_STAGE) < Duration::from_secs(1));
        assert!(retries.next(Full, 3) == Full);
        assert_eq!(retries.failed(Full, CHECK_STAGE), Duration::from_secs(4));
        assert!(retries.next(Full, 4) == Timed);
        retries.failed(Timed, CHECK_STAGE);
        assert!(retries.next(Full, 5) == Lite);

        let mut legacy = RetrySchedule::default();
        legacy.failed(Grouped, CHECK_STAGE);
        assert!(legacy.next(Grouped, 2) == Grouped);
        assert_ne!(Grouped.frame_kind(), FULL_OFFER);
    }

    #[test]
    fn confirmed_empty_full_pool_retries_lightweight_without_the_old_strategy() {
        let mut retries = RetrySchedule::default();
        assert_eq!(
            retries.failed(OfferMode::Full, EMPTY_POOL_STAGE),
            Duration::from_secs(3)
        );
        assert!(retries.next(OfferMode::Full, 3) == OfferMode::Lite);
    }

    #[test]
    fn grouped_checks_preserve_the_ordinary_and_single_pair_retries() {
        use OfferMode::*;
        assert!([Coordinated, Grouped, Coordinated, Timed, Coordinated, Grouped].iter()
            .enumerate().all(|(n, mode)| Grouped.for_attempt(n as u64 + 1) == *mode));
        assert!(Timed.for_attempt(2) == Timed && Coordinated.for_attempt(2) == Coordinated);
    }

    #[tokio::test]
    async fn punch_barrier_uses_only_the_first_valid_ready_and_one_controller_go() {
        let (mut controller, ready_a, go_a) = PunchControl::new();
        let (mut responder, ready_b, go_b) = PunchControl::new();
        let (mut a, mut b) = encrypted_pair().await;
        responder.receive(PUNCH_READY, &[9], false);
        responder.receive(PUNCH_GO, &[], false);
        responder.receive(PUNCH_DONE, &[2], false);
        assert!(!responder.status.borrow().started);
        assert!(responder.status.borrow().remote_wakes.is_none());
        assert!(responder.status.borrow().remote_mapping.is_none());

        let epoch = 2;
        let measured = [1, 2, 0, 0, 2, 1];
        let insufficient = [0; 6];
        a.send_raw(frame(PUNCH_READY, epoch, &measured).to_vec())
            .await
            .unwrap();
        let msg = b.next().await.unwrap().unwrap();
        let (kind, id, data) = decode(&msg).unwrap();
        assert_eq!(id, epoch);
        responder.receive(kind, data, false);
        controller.ready_sent = true;
        ready_b.await.unwrap();
        responder.receive(PUNCH_GO, &[], false); // local READY has not gone out
        assert!(!responder.status.borrow().started);
        b.send_raw(frame(PUNCH_READY, epoch, &insufficient).to_vec())
            .await
            .unwrap();
        responder.ready_sent = true;
        let msg = a.next().await.unwrap().unwrap();
        let (kind, _, data) = decode(&msg).unwrap();
        controller.receive(kind, data, true);
        ready_a.await.unwrap();
        assert!(controller.can_start() && responder.can_start());
        controller.receive(PUNCH_READY, &measured, true);
        controller.receive(PUNCH_GO, &[], true); // a responder cannot start the controller
        assert_eq!(
            controller.status.borrow().remote_mapping,
            Some(insufficient)
        );
        assert!(!controller.status.borrow().started);

        a.send_raw(frame(PUNCH_GO, epoch, &[]).to_vec())
            .await
            .unwrap();
        controller.start();
        let msg = b.next().await.unwrap().unwrap();
        let (kind, _, data) = decode(&msg).unwrap();
        responder.receive(kind, data, false);
        responder.receive(kind, data, false);
        go_a.await.unwrap();
        go_b.await.unwrap();
        assert!(!controller.can_start() && !responder.can_start());
        assert_eq!(responder.status.borrow().remote_mapping, Some(measured));
        controller.receive(PUNCH_DONE, &[4], true);
        assert!(controller.status.borrow().remote_wakes.is_none());
        controller.receive(PUNCH_DONE, &[2], true);
        controller.receive(PUNCH_DONE, &[3], true);
        assert_eq!(controller.status.borrow().remote_wakes, Some(2));
    }

    #[test]
    fn peer_udp_samples_are_requested_and_scoped_to_the_correct_role() {
        let (mut controller, _, _) = PunchControl::new();
        let (mut host, _, _) = PunchControl::new();
        let sample = PunchIo {
            elapsed_ms: 2100,
            counts: [91, 4, 3, 2, 1, 2],
        };
        let bytes = sample.payload();
        assert!(!*host.report_io.borrow());
        host.receive(PUNCH_IO_REQUEST, &[1], false);
        controller.receive(PUNCH_IO_REQUEST, &[], true);
        assert!(!*host.report_io.borrow() && !*controller.report_io.borrow());
        host.receive(PUNCH_IO_REQUEST, &[], false);
        assert!(*host.report_io.borrow());
        controller.receive(PUNCH_IO, &bytes[..27], true);
        host.receive(PUNCH_IO, &bytes, false);
        assert!(controller.status.borrow().remote_io.is_none());
        assert!(host.status.borrow().remote_io.is_none());
        controller.receive(PUNCH_IO, &bytes, true);
        controller.receive(
            PUNCH_IO,
            &PunchIo {
                elapsed_ms: 100,
                counts: [0; 6],
            }
            .payload(),
            true,
        );
        assert_eq!(controller.status.borrow().remote_io, Some(sample));
    }

    #[test]
    fn candidate_diagnostics_distinguish_signaled_base_families() {
        let mut counts = CandidateCounts::default();
        for line in [
            "candidate:a 1 udp 1 192.0.2.1 51234 typ host",
            "candidate:b 1 udp 1 2001:db8::2 51235 typ srflx raddr :: rport 0",
            "candidate:c 1 udp 1 mask.local 51236 typ host",
            "candidate:d 1 udp 1 192.0.2.8 51237 typ srflx raddr 10.0.0.7 rport 51234",
            "candidate:e 1 udp 1 192.0.2.8 51238 typ srflx network-id 1 raddr 2001:db8::9 rport 51234",
            "candidate:f 1 udp 1 192.0.2.8 51239 typ srflx raddr 0.0.0.0 rport 0",
            "candidate:g 1 udp 1 192.0.2.8 51240 typ srflx raddr :: rport 0",
            "candidate:h 1 udp 1 192.0.2.8 51241 typ srflx",
            "candidate:i 1 udp 1 192.0.2.8 51242 typ srflx raddr mask.local rport 51234",
            "candidate:j 1 udp 1 192.0.2.8 51243 typ srflx raddr ::ffff:10.0.0.7 rport 51234",
            "candidate:k 1 udp 1 0.0.0.0 51244 typ host",
            "candidate:l 1 udp 1 192.0.2.8 51245 typ relay raddr 2001:db8::9 rport 51234",
        ] {
            counts.record(
                hbb_common::serde_json::json!({ "candidate": line })
                    .to_string()
                    .as_bytes(),
            );
        }
        assert_eq!(
            (counts.v4, counts.v6, counts.host, counts.srflx),
            (10, 1, 3, 8)
        );
        assert_eq!(counts.relay, 1);
        assert_eq!(counts.v4_host, 1);
        assert_eq!(counts.v4_srflx_v4_base, 2);
        assert_eq!(counts.v4_srflx_v6_base, 1);
        assert_eq!(counts.v4_srflx_unknown_base, 4);
    }

    #[test]
    fn candidate_diagnostics_ignore_malformed_lines() {
        let mut counts = CandidateCounts::default();
        for line in [
            "",
            "candidate:",
            "bad 1 udp 1 192.0.2.1 51234 typ host",
            "candidate: 1 udp 1 192.0.2.1 51234 typ host",
            "candidate:a 0 udp 1 192.0.2.1 51234 typ host",
            "candidate:a 1 udp bad 192.0.2.1 51234 typ host",
            "candidate:a 1 udp 1 192.0.2.1 99999 typ host",
            "candidate:a 1 udp 1 192.0.2.1 51234 junk host",
            "candidate:a 1 udp 1 192.0.2.1 51234 typ invalid",
            "candidate:a 1 udp 1 192.0.2.1 51234 typ srflx raddr",
            "candidate:a 1 udp 1 192.0.2.1 51234 typ srflx raddr :: raddr 10.0.0.1",
        ] {
            counts.record(
                hbb_common::serde_json::json!({"candidate": line})
                    .to_string()
                    .as_bytes(),
            );
        }
        counts.record(b"invalid json");
        counts.record(br#"{"candidate": false}"#);
        assert_eq!(
            (counts.v4, counts.v6, counts.host, counts.srflx),
            (0, 0, 0, 0)
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
    async fn session_upgrades_over_native_tcp_with_webrtc_unused() {
        let (mut controller, mut controlled) = encrypted_pair().await;
        let listener = native::Listener::new();
        let ticket = listener.response()[native::ACCEPT.len()..].try_into().unwrap();
        let mut host_path = wrap_native(&mut controlled, native::Mode::Listen(listener)).unwrap();
        let dial = Box::new(|| -> BoxFuture<'static, ResultType<_>> {
            Box::pin(async {
                let (first, second) = encrypted_pair().await;
                tokio::spawn(async move { native::accept(second).await.unwrap().await.ok(); });
                Ok((first, None, "TCP"))
            })
        });
        let mut path = wrap_native(&mut controller, native::Mode::Call(ticket, dial)).unwrap();
        controller.send_raw(b"on the relay".to_vec()).await.unwrap();
        assert_eq!(&controlled.next_timeout(3_000).await.unwrap().unwrap()[..], b"on the relay");
        timeout(Duration::from_secs(8), async {
            path.changed().await.unwrap();
            host_path.changed().await.unwrap();
        }).await.unwrap();
        assert_eq!(*path.borrow(), Some("TCP"));
        assert_eq!(*host_path.borrow(), Some("TCP"));
        let frame = vec![0x37; FRAGMENT + 10];
        controlled.send_raw(frame.clone()).await.unwrap();
        assert_eq!(&controller.next_timeout(3_000).await.unwrap().unwrap()[..], frame);
        controller.send_raw(b"remote input".to_vec()).await.unwrap();
        assert_eq!(&controlled.next_timeout(3_000).await.unwrap().unwrap()[..], b"remote input");
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
        assert!(one.borrow().is_none() && two.borrow().is_none());
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
    async fn stale_punch_messages_do_not_interrupt_encrypted_relay_data() {
        let (mut old, mut new) = encrypted_pair().await;
        let _path = wrap(&mut new, Role::Answerer).unwrap();
        for (kind, bytes) in [
            (PUNCH_READY, &[0, 0, 0, 0, 0, 0][..]),
            (PUNCH_GO, &[][..]),
            (PUNCH_DONE, &[3][..]),
            (PUNCH_IO_REQUEST, &[][..]),
            (PUNCH_IO, &[0; 28][..]),
        ] {
            old.send_raw(frame(kind, 70, bytes).to_vec()).await.unwrap();
        }
        old.send_raw(frame(DATA, 1, b"still on relay").to_vec())
            .await
            .unwrap();
        assert_eq!(&new.next().await.unwrap().unwrap()[..], b"still on relay");
    }

    #[tokio::test]
    #[ignore = "requires two working local UDP/ICE peers"]
    async fn active_session_survives_relay_direct_relay_and_retry() {
        use std::sync::atomic::Ordering;

        async fn wait_for_path(path: &mut watch::Receiver<Path>, direct: bool) {
            timeout(Duration::from_secs(30), async {
                loop {
                    if path.borrow_and_update().is_some() == direct {
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
    path: watch::Sender<Path>,
    mut native: Option<native::Mode>,
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
    let offer_mode = role.offer_mode();
    let offerer = offer_mode.is_some() || matches!(native, Some(native::Mode::Call(..)));
    let mut native_task = None;
    let mut retries = RetrySchedule::default();
    let mut accepted_lite = None;
    let mut full_plan = None;
    let mut last_lite_step = None;
    let mut next_attempt = Instant::now() + Duration::from_secs(1);
    let mut direct: Option<Direct> = None;
    let mut direct_write: Option<BoxFuture<'static, (bool, ResultType<()>)>> = None;
    let mut first_relay_data = None;
    let mut seq = Sequence::default();
    let mut message: Option<BytesMut> = None;
    let mut tick = interval(Duration::from_millis(500));
    tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    #[cfg(target_os = "ios")]
    let mut path_changes = crate::p2p::ios_path::subscribe();
    loop {
        // A direct frame must never overtake a relay frame at the switch.
        let switching = direct.as_ref().map_or(false, |d| !d.active);
        tokio::select! {
            _ = async {
                #[cfg(target_os = "ios")]
                { let _ = path_changes.changed().await; }
                #[cfg(not(target_os = "ios"))]
                pending::<()>().await;
            }, if offerer && direct.is_none() && setup.is_none() => {
                // Keep the responder's existing pacing and any working path.
                next_attempt = next_attempt.min(Instant::now() + Duration::from_secs(1));
            }
            from_relay = relay.incoming.recv() => {
                let Some(packet) = from_relay else { break };
                match decode(&packet) {
                    Some((kind @ (DATA | DATA_MORE), number, payload)) => {
                        first_relay_data.get_or_insert_with(Instant::now);
                        receive_data(&to_app, &relay, &mut seq, number, payload, kind == DATA).await?;
                    }
                    Some((ACK, number, [])) => seq.acknowledge(number),
                    Some((kind @ (OFFER | TRICKLE_OFFER | PUNCH_OFFER | TIMED_OFFER | GROUP_OFFER | LITE_OFFER | FULL_OFFER), number, data))
                        if native.is_none() && !offerer && direct.is_none() && number > attempt
                            && data.len() <= MAX_SDP + usize::from(kind == FULL_OFFER) * 2
                            && if kind == FULL_OFFER {
                                accepted_lite == number.checked_sub(1) && WebRTCStream::has_expanded_udp_observer()
                            } else {
                                Instant::now() >= next_attempt
                            } =>
                    {
                        let (plan, data) = if kind == FULL_OFFER {
                            let Some((plan, data)) = timed::Plan::decode(data) else { continue };
                            (Some(plan), data)
                        } else {
                            (None, data)
                        };
                        if let Ok(sdp) = std::str::from_utf8(data) {
                            let step = if kind == FULL_OFFER {
                                setup.as_ref().and_then(|a| a.punch.as_ref())
                                    .and_then(|p| p.status.borrow().local_linear_step)
                                    .or(last_lite_step)
                            } else {
                                last_lite_step = None;
                                None
                            };
                            accepted_lite = (kind == LITE_OFFER).then_some(number);
                            attempt = number;
                            next_attempt = Instant::now() + Duration::from_secs(3);
                            let mode = match kind {
                                LITE_OFFER => OfferMode::Lite,
                                FULL_OFFER => OfferMode::Full,
                                GROUP_OFFER => OfferMode::Grouped,
                                TIMED_OFFER => OfferMode::Timed,
                                PUNCH_OFFER => OfferMode::Coordinated,
                                TRICKLE_OFFER => OfferMode::Trickle,
                                _ => OfferMode::Complete,
                            };
                            setup = Some(make_attempt(&event_tx, number, Some(sdp.to_owned()), mode, plan, step));
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
                    Some((timed::GROUP_ALIASES, number, [mask])) if number == attempt && *mask < 8 => {
                        if let Some(p) = setup.as_ref().filter(|a| a.mode.grouped()).and_then(|a| a.punch.as_ref()) {
                            p.status.send_modify(|s| s.peer_group_aliases = Some(*mask));
                        }
                    }
                    Some((timed::PROFILE, number, data)) if number == attempt && matches!(data.len(), 4 | 5) => {
                        if let Some(a) = setup.as_ref().filter(|a| a.mode.grouped()) {
                            if let (Some(p), Ok(counts)) = (a.punch.as_ref(), <[u8; 4]>::try_from(&data[..4])) {
                                let primary = data.get(4).copied().filter(|_| a.mode == OfferMode::Lite)
                                    .and_then(timed::Nat::decode);
                                p.status.send_modify(|s| {
                                    s.peer_profiles = Some(counts);
                                    s.peer_primary_profile = primary;
                                });
                            }
                        }
                    }
                    Some((timed::GROUP_RESULT, number, data)) if number == attempt => {
                        if let (Some(p), Some(sample)) = (setup.as_ref().filter(|a| a.mode.grouped()).and_then(|a| a.punch.as_ref()), timed::GroupSample::decode(data)) {
                            p.status.send_modify(|s| s.group_peer = Some(sample));
                        }
                    }
                    Some((timed::FULL_RESULT, number, data)) if number == attempt => {
                        if let (Some(p), Some(sample)) = (setup.as_ref().filter(|a| a.mode == OfferMode::Full).and_then(|a| a.punch.as_ref()), timed::FullSample::decode(data)) {
                            p.status.send_modify(|s| s.full_peer = Some(sample));
                        }
                    }
                    Some((kind @ (timed::FULL_SELECT | timed::FULL_HINT), number, data))
                        if number == attempt && (kind == timed::FULL_HINT && data.len() == 2
                            || kind == timed::FULL_SELECT && data.len() <= timed::MAX_FULL_ENDPOINTS * 6) => {
                        if let Some(tx) = setup.as_ref().filter(|a| a.mode == OfferMode::Full).and_then(|a| a.timed.as_ref()) {
                            let _ = tx.try_send((kind, data.to_vec()));
                        }
                    }
                    Some((timed::GROUP_SELECT, number, data)) if number == attempt && data.len() <= 21 => {
                        if let Some(tx) = setup.as_ref().filter(|a| a.mode.grouped()).and_then(|a| a.timed.as_ref()) {
                            let _ = tx.try_send((timed::GROUP_SELECT, data.to_vec()));
                        }
                    }
                    Some((timed::RESULT, number, data)) if number == attempt => {
                        if let Some(a) = setup.as_ref().filter(|a| a.timed.is_some()) {
                            if let (Some(p), Some(sample)) = (&a.punch, timed::Sample::decode(data)) {
                                p.status.send_modify(|s| s.timed_peer = Some(sample));
                            }
                        }
                    }
                    Some((kind @ timed::SELECT..=timed::GO, number, data)) if number == attempt && data.len() <= 8 => {
                        if let Some(tx) = setup.as_ref().and_then(|a| a.timed.as_ref()) {
                            let _ = tx.try_send((kind, data.to_vec()));
                        }
                    }
                    Some((kind @ (PUNCH_READY | PUNCH_GO | PUNCH_DONE | PUNCH_IO_REQUEST | PUNCH_IO), number, data)) if number == attempt => {
                        if let Some(control) = setup.as_mut().and_then(|a| a.punch.as_mut()) {
                            control.receive(kind, data, offerer);
                        }
                    }
                    Some((RESET, number, [])) if number == attempt => {
                        setup = None;
                        relay_pending(&relay, &mut direct, &mut seq, &path, None).await?;
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
                    Some(direct) => direct.lane.next().await,
                    None => pending().await,
                }
            } => {
                if let Some(Ok(packet)) = from_direct {
                    if let Some((kind @ (DATA | DATA_MORE), number, payload)) = decode(&packet) {
                        let previous = seq.received;
                        receive_data(&to_app, &relay, &mut seq, number, payload, kind == DATA).await?;
                        if kind == DATA && seq.received > previous {
                            if let Some(path) = direct.as_mut() {
                                path.first_received.get_or_insert_with(Instant::now);
                            }
                        }
                    }
                } else {
                    let reason = match from_direct {
                        None => "direct data channel ended",
                        Some(Err(err)) if err.kind() == std::io::ErrorKind::InvalidData => {
                            "direct data channel rejected a frame"
                        }
                        Some(Err(err)) if err.to_string().starts_with("WebRTC connection closed:") => {
                            "direct peer connection closed"
                        }
                        _ => "direct data channel read failed",
                    };
                    relay_pending(&relay, &mut direct, &mut seq, &path, Some(reason)).await?;
                }
            }
            payload = from_app.recv(), if message.is_none() => {
                let Some(payload) = payload else { break };
                message = Some(payload);
            }
            (last, result) = async {
                match direct_write.as_mut() {
                    Some(write) => write.await,
                    None => pending().await,
                }
            } => {
                direct_write = None;
                if let Err(err) = result {
                    let reason = if err.downcast_ref::<std::io::Error>()
                        .is_some_and(|io| io.kind() == std::io::ErrorKind::TimedOut)
                    {
                        "direct data channel write timed out"
                    } else {
                        "direct data channel write failed"
                    };
                    relay_pending(&relay, &mut direct, &mut seq, &path, Some(reason)).await?;
                } else if last {
                    if let Some(route) = direct.as_mut() {
                        route.first_sent.get_or_insert_with(Instant::now);
                    }
                }
            }
            _ = std::future::ready(()),
                if !switching && direct_write.is_none() && message.is_some()
                    && seq.sent - seq.acked < MAX_IN_FLIGHT =>
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
                    relay_pending(&relay, &mut direct, &mut seq, &path, Some("direct send queue full")).await?;
                }
                if let Some(route) = direct.as_ref() {
                    seq.track(bytes.clone());
                    // Keep polling inbound SCTP and relay acknowledgements under send backpressure.
                    direct_write = Some(route.lane.write(bytes, last));
                } else {
                    first_relay_data.get_or_insert_with(Instant::now);
                    relay.send(bytes).await?;
                }
            }
            Some((id, lane)) = async {
                match native.as_mut() {
                    Some(mode) => mode.incoming().await,
                    None => pending().await,
                }
            } => {
                if direct.is_none() && id > attempt {
                    attempt = id;
                    direct = Some(Direct::new(id, Lane::Native(lane)));
                }
            }
            Some(event) = events.recv() => match event {
                SetupEvent::Native(id, lane) => {
                    native_task = None;
                    direct = lane.map(|lane| Direct::new(id, Lane::Native(lane)));
                    next_attempt = Instant::now() + Duration::from_secs(10);
                }
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
                        if matches!(kind, LITE_OFFER | FULL_OFFER) && (id <= 3 || id.is_power_of_two()) {
                            if let Some(start) = first_relay_data {
                                let mode = if kind == LITE_OFFER { "lightweight" } else { "full" };
                                log::info!("RustDesk {mode} UDP offer sent; relayDataToOfferMs={}", start.elapsed().as_millis());
                            }
                        }
                        if kind == PUNCH_READY {
                            if let Some(control) = setup.as_mut().and_then(|a| a.punch.as_mut()) {
                                control.ready_sent = true;
                            }
                        }
                    }
                }
                SetupEvent::StartPunch(id) => {
                    if offerer && id == attempt {
                        if let Some(control) = setup.as_mut().and_then(|a| a.punch.as_mut()) {
                            if control.can_start() {
                                relay.send(frame(PUNCH_GO, id, &[])).await?;
                                control.start();
                            }
                        }
                    }
                }
                SetupEvent::Finished(id, rtc, stage) if id == attempt && setup.is_some() => {
                    let current = setup.take().unwrap();
                    if current.mode == OfferMode::Lite {
                        last_lite_step = current.punch.as_ref().and_then(|p| p.status.borrow().local_linear_step);
                    }
                    if id <= 3 || id.is_power_of_two() || rtc.is_some() {
                        let side = if offerer { "controller" } else { "controlled" };
                        if current.candidates.is_some() {
                            log::info!("Live direct {side} attempt {id} (trickle): {stage}; local {:?}, remote {:?}", current.local, current.remote);
                        } else {
                            log::info!("Live direct {side} attempt {id} (complete SDP): {stage}");
                        }
                    }
                    if let Some(rtc) = rtc {
                        direct = Some(Direct::new(id, Lane::WebRtc(rtc)));
                    } else if offerer {
                        if current.mode == OfferMode::Lite && stage == CHECK_STAGE {
                            let reported = current.punch.as_ref().map(|p| *p.status.borrow());
                            let measured = |primary, counts| match primary {
                                Some(nat) if nat != timed::Nat::Unknown => nat,
                                _ => timed::Nat::measured(counts),
                            };
                            full_plan = Some(timed::Plan::new(reported.map_or(
                                [timed::Nat::Unknown; 2],
                                |s| [
                                    measured(s.local_primary_profile, s.local_profiles),
                                    measured(s.peer_primary_profile, s.peer_profiles),
                                ],
                            )));
                        }
                        next_attempt = Instant::now() + retries.failed(current.mode, stage);
                    }
                }
                SetupEvent::Finished(_, _, _) => {}
            },
            _ = tick.tick() => {
                #[cfg(test)]
                if direct.as_ref().is_some_and(|d| matches!(d.lane, Lane::WebRtc(_))) && DROP_TEST_PATH.swap(false, std::sync::atomic::Ordering::AcqRel) {
                    relay_pending(&relay, &mut direct, &mut seq, &path, Some("test cut")).await?;
                }
                let now = Instant::now();
                if let Some(d) = direct.as_mut() {
                    let ice_timeout = if let Lane::WebRtc(rtc) = &d.lane {
                        let rx = rtc.0.rx_progress();
                        let progressed = rx != d.last_rx_progress;
                        d.last_rx_progress = rx;
                        ice_stalled(&mut d.ice_silent_since, now, rtc.0.is_disconnected(), progressed)
                    } else { false };
                    let reason = if !d.active && now.duration_since(d.since) >= PATH_TIMEOUT {
                        Some("relay drain timed out")
                    } else if seq.pending.front().is_some_and(|p| now.duration_since(p.sent) >= PATH_TIMEOUT) {
                        Some("direct application acknowledgement timed out")
                    } else if ice_timeout {
                        Some("ICE stopped receiving")
                    } else {
                        None
                    };
                    if reason.is_some() {
                        relay_pending(&relay, &mut direct, &mut seq, &path, reason).await?;
                    }
                }
                if let Some(mode @ native::Mode::Call(..)) = &native {
                    if direct.is_none() && now >= next_attempt && native_task.is_none() {
                        attempt += 1;
                        native_task = mode.start(attempt, event_tx.clone());
                    }
                } else if let Some(mode) = offer_mode {
                    if direct.is_none() && Instant::now() >= next_attempt && setup.is_none() {
                        attempt += 1;
                        // Only an authenticated peer advertising the new capability can enter full mode.
                        let mode = retries.next(mode, attempt);
                        let plan = if mode == OfferMode::Full { full_plan.take() } else { None };
                        setup = Some(make_attempt(&event_tx, attempt, None, mode, plan, last_lite_step));
                    }
                }
            }
        }
        if let Some(direct) = direct.as_mut() {
            if !direct.active && seq.acked == seq.sent {
                direct.active = true;
                path.send_replace(Some(direct.lane.label()));
                retries = RetrySchedule::default();
                let relay_ms = first_relay_data.map(|start| start.elapsed().as_millis());
                log::info!("Active RustDesk session switched to direct {}; relayDataToSwitchMs={relay_ms:?} drainMs={}", direct.lane.label(), direct.since.elapsed().as_millis());
            }
            if direct.active && !direct.reported {
                if let (Some(start), Some(tx), Some(rx)) = (first_relay_data, direct.first_sent, direct.first_received) {
                    direct.reported = true;
                    #[cfg(target_os = "ios")]
                    crate::ios_p2p_diagnostics::record_milestone("direct-data", "sent and received complete application messages");
                    log::info!("RustDesk direct application data observed; relayDataToSendMs={} relayDataToReceiveMs={}",
                        tx.saturating_duration_since(start).as_millis(), rx.saturating_duration_since(start).as_millis());
                }
            }
        } else {
            // The old data channel is closed. Its unacknowledged frames have been replayed.
            direct_write = None;
        }
    }
    Ok(())
}
