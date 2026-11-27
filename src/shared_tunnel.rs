//! Additional authenticated sessions over the same selected RustDesk path.
use hbb_common::{
    anyhow::{anyhow, Context},
    bail,
    bytes::{Buf, BytesMut},
    sodiumoxide::crypto::secretbox,
    tcp::{FramedStream, KxTranscript},
    tokio::{
        self,
        io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf},
        sync::{mpsc, oneshot},
        time::{timeout, Duration},
    },
    ResultType, Stream,
};
use std::{
    collections::{HashMap, VecDeque},
    future::poll_fn,
    io,
    net::SocketAddr,
    pin::Pin,
    sync::{Arc, Mutex, OnceLock, Weak},
    task::{Context as TaskContext, Poll},
};
use tokio_util::compat::{Compat, FuturesAsyncReadCompatExt, TokioAsyncReadCompatExt};

pub(crate) const CAPABILITY: &str = "rustdesk_shared_sessions_v1";
pub(crate) const START: &[u8] = b"\0RD-sessions-1";
const ACCEPT: &[u8] = b"\0RD-sessions-ok-1";
const CHUNK: usize = 16384;
const DEADLINE: Duration = Duration::from_secs(8);

type Reply = oneshot::Sender<Stream>;
pub(crate) type Accept = Arc<dyn Fn(Stream) + Send + Sync>;
#[cfg(not(target_os = "ios"))]
pub(crate) enum ServerRole {
    Physical(Option<Accept>),
    Channel,
}
pub(crate) type Closed = oneshot::Receiver<()>;
pub(crate) type RouteKey = [u8; 32];

pub(crate) struct Route {
    pub direct: bool,
    pub label: &'static str,
    pub peer_key: Vec<u8>,
    pub live_path: Option<tokio::sync::watch::Receiver<Option<&'static str>>>,
}
struct Tunnel {
    open: mpsc::Sender<Reply>,
    route: Route,
}
fn routes() -> &'static Mutex<HashMap<RouteKey, Weak<Tunnel>>> {
    static ROUTES: OnceLock<Mutex<HashMap<RouteKey, Weak<Tunnel>>>> = OnceLock::new();
    ROUTES.get_or_init(Default::default)
}

pub(crate) async fn reuse(key: &RouteKey) -> Option<(Stream, bool, Vec<u8>, &'static str)> {
    let tunnel = routes().lock().unwrap().get(key)?.upgrade()?;
    let stream = timeout(DEADLINE, open(&tunnel)).await.ok()?.ok()?;
    let path = tunnel.route.live_path.as_ref().and_then(|rx| *rx.borrow());
    Some((
        stream,
        tunnel.route.direct || path.is_some(),
        tunnel.route.peer_key.clone(),
        path.unwrap_or(tunnel.route.label),
    ))
}

struct Channel<T> {
    io: Compat<yamux::Stream>,
    _lease: T,
}
impl<T: Unpin> AsyncRead for Channel<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Pin::new(&mut self.io).poll_read(cx, buf)
    }
}
impl<T: Unpin> AsyncWrite for Channel<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.io).poll_write(cx, buf)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.io).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.io).poll_shutdown(cx)
    }
}
fn channel<T: Send + Sync + Unpin + 'static>(
    raw: yamux::Stream,
    addr: SocketAddr,
    seed: &secretbox::Key,
    client: bool,
    lease: T,
) -> ResultType<Stream> {
    let mut id = [0u8; 32];
    id[..4].copy_from_slice(&raw.id().val().to_be_bytes());
    let mut stream = FramedStream::from(
        Channel {
            io: raw.compat(),
            _lease: lease,
        },
        addr,
    );
    stream.set_key_split(
        seed.clone(),
        client,
        &KxTranscript {
            initiator_pk: &id,
            responder_pk: &[0; 32],
            advertised: 1,
            picked: 1,
        },
    )?;
    Ok(Stream::Tcp(stream))
}

// Adapt the encrypted message transport to a byte stream without buffering a stalled lane's file in memory.
async fn carrier(mut network: Stream, pipe: tokio::io::DuplexStream) -> ResultType<()> {
    let (mut reader, mut writer) = tokio::io::split(pipe);
    let mut buf = [0; CHUNK];
    let mut incoming = BytesMut::new();
    network.set_max_packet_length(CHUNK + secretbox::MACBYTES);
    network.set_send_timeout(8000);
    loop {
        tokio::select! {
            frame = network.next(), if incoming.is_empty() => {
                let Some(frame) = frame else { return Ok(()) };
                incoming = frame?;
                if incoming.is_empty() || incoming.len() > CHUNK { bail!("Invalid shared tunnel frame") }
            }
            written = writer.write(&incoming), if !incoming.is_empty() => {
                let n = written?;
                if n == 0 { return Ok(()) }
                incoming.advance(n);
            }
            read = reader.read(&mut buf) => {
                let n = read?;
                if n == 0 { return Ok(()) }
                network.send_raw(buf[..n].to_vec()).await?;
            }
        }
    }
}

