use hbb_common::{
    log,
    protobuf::Message as _,
    rendezvous_proto::{rendezvous_message::Union, RendezvousMessage, TestNatRequest},
    sodiumoxide::randombytes,
    tokio::{
        self,
        net::UdpSocket,
        sync::oneshot,
        time::{Duration, Instant},
    },
    ResultType,
};
use std::{net::SocketAddr, sync::Mutex};

fn binding_request() -> [u8; 44] {
    let mut request = [0; 44];
    request[..8].copy_from_slice(&[0, 1, 0, 24, 0x21, 0x12, 0xa4, 0x42]);
    randombytes::randombytes_into(&mut request[8..20]);
    request[20..24].copy_from_slice(&[0x80, 0x22, 0, 20]);
    request[24..].copy_from_slice(b"RustDesk observation");
    request
}

fn mapped_port(reply: &[u8], request: &[u8; 44]) -> Option<u16> {
    let header = reply.get(..20)?;
    let length = usize::from(u16::from_be_bytes([header[2], header[3]]));
    if header[..2] != [1, 1]
        || header[4..] != request[4..20]
        || length != reply.len() - 20
        || length % 4 != 0
    {
        return None;
    }
    let mut attributes = &reply[20..];
    while !attributes.is_empty() {
        let header = attributes.get(..4)?;
        let kind = u16::from_be_bytes([header[0], header[1]]);
        let len = usize::from(u16::from_be_bytes([header[2], header[3]]));
        let payload = attributes.get(4..4 + len)?;
        if kind == 0x0020 {
            if !matches!(payload, [0, 1, ..] if len == 8)
                && !matches!(payload, [0, 2, ..] if len == 20)
            {
                return None;
            }
            let port = u16::from_be_bytes([payload[2], payload[3]]) ^ 0x2112;
            return (port != 0).then_some(port);
        }
        attributes = attributes.get(4 + ((len + 3) & !3)..)?;
    }
    None
}

pub(crate) async fn observe(
    socket: &UdpSocket,
    server: SocketAddr,
    public_port: &Mutex<u16>,
    mut stop: oneshot::Receiver<()>,
) -> ResultType<()> {
    let stun = binding_request();
    let mut legacy = RendezvousMessage::new();
    legacy.set_test_nat_request(TestNatRequest::new());
    let legacy = legacy.write_to_bytes()?;
    let mut interval = Duration::from_millis(30);
    let mut next = Instant::now();
    let mut buf = [0u8; 1500];
    loop {
        tokio::select! {
            biased;
            _ = &mut stop => return Ok(()),
            _ = tokio::time::sleep_until(next) => {
                for request in [&stun[..], &legacy] {
                    if let Err(err) = socket.send_to(request, server).await {
                        log::trace!("UDP mapping request send failed: {err}");
                    }
                }
                next = Instant::now() + interval;
                interval = (interval * 2).min(Duration::from_millis(200));
            }
            packet = socket.recv_from(&mut buf) => match packet {
                Ok((n, from)) if from == server => {
                    let reply = &buf[..n];
                    let port = mapped_port(reply, &stun).or_else(|| {
                        if reply.get(4..8) == Some(&stun[4..8]) {
                            return None;
                        }
                        let Union::TestNatResponse(response) =
                            RendezvousMessage::parse_from_bytes(reply).ok()?.union? else { return None };
                        u16::try_from(response.port).ok().filter(|port| *port != 0)
                    });
                    if let Some(port) = port {
                        *public_port.lock().unwrap() = port;
                        return Ok(());
                    }
                }
                Ok(_) => {}
                Err(err) => {
                    log::trace!("UDP mapping socket receive failed: {err}");
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            },
        }
    }
}
