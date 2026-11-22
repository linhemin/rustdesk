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

fn mapped_endpoint(reply: &[u8], request: &[u8; 44]) -> Option<SocketAddr> {
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
            if port == 0 {
                return None;
            }
            let mut bytes = [0u8; 16];
            for ((out, value), mask) in bytes.iter_mut().zip(&payload[4..]).zip(&request[4..20]) {
                *out = value ^ mask;
            }
            let ip = if len == 8 {
                std::net::Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3]).into()
            } else {
                std::net::IpAddr::V6(bytes.into())
            };
            return Some(SocketAddr::new(ip, port));
        }
        attributes = attributes.get(4 + ((len + 3) & !3)..)?;
    }
    None
}

pub(crate) async fn observe_ipv6(server: &str) -> ResultType<SocketAddr> {
    let server = tokio::net::lookup_host(server)
        .await?
        .find(SocketAddr::is_ipv6)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("No IPv6 rendezvous address"))?;
    let socket = UdpSocket::bind("[::]:0").await?;
    socket.connect(server).await?;
    let request = binding_request();
    let mut reply = [0u8; 512];
    for _ in 0..3 {
        socket.send(&request).await?;
        if let Ok(Ok(n)) = hbb_common::timeout(400, socket.recv(&mut reply)).await {
            if let Some(SocketAddr::V6(v6)) = mapped_endpoint(&reply[..n], &request) {
                if v6.ip().segments()[0] & 0xe000 == 0x2000 {
                    return Ok(SocketAddr::V6(v6));
                }
            }
        }
    }
    hbb_common::bail!("No global IPv6 mapping from rendezvous");
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
                    let port = mapped_endpoint(reply, &stun).map(|a| a.port()).or_else(|| {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn ipv6_observation_uses_the_rendezvous_transaction() {
        let nas = UdpSocket::bind("[::1]:0").await.unwrap();
        let endpoint = nas.local_addr().unwrap();
        let observed: SocketAddr = "[2001:db8::4321]:49154".parse().unwrap();
        let server = tokio::spawn(async move {
            let mut request = [0u8; 44];
            let (n, caller) = nas.recv_from(&mut request).await.unwrap();
            assert_eq!(n, request.len());
            let mut reply = vec![1, 1, 0, 24];
            reply.extend_from_slice(&request[4..20]);
            reply.extend_from_slice(&[0, 32, 0, 20, 0, 2]);
            reply.extend_from_slice(&(observed.port() ^ 0x2112).to_be_bytes());
            let SocketAddr::V6(v6) = observed else {
                unreachable!()
            };
            reply.extend(
                v6.ip()
                    .octets()
                    .iter()
                    .zip(&request[4..20])
                    .map(|(ip, mask)| ip ^ mask),
            );
            nas.send_to(&reply, caller).await.unwrap();
        });
        assert_eq!(observe_ipv6(&endpoint.to_string()).await.unwrap(), observed);
        server.await.unwrap();
    }
}
