use hbb_common::{
    anyhow::{ensure, Context}, config::{Config, CONNECT_TIMEOUT},
    rendezvous_proto::{DeviceStreamProof, RendezvousMessage},
    socket_client::connect_tcp, sodiumoxide::{crypto::sign, randombytes},
    websocket::{check_ws, WsFramedStream}, ResultType, Stream,
};

pub(super) struct Proof {
    pub nonce: [u8; 32],
    operator: sign::PublicKey,
}

pub(super) fn sibling_relay(endpoint: &str) -> Option<String> {
    let mut url = url::Url::parse(endpoint).ok()?;
    if !matches!(url.scheme(), "ws" | "wss") || url.path() != "/ws/id" {
        return None;
    }
    url.set_path("/ws/relay");
    Some(url.to_string())
}

#[cfg(test)]
mod tests {
    #[test]
    fn explicit_wss_relay_keeps_the_operator_domain_and_tls_port() {
        assert_eq!(super::sibling_relay("wss://rd.example:8443/ws/id").as_deref(),
            Some("wss://rd.example:8443/ws/relay"));
        assert_eq!(super::sibling_relay("rd.example:21116"), None);
    }
}

pub(super) async fn connect(host: &str, key: &str) -> ResultType<(Stream, Option<Proof>)> {
    let route = check_ws(host);
    let mut trusted_wss = false;
    let mut stream = if route.starts_with("wss://") && !key.is_empty() {
        match WsFramedStream::new_verified_wss(&route, CONNECT_TIMEOUT).await {
            Ok(stream) => { trusted_wss = true; Stream::WebSocket(stream) }
            Err(_) => connect_tcp(host, CONNECT_TIMEOUT).await?,
        }
    } else {
        connect_tcp(host, CONNECT_TIMEOUT).await?
    };
    if !trusted_wss {
        crate::secure_tcp(&mut stream, key).await?;
    }
    let proof = if trusted_wss || stream.is_secured() {
        crate::get_rs_pk(key).filter(|_| !key.is_empty()).map(|operator| {
            let mut nonce = [0; 32];
            randombytes::randombytes_into(&mut nonce);
            Proof { nonce, operator }
        })
    } else { None };
    Ok((stream, proof))
}

impl Proof {
    pub async fn answer(self, request: DeviceStreamProof, stream: &mut Stream) -> ResultType<()> {
        let challenge: &[u8; 32] = request.challenge.as_ref().try_into()?;
        let (sk, pk) = Config::get_key_pair();
        let secret = sign::SecretKey::from_slice(&sk).context("Invalid device signing key")?;
        let public = sign::PublicKey::from_slice(&pk).context("Invalid device public key")?;
        let id = Config::get_id();
        let transcript = |server| hbb_common::device_stream::transcript(server, &self.operator.0,
            &public.0, &id, &self.nonce, challenge);
        let signature = sign::Signature::from_bytes(&request.signature)
            .map_err(|_| hbb_common::anyhow::anyhow!("Invalid rendezvous signature"))?;
        ensure!(sign::verify_detached(&signature, &transcript(true), &self.operator),
            "Invalid rendezvous device-stream challenge");
        let mut reply = RendezvousMessage::new();
        reply.set_device_stream_proof(DeviceStreamProof {
            signature: sign::sign_detached(&transcript(false), &secret).to_bytes().to_vec().into(),
            ..Default::default()
        });
        stream.send(&reply).await
    }
}
