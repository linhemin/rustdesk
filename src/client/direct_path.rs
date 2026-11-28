use super::*;

impl Client {
    pub(super) async fn create_webrtc_offerer(server: &str, key: &str) -> Option<WebRTCStream> {
        crate::p2p::observer_policy::prepare_direct_ice(server, key).await;
        match WebRTCStream::new_direct_only("", CONNECT_TIMEOUT).await {
            Ok(offer) => Some(offer),
            Err(err) => {
                log::warn!("webrtc offerer setup failed: {err}");
                None
            }
        }
    }

    pub(super) async fn start_direct_ice(
        peer: &str,
        key: &str,
        token: &str,
        conn_type: ConnType,
        interface: impl Interface,
        server: String,
        servers: Vec<String>,
        contained: bool,
        permission: &DirectRetryPermission,
    ) -> ResultType<PeerConnection> {
        let offer = Self::create_webrtc_offerer(&server, key)
            .await
            .context(DIRECT_ONLY_UNAVAILABLE)?;
        #[cfg(target_os = "ios")]
        let mut observation = crate::ios_p2p_diagnostics::Observation::new(true, "initial").map(
            |mut observation| {
                observation.observe(&offer);
                observation
            },
        );
        let result = Self::_start_inner(
            peer.to_owned(),
            key.to_owned(),
            token.to_owned(),
            conn_type,
            interface,
            (None, None),
            None,
            None,
            Some(offer),
            server,
            servers,
            contained,
            permission,
        )
        .boxed()
        .await;
        #[cfg(target_os = "ios")]
        if let Some(observation) = observation.as_mut() {
            let direct_webrtc = matches!(&result, Ok(((Stream::WebRTC(_), true, ..), ..)));
            observation.finish_initial(direct_webrtc, result.is_err());
        }
        result
    }

    pub(super) fn native_path_dialer(
        interface: impl Interface,
        key: &str,
        token: &str,
        original_pk: Option<Vec<u8>>,
        server: String,
        udp_upgrade_only: bool,
    ) -> crate::live_direct::native::Dial {
        let conn_type = interface.get_lch().read().unwrap().conn_type;
        let other_server = interface.get_lch().read().unwrap().other_server.clone();
        let (peer, key, token) = match other_server {
            Some((id, _, key)) => (id, key, String::new()),
            None => (interface.get_id(), key.to_owned(), token.to_owned()),
        };
        Box::new(move || {
            let (peer, key, token, server) =
                (peer.clone(), key.clone(), token.clone(), server.clone());
            let (interface, original_pk) = (interface.clone(), original_pk.clone());
            Box::pin(async move {
                if interface.is_policy_relay() || !crate::live_direct::native::enabled() {
                    bail!("Direct transport is disabled");
                }
                let udp_permission = DirectRetryPermission {
                    direct_only: true,
                    native_upgrade: true,
                    udp_upgrade_only: true,
                    ..Default::default()
                };
                let udp = Self::start_via_rendezvous(
                    &peer,
                    &key,
                    &token,
                    conn_type,
                    interface.clone(),
                    server.clone(),
                    Vec::new(),
                    true,
                    &udp_permission,
                );
                let path = if udp_upgrade_only || !tcp_punch_allowed() {
                    udp.await?
                } else {
                    // An authenticated upgrade has four seconds to present its session ticket.
                    // Give UDP its head start before opening the fallback TCP connection.
                    let tcp_permission = DirectRetryPermission {
                        direct_only: true,
                        native_upgrade: true,
                        ..Default::default()
                    };
                    let tcp = Self::_start_inner(
                        peer.clone(),
                        key.clone(),
                        token.clone(),
                        conn_type,
                        interface,
                        (None, None),
                        None,
                        None,
                        None,
                        server,
                        Vec::new(),
                        true,
                        &tcp_permission,
                    );
                    if crate::get_udp_punch_enabled() || crate::get_ipv6_punch_enabled() {
                        tokio::pin!(udp);
                        match tokio::time::timeout(
                            transport_preference::tcp_wait(Self::udp_preference_window()),
                            &mut udp,
                        )
                        .await
                        {
                            Ok(Ok(path)) => path,
                            Ok(Err(_)) => tcp.await?,
                            Err(_) => {
                                hbb_common::futures_util::future::select_ok([
                                    udp.boxed(),
                                    tcp.boxed(),
                                ])
                                .await?
                                .0
                            }
                        }
                    } else {
                        tcp.await?
                    }
                };
                let ((stream, direct, pk, kcp, label), _, _) = path;
                if !direct || !stream.is_secured() || pk.is_none() || pk != original_pk {
                    bail!("Native path does not match the authenticated session");
                }
                Ok((stream, kcp, label))
            })
        })
    }

