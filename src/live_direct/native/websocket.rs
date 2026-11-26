use super::{sessions, Relay, SetupTask, Ticket};
use hbb_common::{
    bail,
    sodiumoxide::crypto::auth,
    tokio::{self, sync::mpsc},
    websocket::WsFramedStream,
    ResultType, Stream,
};
use std::{cell::Cell, net::SocketAddr};

pub(crate) struct TcpFraming {
    marker: Option<Ticket>,
    websocket_next: Cell<bool>,
}

impl TcpFraming {
    pub(crate) fn new(ticket: Option<Ticket>) -> Self {
        Self {
            marker: ticket.as_ref().map(marker),
            websocket_next: Cell::new(false),
        }
    }

    // Both framings need the same listener/mapping. Reuse the TCP family's retry
    // budget so asking for both cannot evict a TCP punch already in flight.
    pub(crate) fn next_marker(&self) -> Option<Ticket> {
        self.marker
            .filter(|_| self.websocket_next.replace(!self.websocket_next.get()))
    }
}

pub(crate) fn marker(ticket: &Ticket) -> Ticket {
    auth::authenticate(b"rustdesk/direct/websocket/v1", &auth::Key(*ticket)).0
}

pub(crate) fn active_marker(bytes: &[u8]) -> Option<Ticket> {
    let tag: Ticket = bytes.try_into().ok()?;
    sessions()
        .lock()
        .unwrap()
        .keys()
        .any(|ticket| marker(ticket) == tag)
        .then_some(tag)
}

pub(crate) async fn upgrade(mut stream: Stream, peer: Option<SocketAddr>) -> ResultType<Stream> {
    let Stream::Tcp(tcp) = &mut stream else {
        bail!("WebSocket path requires TCP");
    };
    let ws = hbb_common::timeout(4_000, WsFramedStream::on_punched_tcp(tcp, peer)).await??;
    Ok(Stream::WebSocket(ws))
}

pub(super) fn bridge(mut stream: Stream) -> Relay {
    let (read, incoming) = mpsc::channel(64);
    let (outgoing, write) = mpsc::channel(64);
    let task = SetupTask(tokio::spawn(async move {
        if let Stream::WebSocket(ws) = &mut stream {
            if let Err(err) = ws.forward_authenticated(read, write).await {
                hbb_common::log::debug!("WebSocket path closed: {err}");
            }
        }
    }));
    Relay {
        incoming,
        outgoing,
        _reader: task,
        _writer: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::live_direct::native::{accept_for, attach, Listener};
    use hbb_common::{
        bytes::Bytes, sodiumoxide::crypto::secretbox, tcp::KxTranscript, tokio::net::TcpListener,
    };

    async fn encrypted_pair() -> (Stream, Stream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (dial, accept) = tokio::join!(tokio::net::TcpStream::connect(addr), listener.accept());
        let dial = dial.unwrap();
        let local = dial.local_addr().unwrap();
        let (a, b) = tokio::join!(
            upgrade(Stream::from(dial, local), Some(addr)),
            upgrade(Stream::from(accept.unwrap().0, addr), None),
        );
        let (mut a, mut b) = (a.unwrap(), b.unwrap());
        let key = secretbox::gen_key();
        let transcript = KxTranscript {
            initiator_pk: &[1; 32],
            responder_pk: &[2; 32],
            advertised: 1,
            picked: 1,
        };
        a.set_negotiated_key(key.clone(), true, &transcript)
            .unwrap();
        b.set_negotiated_key(key, false, &transcript).unwrap();
        (a, b)
    }

    #[tokio::test]
    async fn punched_websocket_carries_both_directions_after_session_attachment() {
        hbb_common::timeout(5_000, async {
            let mut listener = Listener::new();
            let ticket = listener.ticket;
            let (a, b) = encrypted_pair().await;
            let (dial, accept) = tokio::join!(
                attach(ticket, 9, (a, None, "WebSocket")),
                accept_for(b, Some(marker(&ticket)))
            );
            let _closed = accept.unwrap();
            let mut a = dial.unwrap();
            let (id, mut b) = listener.incoming.recv().await.unwrap();
            assert_eq!((id, b.label), (9, "WebSocket"));
            a.io.send(Bytes::from_static(b"mouse input")).await.unwrap();
            b.io.send(Bytes::from_static(b"screen image"))
                .await
                .unwrap();
            assert_eq!(&a.io.incoming.recv().await.unwrap()[..], b"screen image");
            assert_eq!(&b.io.incoming.recv().await.unwrap()[..], b"mouse input");
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn a_websocket_negotiated_for_one_session_cannot_attach_to_another() {
        hbb_common::timeout(5_000, async {
            let first = Listener::new();
            let second = Listener::new();
            let framing = TcpFraming::new(Some(first.ticket));
            assert_eq!(framing.next_marker(), None);
            let tag = framing.next_marker().unwrap();
            assert_eq!(active_marker(&tag), Some(tag));
            let (a, b) = encrypted_pair().await;
            let (dial, accept) = tokio::join!(
                attach(second.ticket, 9, (a, None, "WebSocket")),
                accept_for(b, Some(tag))
            );
            assert!(dial.is_err() && accept.is_err());
            drop(first);
            assert!(active_marker(&tag).is_none());
        })
        .await
        .unwrap();
    }
}
