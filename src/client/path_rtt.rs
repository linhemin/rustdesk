use base::message_proto::{message, Message, TestDelay};
use bytes::BytesMut;
use hbb_common::{
    log,
    protobuf::Message as _,
    rand,
    tokio::{
        self,
        time::{timeout_at, Duration, Instant},
    },
    ResultType, Stream,
};
use std::{collections::VecDeque, io};

// A pair of already-open direct paths may spend at most this long measuring, in parallel.
const SAMPLE_WINDOW: Duration = Duration::from_millis(150);
pub(super) type InitialFrames = VecDeque<BytesMut>;

pub(super) async fn next_frame(
    frames: &mut InitialFrames,
    stream: &mut Stream,
) -> Option<io::Result<BytesMut>> {
    match frames.pop_front() {
        Some(frame) => Some(Ok(frame)),
        None => stream.next().await,
    }
}

pub(super) fn can_compare(
    lan_direct: bool,
    lan_key: Option<&[u8]>,
    lan: &Stream,
    other_direct: bool,
    other_key: Option<&[u8]>,
    other: &Stream,
) -> bool {
    lan_direct
        && other_direct
        && lan.is_secured()
        && other.is_secured()
        && matches!((lan_key, other_key), (Some(a), Some(b)) if !a.is_empty() && a == b)
}

enum Sample {
    Echo(Duration),
    Unknown,
    Closed,
}

async fn measure(stream: &mut Stream, frames: &mut InitialFrames) -> Sample {
    let nonce = rand::random::<i64>();
    let mut request = Message::new();
    request.set_test_delay(TestDelay {
        time: nonce,
        from_client: true,
        ..Default::default()
    });
    let started = Instant::now();
    let deadline = started + SAMPLE_WINDOW;
    // A cancelled send can have advanced a cipher's write counter without flushing its frame.
    // Never reuse that stream. Only timing out while reading an echo means an unknown sample.
    if !matches!(
        timeout_at(deadline, stream.send(&request)).await,
        Ok(Ok(()))
    ) {
        return Sample::Closed;
    }
    timeout_at(deadline, async {
        // A stock peer can send its login challenge before echoing TestDelay. Preserve every
        // unrelated frame for the normal UI reader, including on timeout. Bound read-ahead.
        let mut bytes_read = 0;
        while Instant::now() < deadline && frames.len() < 4 && bytes_read < 8 * 1024 {
            let Some(Ok(frame)) = stream.next().await else {
                return Sample::Closed;
            };
            if frame.len() <= 64
                && Instant::now() <= deadline
                && matches!(
                    Message::parse_from_bytes(&frame).ok().and_then(|msg| msg.union),
                    Some(message::Union::TestDelay(t)) if t.from_client && t.time == nonce
                )
            {
                return Sample::Echo(started.elapsed());
            }
            bytes_read += frame.len();
            frames.push_back(frame);
        }
        Sample::Unknown
    })
    .await
    .unwrap_or(Sample::Unknown)
}

fn choose_alternate(lan: &Sample, other: &Sample) -> bool {
    match (lan, other) {
        (Sample::Echo(lan), Sample::Echo(other)) => {
            let gain = lan.saturating_sub(*other);
            gain >= Duration::from_millis(5) && gain >= *lan / 5
        }
        (Sample::Closed, Sample::Echo(_) | Sample::Unknown) => true,
        _ => false,
    }
}