    pub(super) fn native_parallel_dials(
        interface: impl Interface,
        key: &str,
        token: &str,
        original_pk: Option<Vec<u8>>,
        server: String,
        websocket_ticket: Option<crate::live_direct::native::Ticket>,
    ) -> crate::live_direct::parallel::Dials {
        let conn_type = interface.get_lch().read().unwrap().conn_type;
        let other_server = interface.get_lch().read().unwrap().other_server.clone();
        let (peer, key, token) = match other_server {
            Some((id, _, key)) => (id, key, String::new()),
            None => (interface.get_id(), key.to_owned(), token.to_owned()),
        };
        let enabled = [
            tcp_punch_allowed(),
            crate::get_udp_punch_enabled() || crate::get_ipv6_punch_enabled(),
        ];
        [false, true].map(|udp| {
            let (peer, key, token, server) =
                (peer.clone(), key.clone(), token.clone(), server.clone());
            let (interface, original_pk) = (interface.clone(), original_pk.clone());
            enabled[usize::from(udp)].then(|| -> crate::live_direct::native::Dial {
                let framing = crate::live_direct::native::websocket::TcpFraming::new(
                    websocket_ticket.filter(|_| !udp),
                );
                Box::new(move || {
                    let websocket_path_ticket = framing.next_marker();
                    let (peer, key, token, server) =
                        (peer.clone(), key.clone(), token.clone(), server.clone());
                    let (interface, original_pk) = (interface.clone(), original_pk.clone());
                    Box::pin(async move {
                        if interface.is_policy_relay() || !crate::live_direct::native::enabled() {
                            bail!("Direct transport is disabled");
                        }
                        let permission = DirectRetryPermission {
                            direct_only: true,
                            native_upgrade: true,
                            udp_upgrade_only: udp,
                            websocket_path_ticket,
                            ..Default::default()
                        };
                        let ((stream, direct, pk, kcp, label), _, _) = if udp {
                            Self::start_via_rendezvous(
                                &peer,
                                &key,
                                &token,
                                conn_type,
                                interface,
                                server,
                                Vec::new(),
                                true,
                                &permission,
                            )
                            .await?
                        } else {
                            Self::_start_inner(
                                peer,
                                key,
                                token,
                                conn_type,
                                interface,
                                (None, None),
                                None,
                                None,
                                None,
                                server,
                                Vec::new(),
                                true,
                                &permission,
                            )
                            .await?
                        };
                        if !direct || !stream.is_secured() || pk.is_none() || pk != original_pk {
                            bail!("Native path does not match the authenticated session");
                        }
                        Ok((stream, kcp, label))
                    })
                })
            })
        })
    }

