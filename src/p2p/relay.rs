use hbb_common::{
    config::{Config, CONNECT_TIMEOUT},
    socket_client::connect_tcp_local,
    websocket::{is_ws_endpoint, WsFramedStream},
    ResultType, Stream,
};

pub(crate) async fn connect(
    server: String,
    _key: &str,
    _ipv4: bool,
) -> ResultType<(Stream, &'static str)> {
    // A negotiated relay identifies an exact endpoint. The global signalling
    // WebSocket setting must not remap its port or substitute another path.
    if is_ws_endpoint(&server) {
        let ws = if server.starts_with("wss://") {
            WsFramedStream::new_verified_wss(&server, CONNECT_TIMEOUT).await?
        } else {
            WsFramedStream::new(&server, None, CONNECT_TIMEOUT).await?
        };
        return Ok((Stream::WebSocket(ws), "WebSocket"));
    }
    let tcp = async {
        let stream = connect_tcp_local(server.as_str(), None, CONNECT_TIMEOUT).await?;
        Ok((stream, "Relay"))
    };
    #[cfg(feature = "udp-relay")]
    if !Config::is_proxy() && !crate::is_udp_disabled() {
        let quic = async { connect_udp(&server, _key).await.map(|stream| (stream, "QUIC")) };
        return with_tcp_fallback(quic, tcp).await;
    }
    tcp.await
}

#[cfg(feature = "udp-relay")]
async fn with_tcp_fallback<T>(
    udp: impl std::future::Future<Output = Option<T>>,
    tcp: impl std::future::Future<Output = ResultType<T>>,
) -> ResultType<T> {
    use hbb_common::tokio::{self, time::{sleep, Duration}};
    tokio::pin!(udp);
    tokio::select! {
        first = &mut udp => if let Some(path) = first { return Ok(path) } else { return tcp.await },
        _ = sleep(Duration::from_millis(150)) => {}
    }
    tokio::pin!(tcp);
    tokio::select! {
        first = &mut udp => match first { Some(path) => Ok(path), None => tcp.await },
        first = &mut tcp => match first { Ok(path) => Ok(path), Err(err) => udp.await.ok_or(err) },
    }
}

#[cfg(feature = "udp-relay")]
pub(crate) async fn connect_udp(server: &str, key: &str) -> Option<Stream> {
    if Config::is_proxy() || is_ws_endpoint(server) || crate::is_udp_disabled() {
        return None;
    }
    let pk = crate::decode64(key).ok()?.try_into().ok()?;
    match hbb_common::timeout(1800, quic::connect(server, pk)).await {
        Ok(Ok(stream)) => Some(Stream::Tcp(stream)),
        Ok(Err(err)) => {
            hbb_common::log::debug!("UDP relay unavailable: {err}");
            None
        }
        Err(_) => {
            hbb_common::log::debug!("UDP relay handshake timed out");
            None
        }
    }
}

#[cfg(all(test, feature = "udp-relay"))]
mod tests {
    use super::with_tcp_fallback;
    use hbb_common::{anyhow::anyhow, tokio::{self, time::{sleep, Duration, Instant}}};

    #[tokio::test(start_paused = true)]
    async fn a_blocked_udp_relay_does_not_delay_a_working_tcp_relay() {
        let start = Instant::now();
        assert_eq!(with_tcp_fallback(std::future::pending(), async { Ok("TCP") }).await.unwrap(), "TCP");
        assert_eq!(start.elapsed(), Duration::from_millis(150));

        let slow_quic = async { sleep(Duration::from_millis(500)).await; Some("QUIC") };
        assert_eq!(with_tcp_fallback(slow_quic, async { Err(anyhow!("TCP refused")) }).await.unwrap(), "QUIC");
    }
}

#[cfg(feature = "udp-relay")]
mod quic {
    use hbb_common::{
        anyhow::anyhow,
        futures_util::{stream::FuturesUnordered, StreamExt},
        tcp::FramedStream,
        tokio::{io, net::lookup_host},
        ResultType,
    };
    use quinn::{crypto::rustls::QuicClientConfig, ClientConfig, Endpoint};
    use rustls::{
        client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
        crypto::{ring, verify_tls13_signature_with_raw_key},
        pki_types::{CertificateDer, ServerName, SubjectPublicKeyInfoDer, UnixTime},
        DigitallySignedStruct, Error, SignatureScheme,
    };
    use std::{
        net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
        sync::Arc,
    };