pub(super) async fn prefer_alternate(
    lan: &mut Stream,
    other: &mut Stream,
    frames: &mut InitialFrames,
) -> ResultType<bool> {
    let mut other_frames = InitialFrames::new();
    let (lan_rtt, other_rtt) =
        tokio::join!(measure(lan, frames), measure(other, &mut other_frames));
    if matches!((&lan_rtt, &other_rtt), (Sample::Closed, Sample::Closed)) {
        hbb_common::bail!("Both peer connections closed before login");
    }
    let use_other = choose_alternate(&lan_rtt, &other_rtt);
    if let (Sample::Echo(lan), Sample::Echo(alternate)) = (&lan_rtt, &other_rtt) {
        log::info!(
            "Authenticated peer RTT: first path {lan:?}, alternate path {alternate:?}; selected {}",
            if use_other {
                "alternate"
            } else {
                "first"
            }
        );
    }
    if use_other {
        *frames = other_frames;
    }
    Ok(use_other)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        sodiumoxide::crypto::secretbox,
        tokio::net::{TcpListener, TcpStream},
    };

    async fn pair(encrypted: bool) -> (Stream, Stream) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (a, b) = tokio::join!(TcpStream::connect(addr), listener.accept());
        let (a, b) = (a.unwrap(), b.unwrap().0);
        a.set_nodelay(true).unwrap();
        b.set_nodelay(true).unwrap();
        let (mut a, mut b) = (Stream::from(a, addr), Stream::from(b, addr));
        if encrypted {
            let key = secretbox::gen_key();
            a.set_key(key.clone());
            b.set_key(key);
        }
        (a, b)
    }

    #[tokio::test]
    async fn only_same_verified_identity_on_two_encrypted_directs_is_eligible() {
        let (a, b) = pair(true).await;
        let (plain, _) = pair(false).await;
        let id = Some(&b"peer"[..]);
        assert!(can_compare(true, id, &a, true, id, &b));
        assert!(!can_compare(false, id, &a, true, id, &b));
        assert!(!can_compare(true, id, &a, false, id, &b));
        assert!(!can_compare(true, id, &a, true, id, &plain));
        assert!(!can_compare(true, id, &plain, true, id, &b));
        assert!(!can_compare(true, id, &a, true, None, &b));
        assert!(!can_compare(true, None, &a, true, None, &b));
        assert!(!can_compare(true, Some(b""), &a, true, Some(b""), &b));
        assert!(!can_compare(true, id, &a, true, Some(b"another peer"), &b));
    }

    #[test]
    fn keep_lan_unless_both_margins_are_met() {
        let echo = |ms| Sample::Echo(Duration::from_millis(ms));
        assert!(!choose_alternate(&echo(10), &echo(6)));
        assert!(!choose_alternate(&echo(100), &echo(81)));
        assert!(choose_alternate(&echo(25), &echo(20)));
        assert!(!choose_alternate(&echo(20), &echo(25)));
        assert!(!choose_alternate(&Sample::Unknown, &echo(1)));
        assert!(!choose_alternate(&echo(100), &Sample::Unknown));
        assert!(choose_alternate(&Sample::Closed, &echo(100)));
    }

    async fn echo(mut peer: Stream, before: &[u8], delay: Duration) {
        let frame = peer.next().await.unwrap().unwrap();
        let msg = Message::parse_from_bytes(&frame).unwrap();
        assert!(matches!(&msg.union, Some(message::Union::TestDelay(t)) if t.from_client));
        peer.send_raw(before.to_vec()).await.unwrap();
        tokio::time::sleep(delay).await;
        peer.send(&msg).await.unwrap();
        peer.send_raw(b"after echo".to_vec()).await.unwrap();
    }

    #[tokio::test]
    async fn real_peer_echo_selects_the_faster_path_and_preserves_the_winners_frames() {
        let (mut lan, lan_peer) = pair(true).await;
        let (mut other, other_peer) = pair(true).await;
        let mut frames = InitialFrames::new();
        let (use_other, _, _) = tokio::join!(
            prefer_alternate(&mut lan, &mut other, &mut frames),
            echo(lan_peer, b"LAN challenge", Duration::from_millis(65)),
            echo(other_peer, b"other challenge", Duration::ZERO)
        );
        assert!(use_other.unwrap());
        for expected in [&b"other challenge"[..], &b"after echo"[..]] {
            assert_eq!(
                next_frame(&mut frames, &mut other)
                    .await
                    .unwrap()
                    .unwrap()
                    .as_ref(),
                expected
            );
        }
    }

    #[tokio::test]
    async fn unmatched_and_late_echo_never_supply_a_metric_or_lose_early_frames() {
        let (mut client, mut peer) = pair(true).await;
        let mut frames = InitialFrames::new();
        let received = async {
            let frame = peer.next().await.unwrap().unwrap();
            let mut msg = Message::parse_from_bytes(&frame).unwrap();
            let Some(message::Union::TestDelay(t)) = &mut msg.union else {
                panic!("expected echo")
            };
            t.time = t.time.wrapping_add(1);
            peer.send_raw(b"challenge".to_vec()).await.unwrap();
            peer.send(&msg).await.unwrap();
            // Keep the stream open while its peer times out.
            tokio::time::sleep(SAMPLE_WINDOW * 2).await;
            peer.send_raw(frame.to_vec()).await.unwrap();
            msg
        };
        let (sample, wrong) = tokio::join!(measure(&mut client, &mut frames), received);
        assert!(matches!(sample, Sample::Unknown));
        assert_eq!(
            next_frame(&mut frames, &mut client)
                .await
                .unwrap()
                .unwrap()
                .as_ref(),
            b"challenge"
        );
        let saved = next_frame(&mut frames, &mut client).await.unwrap().unwrap();
        assert_eq!(Message::parse_from_bytes(&saved).unwrap(), wrong);
        let late = next_frame(&mut frames, &mut client).await.unwrap().unwrap();
        assert!(matches!(Message::parse_from_bytes(&late).unwrap().union,
            Some(message::Union::TestDelay(t)) if t.from_client));
    }

    #[tokio::test]
    async fn two_closed_paths_return_an_error_before_login() {
        let (mut lan, a) = pair(true).await;
        let (mut other, b) = pair(true).await;
        drop((a, b));
        assert!(
            prefer_alternate(&mut lan, &mut other, &mut InitialFrames::new())
                .await
                .is_err()
        );
    }
}