    pub(super) async fn race_lan_and_rendezvous(
        peer: &str,
        key: &str,
        token: &str,
        conn_type: ConnType,
        interface: impl Interface,
        rendezvous_server: String,
        servers: Vec<String>,
        contained: bool,
        direct_permission: &DirectRetryPermission,
        initial_frames: Option<&mut path_rtt::InitialFrames>,
    ) -> ResultType<PeerConnection> {
        let lan = if !interface.is_force_relay()
            && tcp_punch_allowed()
            && matches!(conn_type, ConnType::DEFAULT_CONN | ConnType::FILE_TRANSFER)
            && interface.get_switch_code().is_empty()
        {
            crate::p2p::Interface::configured()
        } else {
            None
        };
        let lan_server = lan.map(|_| rendezvous_server.clone());
        let existing = Self::start_via_rendezvous(
            peer,
            key,
            token,
            conn_type,
            interface,
            rendezvous_server,
            servers,
            contained,
            direct_permission,
        );
        if let Some((iface, server)) = lan.zip(lan_server) {
            if !crate::is_udp_disabled()
                && (crate::get_udp_punch_enabled()
                    || crate::get_ipv6_punch_enabled()
                    || crate::get_webrtc_enabled())
            {
                let lan = Self::probe_lan(
                    peer,
                    key,
                    token,
                    conn_type,
                    &server,
                    iface,
                    direct_permission,
                );
                return transport_preference::choose(
                    [existing.boxed(), lan.boxed()],
                    Self::udp_preference_window(),
                    |path| direct_permission.session_rank(path),
                )
                .await;
            }
            let (mut lan, alternate) = prefer_lan_connection(
                Self::probe_lan(
                    peer,
                    key,
                    token,
                    conn_type,
                    &server,
                    iface,
                    direct_permission,
                ),
                existing,
                Duration::from_secs(1),
            )
            .await?;
            if let (Some(mut other), Some(initial_frames)) = (alternate, initial_frames) {
                let (lan_path, other_path) = (&mut lan.0, &mut other.0);
                if path_rtt::can_compare(
                    lan_path.1,
                    lan_path.2.as_deref(),
                    &lan_path.0,
                    other_path.1,
                    other_path.2.as_deref(),
                    &other_path.0,
                ) && path_rtt::prefer_alternate(
                    &mut lan_path.0,
                    &mut other_path.0,
                    initial_frames,
                )
                .await?
                {
                    return Ok(other);
                }
            }
            return Ok(lan);
        }
        existing.await
    }

    async fn probe_lan(
        peer: &str,
        key: &str,
        token: &str,
        conn_type: ConnType,
        server: &str,
        iface: crate::p2p::Interface,
        direct_permission: &DirectRetryPermission,
    ) -> ResultType<PeerConnection> {
        let address = crate::lan::probe_peer(peer, iface).await?;
        let mut socket = crate::p2p::connect_rendezvous(server, None, 1_000).await?;
        if !token.is_empty() {
            secure_tcp(&mut socket, key).await?;
        }
        let offered = if direct_permission.direct_only {
            Vec::new()
        } else {
            direct_permission
                .relay_start
                .offered(crate::p2p::relay_list::configured_for(key))
        };
        let mut request = RendezvousMessage::new();
        request.set_punch_hole_request(PunchHoleRequest {
            id: peer.to_owned(),
            licence_key: key.to_owned(),
            token: token.to_owned(),
            version: crate::VERSION.to_owned(),
            lan_probe: true,
            conn_type: conn_type.into(),
            relay_samples: if offered.len() > 1 {
                direct_permission.relay_start.remaining(
                    crate::p2p::regional_relay::offer_samples(key, socket.local_addr().is_ipv4())
                        .await,
                )
            } else {
                Vec::new()
            },
            session_relays: Some(SessionRelayList {
                servers: offered.clone(),
                ..Default::default()
            })
            .into(),
            direct_only: direct_permission.direct_only,
            ..Default::default()
        });
        socket.send(&request).await?;
        let Some(response) = crate::get_next_nonkeyexchange_msg(&mut socket, Some(1_000)).await
        else {
            bail!("LAN rendezvous timed out");
        };
        let Some(rendezvous_message::Union::PunchHoleResponse(reply)) = response.union else {
            bail!("LAN rendezvous declined");
        };
        direct_permission.observe_refusal(&reply.other_failure);
        if !reply.lan_probe || !reply.is_local() || reply.pk.is_empty() {
            bail!("LAN rendezvous declined");
        }
        let listener = AddrMangle::decode(&reply.socket_addr);
        if !listener.ip().is_unspecified() || listener.port() == 0 {
            bail!("Invalid LAN listener");
        }
        let mut stream = iface
            .connect(SocketAddr::from((address, listener.port())), 0, 1_000)
            .await?;
        if direct_permission.agrees_to_relay(
            &offered,
            reply.session_relays.as_ref(),
            &reply.relay_server,
            key,
        ) {
            direct_permission
                .relay_start
                .agreed(server, &reply.relay_server, &reply.pk);
        }
        let pk = Self::secure_connection(peer, reply.pk.into(), key, &mut stream).await?;
        if pk.is_none() || !stream.is_secured() {
            bail!("LAN peer identity could not be verified");
        }
        log::info!(
            "Secure LAN direct connection to {address}:{}",
            listener.port()
        );
        Ok((
            (stream, true, pk, None, "TCP"),
            (0, server.to_owned()),
            false,
        ))
    }
}
