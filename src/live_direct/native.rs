use super::{Relay, SetupTask};
use crate::kcp_stream::KcpStream;
use hbb_common::{
    anyhow::anyhow,
    bail,
    config::Config,
    futures_util::future::BoxFuture,
    sodiumoxide::randombytes,
    tcp::FramedStream,
    tokio::{
        self,
        sync::{mpsc, oneshot},
    },
    ResultType, Stream,
};
use std::{
    collections::HashMap,
    future::pending,
    sync::{Mutex, OnceLock},
};

pub(crate) mod websocket;

pub(crate) const CAPABILITY: &str = "rustdesk_live_native_v1";
pub(crate) const START: &[u8] = b"\0RD-native-v1-start";
pub(crate) const ACCEPT: &[u8] = b"\0RD-native-v1-accept";
const BOUND: &[u8] = b"\0RD-native-v1-bound";
pub(crate) type Ticket = [u8; 32];
type Candidate = (u64, Lane);
pub(crate) type Dial = Box<
    dyn Fn() -> BoxFuture<'static, ResultType<(Stream, Option<KcpStream>, &'static str)>> + Send,
>;

pub(crate) fn enabled() -> bool {
    !hbb_common::config::use_ws()
        && !Config::is_proxy()
        && Config::get_option("force-always-relay") != "Y"
        && (crate::client::tcp_punch_allowed()
            || crate::get_udp_punch_enabled()
            || crate::get_ipv6_punch_enabled())
}

fn sessions() -> &'static Mutex<HashMap<Ticket, mpsc::Sender<Candidate>>> {
    static SESSIONS: OnceLock<Mutex<HashMap<Ticket, mpsc::Sender<Candidate>>>> = OnceLock::new();
    SESSIONS.get_or_init(Default::default)
}

pub(super) struct Lane {
    pub(super) io: Relay,
    pub(super) label: &'static str,
    _kcp: Option<KcpStream>,
    _closed: Option<oneshot::Sender<()>>,
}

fn into_socket(mut stream: Stream) -> ResultType<FramedStream> {
    let Stream::Tcp(socket) = &mut stream else {
        bail!("Expected native stream")
    };
    if !socket.is_secured() {
        bail!("Unsecured path attachment");
    }
    let placeholder = FramedStream::from(tokio::io::duplex(1).0, socket.local_addr());
    Ok(std::mem::replace(socket, placeholder))
}

pub(super) fn relay_io(stream: Stream) -> ResultType<Relay> {
    match &stream {
        Stream::WebSocket(ws) if ws.is_secured() => Ok(websocket::bridge(stream)),
        _ => Ok(Relay::new(into_socket(stream)?)),
    }
}

pub(crate) struct Listener {
    ticket: Ticket,
    incoming: mpsc::Receiver<Candidate>,
}

impl Listener {
    pub(crate) fn new() -> Self {
        Self::with_capacity(1)
    }

    pub(super) fn with_capacity(capacity: usize) -> Self {
        let mut ticket = [0; 32];
        randombytes::randombytes_into(&mut ticket);
        let (sender, incoming) = mpsc::channel(capacity);
        sessions().lock().unwrap().insert(ticket, sender);
        Self { ticket, incoming }
    }

    pub(crate) fn response(&self) -> Vec<u8> {
        self.response_with(ACCEPT)
    }

    pub(super) fn response_with(&self, accept: &[u8]) -> Vec<u8> {
        [accept, &self.ticket].concat()
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        sessions().lock().unwrap().remove(&self.ticket);
    }
}

pub(crate) enum Mode {
    Call(Ticket, Dial),
    Listen(Listener),
}

impl Mode {
    pub(super) async fn incoming(&mut self) -> Option<Candidate> {
        match self {
            Self::Listen(listener) => listener.incoming.recv().await,
            Self::Call(..) => pending().await,
        }
    }