    #[derive(Debug)]
    struct PinnedRelay(SubjectPublicKeyInfoDer<'static>);

    impl ServerCertVerifier for PinnedRelay {
        fn requires_raw_public_keys(&self) -> bool {
            true
        }

        fn verify_server_cert(
            &self,
            key: &CertificateDer<'_>,
            chain: &[CertificateDer<'_>],
            _: &ServerName<'_>,
            _: &[u8],
            _: UnixTime,
        ) -> Result<ServerCertVerified, Error> {
            if chain.is_empty() && key.as_ref() == self.0.as_ref() {
                Ok(ServerCertVerified::assertion())
            } else {
                Err(Error::General("Unexpected relay signing key".into()))
            }
        }

        fn verify_tls12_signature(
            &self,
            _: &[u8],
            _: &CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Err(Error::General("QUIC requires TLS 1.3".into()))
        }

        fn verify_tls13_signature(
            &self,
            msg: &[u8],
            _: &CertificateDer<'_>,
            signature: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            verify_tls13_signature_with_raw_key(
                msg,
                &self.0,
                signature,
                &ring::default_provider().signature_verification_algorithms,
            )
        }

        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            vec![SignatureScheme::ED25519]
        }
    }

    pub(super) async fn connect(server: &str, pk: [u8; 32]) -> ResultType<FramedStream> {
        // RFC 8410 SubjectPublicKeyInfo for the selected relay's Ed25519 key.
        let mut spki = vec![
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0,
        ];
        spki.extend(pk);
        let mut tls =
            rustls::ClientConfig::builder_with_provider(Arc::new(ring::default_provider()))
                .with_protocol_versions(&[&rustls::version::TLS13])?
                .dangerous()
                .with_custom_certificate_verifier(Arc::new(PinnedRelay(spki.into())))
                .with_no_client_auth();
        tls.alpn_protocols = vec![b"rustdesk-relay/1".to_vec()];
        let config = ClientConfig::new(Arc::new(QuicClientConfig::try_from(tls)?));
        #[cfg(target_os = "windows")]
        if let Some(iface) = crate::p2p::Interface::configured() {
            use hbb_common::futures_util::{future::select_ok, FutureExt};
            let pinned = async {
                let addr = crate::p2p::configured_server_endpoint(server, iface, 400)
                    .await
                    .ok_or_else(|| anyhow!("Relay is not the configured rendezvous host"))?;
                let socket = crate::platform::bind_p2p_stun_udp(iface.address, iface.index, 0, 0)
                    .ok_or_else(|| anyhow!("Relay interface unavailable"))?;
                let endpoint = Endpoint::new(
                    Default::default(),
                    None,
                    socket.into_std()?,
                    Arc::new(quinn::TokioRuntime),
                )?;
                handshake(endpoint, addr, config.clone()).await
            };
            return select_ok([
                pinned.boxed(),
                system_routes(server, config.clone()).boxed(),
            ])
            .await
            .map(|r| r.0);
        }
        system_routes(server, config).await
    }

    async fn system_routes(server: &str, config: ClientConfig) -> ResultType<FramedStream> {
        let mut attempts = FuturesUnordered::new();
        for addr in lookup_host(server).await?.take(8) {
            attempts.push(dial(addr, config.clone()));
        }
        let mut last = anyhow!("No UDP relay address");
        while let Some(result) = attempts.next().await {
            match result {
                Ok(stream) => return Ok(stream),
                Err(err) => last = err,
            }
        }
        Err(last)
    }

    async fn dial(remote: SocketAddr, config: ClientConfig) -> ResultType<FramedStream> {
        let ip = if remote.is_ipv4() {
            IpAddr::V4(Ipv4Addr::UNSPECIFIED)
        } else {
            IpAddr::V6(Ipv6Addr::UNSPECIFIED)
        };
        let endpoint = Endpoint::client(SocketAddr::new(ip, 0))?;
        handshake(endpoint, remote, config).await
    }

    async fn handshake(
        endpoint: Endpoint,
        remote: SocketAddr,
        config: ClientConfig,
    ) -> ResultType<FramedStream> {
        let local = endpoint.local_addr()?;
        let conn = endpoint
            .connect_with(config, remote, "relay.rustdesk.invalid")?
            .await?;
        let (tx, rx) = conn.open_bi().await?;
        Ok(FramedStream::from(io::join(rx, tx), local))
    }

    #[cfg(test)]
    #[hbb_common::tokio::test]
    async fn pinned_relay_carries_frames_and_rejects_another_key() {
        use hbb_common::{sodiumoxide::crypto::sign, tokio};
        use quinn::crypto::rustls::QuicServerConfig;
        use rustls::{
            pki_types::PrivatePkcs8KeyDer, server::AlwaysResolvesServerRawPublicKeys,
            sign::CertifiedKey,
        };
        let (public, secret) = sign::gen_keypair();
        let mut der = vec![
            0x30, 0x2e, 0x02, 0x01, 0, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04,
            0x20,
        ];
        der.extend_from_slice(&secret[..32]);
        let provider = Arc::new(ring::default_provider());
        let key = provider
            .key_provider
            .load_private_key(PrivatePkcs8KeyDer::from(der).into())
            .unwrap();
        let cert = CertificateDer::from(key.public_key().unwrap().as_ref().to_vec());
        let identity =
            AlwaysResolvesServerRawPublicKeys::new(Arc::new(CertifiedKey::new(vec![cert], key)));
        let mut tls = rustls::ServerConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(identity));
        tls.alpn_protocols = vec![b"rustdesk-relay/1".to_vec()];
        let server =
            quinn::ServerConfig::with_crypto(Arc::new(QuicServerConfig::try_from(tls).unwrap()));
        let endpoint = Endpoint::server(server, "127.0.0.1:0".parse().unwrap()).unwrap();
        let address = endpoint.local_addr().unwrap();
        let task = tokio::spawn(async move {
            assert!(endpoint.accept().await.unwrap().await.is_err());
            let conn = endpoint.accept().await.unwrap().await.unwrap();
            let (tx, rx) = conn.accept_bi().await.unwrap();
            let mut stream = FramedStream::from(io::join(rx, tx), address);
            assert_eq!(
                &stream.next_timeout(2000).await.unwrap().unwrap()[..],
                b"controller"
            );
            stream.send_raw(b"relay".to_vec()).await.unwrap();
            conn.closed().await;
        });
        let exchange = async {
            assert!(connect(&address.to_string(), [0; 32]).await.is_err());
            let mut stream = connect(&address.to_string(), public.0).await.unwrap();
            stream.send_raw(b"controller".to_vec()).await.unwrap();
            assert_eq!(
                &stream.next_timeout(2000).await.unwrap().unwrap()[..],
                b"relay"
            );
            drop(stream);
            task.await.unwrap();
        };
        hbb_common::timeout(5000, exchange).await.unwrap();
    }
}