type Mux = yamux::Connection<Compat<tokio::io::DuplexStream>>;
fn transport(peer: &mut Stream, mode: yamux::Mode) -> Mux {
    let addr = peer.local_addr();
    let placeholder = Stream::Tcp(FramedStream::from(tokio::io::duplex(1).0, addr));
    let network = std::mem::replace(peer, placeholder);
    let (socket, pipe) = tokio::io::duplex(CHUNK * 4);
    tokio::spawn(async move {
        if let Err(err) = carrier(network, pipe).await {
            hbb_common::log::debug!("Shared tunnel ended: {err}")
        }
    });
    let mut config = yamux::Config::default();
    config
        .set_max_num_streams(16)
        .set_max_connection_receive_window(Some(16 * 1024 * 1024));
    yamux::Connection::new(socket.compat(), config, mode)
}
async fn open(tunnel: &Arc<Tunnel>) -> ResultType<Stream> {
    let (tx, rx) = oneshot::channel();
    tunnel
        .open
        .send(tx)
        .await
        .map_err(|_| anyhow!("Shared tunnel closed"))?;
    let mut stream = rx.await?;
    // Yamux publishes an outbound stream at its first write. The host sends the login challenge first.
    stream.send_raw(b"RD-session".to_vec()).await?;
    Ok(stream)
}

pub(crate) async fn connect(
    peer: &mut Stream,
    frames: &mut VecDeque<BytesMut>,
    key: RouteKey,
    route: Route,
) -> ResultType<Closed> {
    if !peer.is_secured() {
        bail!("Shared sessions require an authenticated encrypted path")
    }
    let seed = secretbox::gen_key();
    peer.send_raw([START, &seed.0].concat()).await?;
    timeout(DEADLINE, async {
        let mut bytes: usize = 0;
        loop {
            let frame = peer.next().await.context("Shared tunnel closed")??;
            if frame.as_ref() == ACCEPT {
                return Ok::<_, hbb_common::anyhow::Error>(());
            }
            bytes = bytes.saturating_add(frame.len());
            if bytes > 32 * 1024 * 1024 || frames.len() >= 256 {
                bail!("Shared tunnel handshake overflow")
            }
            frames.push_back(frame);
        }
    })
    .await??;
    let addr = peer.local_addr();
    let mut mux = transport(peer, yamux::Mode::Client);
    let (open_tx, mut requests) = mpsc::channel::<Reply>(16);
    let tunnel = Arc::new(Tunnel {
        open: open_tx,
        route,
    });
    let weak = Arc::downgrade(&tunnel);
    let (done, closed) = oneshot::channel();
    tokio::spawn(async move {
        loop {
            tokio::select! {
                request = requests.recv() => {
                    let Some(reply) = request else { break };
                    let Some(lease) = weak.upgrade() else { break };
                    let Ok(raw) = poll_fn(|cx| mux.poll_new_outbound(cx)).await else { break };
                    let Ok(stream) = channel(raw, addr, &seed, true, lease) else { break };
                    let _ = reply.send(stream);
                }
                _ = poll_fn(|cx| mux.poll_next_inbound(cx)) => break,
            }
        }
        let _ = timeout(DEADLINE, poll_fn(|cx| mux.poll_close(cx))).await;
        let mut registry = routes().lock().unwrap();
        if registry.get(&key).is_some_and(|entry| entry.ptr_eq(&weak)) {
            registry.remove(&key);
        }
        let _ = done.send(());
    });
    *peer = timeout(DEADLINE, open(&tunnel)).await??;
    routes()
        .lock()
        .unwrap()
        .insert(key, Arc::downgrade(&tunnel));
    Ok(closed)
}