    pub(super) fn start(
        &self,
        id: u64,
        events: mpsc::Sender<super::SetupEvent>,
    ) -> Option<SetupTask> {
        let Self::Call(ticket, dial) = self else {
            return None;
        };
        let (ticket, connect) = (*ticket, dial());
        Some(SetupTask(tokio::spawn(async move {
            let attempt = async { attach(ticket, id, connect.await?).await };
            // Includes rendezvous, the bounded UDP probe window and the authenticated attachment.
            let budget = if crate::get_udp_punch_enabled() { 75_000 } else { 45_000 };
            let lane = match hbb_common::timeout(budget, attempt).await {
                Ok(Ok(lane)) => Some(lane),
                result => {
                    let reason = match result {
                        Ok(Err(err)) => err.to_string(),
                        _ => "timed out".to_owned(),
                    };
                    hbb_common::throttled_log!(
                        std::time::Duration::from_secs(30),
                        debug,
                        "Native direct retry kept the relay: {reason}"
                    );
                    None
                }
            };
            let _ = events.send(super::SetupEvent::Native(id, lane)).await;
        })))
    }
}

pub(super) async fn attach(
    ticket: Ticket,
    id: u64,
    (mut stream, kcp, label): (Stream, Option<KcpStream>, &'static str),
) -> ResultType<Lane> {
    if !stream.is_secured() || stream.is_webrtc() || (label == "WebSocket") != matches!(stream, Stream::WebSocket(_)) {
        bail!("Invalid authenticated attachment transport");
    }
    let kind = match label {
        "TCP" => 1,
        "UDP" => 2,
        "IPv6" => 3,
        "WebSocket" => 4,
        _ => bail!("Unexpected native transport"),
    };
    stream
        .send_raw([ticket.as_slice(), &id.to_be_bytes(), &[kind]].concat())
        .await?;
    let answer = stream
        .next_timeout(4_000)
        .await
        .ok_or_else(|| anyhow!("Path attachment timed out"))??;
    if answer.as_ref() != BOUND {
        bail!("Peer declined path attachment");
    }
    #[cfg(target_os = "ios")]
    crate::ios_p2p_diagnostics::record_milestone("native-upgrade", "peer confirmed session attachment");
    Ok(Lane {
        io: relay_io(stream)?,
        label,
        _kcp: kcp,
        _closed: None,
    })
}

pub(crate) async fn accept(stream: Stream) -> ResultType<oneshot::Receiver<()>> {
    accept_for(stream, None).await
}

pub(crate) async fn accept_for(mut stream: Stream, websocket_tag: Option<Ticket>) -> ResultType<oneshot::Receiver<()>> {
    if !stream.is_secured() || stream.is_webrtc() || websocket_tag.is_some() != matches!(stream, Stream::WebSocket(_)) {
        bail!("Invalid authenticated attachment transport");
    }
    let frame = stream
        .next()
        .await
        .ok_or_else(|| anyhow!("Closed path attachment"))??;
    if frame.len() != 41 {
        bail!("Invalid path attachment");
    }
    let ticket: &Ticket = frame[..32].try_into()?;
    if websocket_tag.is_some_and(|expected| expected != websocket::marker(ticket)) {
        bail!("WebSocket path belongs to a different session");
    }
    let id = u64::from_be_bytes(frame[32..40].try_into()?);
    let label = match (websocket_tag.is_some(), frame[40]) {
        (false, 1) => "TCP",
        (false, 2) => "UDP",
        (false, 3) => "IPv6",
        (true, 4) => "WebSocket",
        _ => bail!("Unknown native transport"),
    };
    let sender = sessions()
        .lock()
        .unwrap()
        .get(ticket)
        .cloned()
        .ok_or_else(|| anyhow!("No active session for this attachment"))?;
    let slot = sender
        .try_reserve()
        .map_err(|_| anyhow!("Session cannot accept a path"))?;
    stream.send_raw(BOUND.to_vec()).await?;
    let (closed, wait) = oneshot::channel();
    slot.send((
        id,
        Lane {
            io: relay_io(stream)?,
            label,
            _kcp: None,
            _closed: Some(closed),
        },
    ));
    Ok(wait)
}
