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

pub(crate) struct Listener {
    ticket: Ticket,
    incoming: mpsc::Receiver<Candidate>,
}

impl Listener {
    pub(crate) fn new() -> Self {
        let mut ticket = [0; 32];
        randombytes::randombytes_into(&mut ticket);
        let (sender, incoming) = mpsc::channel(1);
        sessions().lock().unwrap().insert(ticket, sender);
        Self { ticket, incoming }
    }

    pub(crate) fn response(&self) -> Vec<u8> {
        [ACCEPT, &self.ticket].concat()
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
            let attempt = async {
                let (stream, kcp, label) = connect.await?;
                let mut socket = into_socket(stream)?;
                let kind = match label {
                    "TCP" => 1,
                    "UDP" => 2,
                    "IPv6" => 3,
                    _ => bail!("Unexpected native transport"),
                };
                socket
                    .send_raw([ticket.as_slice(), &id.to_be_bytes(), &[kind]].concat())
                    .await?;
                let answer = socket
                    .next_timeout(4_000)
                    .await
                    .ok_or_else(|| anyhow!("Path attachment timed out"))??;
                if answer.as_ref() != BOUND {
                    bail!("Peer declined path attachment");
                }
                #[cfg(target_os = "ios")]
                crate::ios_p2p_diagnostics::record_milestone("native-upgrade", "peer confirmed session attachment");
                Ok(Lane {
                    io: Relay::new(socket),
                    label,
                    _kcp: kcp,
                    _closed: None,
                })
            };
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

pub(crate) async fn accept(stream: Stream) -> ResultType<oneshot::Receiver<()>> {
    let mut socket = into_socket(stream)?;
    let frame = socket
        .next()
        .await
        .ok_or_else(|| anyhow!("Closed path attachment"))??;
    if frame.len() != 41 {
        bail!("Invalid path attachment");
    }
    let ticket: &Ticket = frame[..32].try_into()?;
    let id = u64::from_be_bytes(frame[32..40].try_into()?);
    let label = match frame[40] {
        1 => "TCP",
        2 => "UDP",
        3 => "IPv6",
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
    socket.send_raw(BOUND.to_vec()).await?;
    let (closed, wait) = oneshot::channel();
    slot.send((
        id,
        Lane {
            io: Relay::new(socket),
            label,
            _kcp: None,
            _closed: Some(closed),
        },
    ));
    Ok(wait)
}