#[cfg(not(target_os = "ios"))]
pub(crate) async fn listen(peer: &mut Stream, seed: &[u8], accept: Accept) -> ResultType<Closed> {
    if !peer.is_secured() {
        bail!("Shared sessions require an authenticated encrypted path")
    }
    let seed = secretbox::Key::from_slice(seed).context("Invalid shared tunnel handshake")?;
    let addr = peer.local_addr();
    peer.send_raw(ACCEPT.to_vec()).await?;
    let mut mux = transport(peer, yamux::Mode::Server);
    let (first, first_rx) = oneshot::channel::<Stream>();
    let (done, closed) = oneshot::channel();
    tokio::spawn(async move {
        let mut first = Some(first);
        let (lease, mut last_closed) = oneshot::channel::<()>();
        let lease = Arc::new(lease);
        let leases = Arc::downgrade(&lease);
        let mut initial_lease = Some(lease);
        loop {
            let raw = tokio::select! {
                _ = &mut last_closed => break,
                next = poll_fn(|cx| mux.poll_next_inbound(cx)) => match next {
                    Some(Ok(raw)) => raw,
                    _ => break,
                },
            };
            let Some(lease) = initial_lease.take().or_else(|| leases.upgrade()) else {
                break;
            };
            let Ok(mut stream) = channel(raw, addr, &seed, false, lease) else {
                break;
            };
            let primary = first.take();
            let accept = accept.clone();
            tokio::spawn(async move {
                stream.set_max_packet_length(64);
                if !matches!(timeout(DEADLINE, stream.next()).await, Ok(Some(Ok(b))) if b.as_ref() == b"RD-session")
                {
                    return;
                }
                stream.set_max_packet_length(if primary.is_some() {
                    usize::MAX
                } else {
                    crate::server::MAX_UNAUTHORIZED_MESSAGE
                });
                if let Some(tx) = primary {
                    let _ = tx.send(stream);
                } else {
                    accept(stream);
                }
            });
        }
        let _ = done.send(());
    });
    *peer = timeout(DEADLINE, first_rx).await??;
    Ok(closed)
}

#[cfg(all(test, not(target_os = "ios")))]
mod tests {
    use super::*;

    #[tokio::test]
    async fn reuse_authenticated_path_after_original_session_closes() {
        timeout(Duration::from_secs(5), async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let (client, host) =
                tokio::join!(tokio::net::TcpStream::connect(addr), listener.accept());
            let mut client = Stream::from(client.unwrap(), addr);
            let (host, remote) = host.unwrap();
            let mut host = Stream::from(host, remote);
            drop(listener);
            let outer = secretbox::gen_key();
            client.set_key(outer.clone());
            host.set_key(outer);
            let route = Route {
                direct: true,
                label: "TCP",
                peer_key: vec![3; 32],
                live_path: None,
            };
            let key = [77; 32];
            let (incoming, mut accepted) = mpsc::unbounded_channel();
            let server = tokio::spawn(async move {
                let start = host.next().await.unwrap().unwrap();
                let closed = listen(
                    &mut host,
                    start.strip_prefix(START).unwrap(),
                    Arc::new(move |s| {
                        incoming.send(s).unwrap();
                    }),
                )
                .await
                .unwrap();
                (host, closed)
            });
            let closed = connect(&mut client, &mut VecDeque::new(), key, route)
                .await
                .unwrap();
            let (mut primary, host_closed) = server.await.unwrap();
            client.send_raw(b"remote".to_vec()).await.unwrap();
            assert_eq!(&primary.next().await.unwrap().unwrap()[..], b"remote");
            assert!(reuse(&[78; 32]).await.is_none());
            let (mut file, direct, pk, label) = reuse(&key).await.unwrap();
            assert!(direct);
            assert_eq!(pk, vec![3; 32]);
            assert_eq!(label, "TCP");
            let mut server_file = accepted.recv().await.unwrap();
            drop(client);
            drop(primary);
            let (mut mic, _, _, _) = reuse(&key).await.unwrap();
            let mut server_mic = accepted.recv().await.unwrap();
            let payload = vec![0x7e; 64 * 1024];
            let ((), (), ()) = tokio::join!(
                async {
                    for _ in 0..16 {
                        file.send_raw(payload.clone()).await.unwrap();
                    }
                },
                async {
                    for _ in 0..16 {
                        assert_eq!(
                            server_file.next().await.unwrap().unwrap().as_ref(),
                            &payload
                        );
                    }
                },
                async {
                    server_mic.send_raw(b"microphone".to_vec()).await.unwrap();
                    assert_eq!(mic.next().await.unwrap().unwrap().as_ref(), b"microphone");
                }
            );
            drop(server_file);
            drop(server_mic);
            host_closed.await.unwrap();
            closed.await.unwrap();
            drop(file);
            drop(mic);
            assert!(reuse(&key).await.is_none());
        })
        .await
        .unwrap();
    }
}
