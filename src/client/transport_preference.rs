use hbb_common::{
    anyhow::anyhow,
    futures_util::{future::BoxFuture, stream::FuturesUnordered, StreamExt},
    tokio::time::{timeout_at, Duration, Instant},
    ResultType,
};

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum Rank {
    TcpRelay,
    TcpDirect,
    UdpRelay,
    StartupDirect,
    UdpDirect,
    VerifiedStartupRelay,
}

pub(super) fn tcp_wait(grace: Duration) -> Duration {
    grace.max(Duration::from_secs(8))
}

pub(super) fn rank(label: &str, direct: bool) -> Rank {
    match (label, direct) {
        ("UDP" | "IPv6" | "WebRTC", true) => Rank::UdpDirect,
        // The linked ICE agent gathers UDP4/UDP6 and implements TURN over UDP.
        ("QUIC" | "WebRTC", false) => Rank::UdpRelay,
        (_, true) => Rank::TcpDirect,
        _ => Rank::TcpRelay,
    }
}

pub(super) async fn choose<'a, T: 'a>(
    candidates: impl IntoIterator<Item = BoxFuture<'a, ResultType<T>>>,
    grace: Duration,
    classify: impl Fn(&T) -> Rank,
) -> ResultType<T> {
    let mut pending: FuturesUnordered<_> = candidates.into_iter().collect();
    let mut best = None;
    let mut deadline = None;
    let mut error = anyhow!("No transport available");
    loop {
        let next = match deadline {
            Some(end) => timeout_at(end, pending.next()).await.ok().flatten(),
            None => pending.next().await,
        };
        match next {
            Some(Ok(path)) => {
                let rank = classify(&path);
                if rank >= Rank::UdpDirect {
                    return Ok(path);
                }
                if best.as_ref().map_or(true, |(old, _)| rank > *old) {
                    best = Some((rank, path));
                    // Committing direct TCP ends this race permanently. Allow the six-second
                    // UDP check plus signaling, while an established UDP relay can upgrade live.
                    let wait = if rank == Rank::StartupDirect {
                        // Let a paired regional relay finish authenticating. Release the
                        // verified direct promptly if the relay is unreachable or legacy.
                        Duration::from_millis(750)
                    } else if rank < Rank::UdpRelay {
                        tcp_wait(grace)
                    } else {
                        grace
                    };
                    let end = Instant::now() + wait;
                    deadline = Some(deadline.map_or(end, |previous| end.min(previous)));
                }
            }
            Some(Err(err)) => error = err,
            None => return best.map(|(_, path)| path).ok_or(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{futures_util::FutureExt, tokio};

    #[tokio::test(start_paused = true)]
    async fn a_working_udp_path_beats_a_ready_tcp_path() {
        for direct in [true, false] {
            let tcp = async { Ok(("TCP", true)) }.boxed();
            let udp = async {
                tokio::time::sleep(Duration::from_millis(4_500)).await;
                Ok((if direct { "UDP" } else { "QUIC" }, direct))
            }
            .boxed();
            let result = choose([tcp, udp], Duration::from_secs(3), |p| rank(p.0, p.1))
                .await
                .unwrap();
            assert_eq!(result.0, if direct { "UDP" } else { "QUIC" });
        }
    }

    #[tokio::test(start_paused = true)]
    async fn unreachable_udp_releases_the_working_tcp_path_at_the_deadline() {
        let start = Instant::now();
        let tcp = async { Ok(("TCP", true)) }.boxed();
        let result = choose(
            [tcp, std::future::pending().boxed()],
            Duration::from_secs(3),
            |p| rank(p.0, p.1),
        )
        .await
        .unwrap();
        assert_eq!(result.0, "TCP");
        assert_eq!(start.elapsed(), Duration::from_secs(8));
    }

    #[tokio::test(start_paused = true)]
    async fn established_bootstrap_relay_can_win_without_stranding_a_ready_direct() {
        let direct = async { Ok(Rank::StartupDirect) }.boxed();
        let relay = async {
            tokio::time::sleep(Duration::from_millis(200)).await;
            Ok(Rank::VerifiedStartupRelay)
        }.boxed();
        assert!(choose([direct, relay], Duration::from_secs(3), |r| *r).await.unwrap() == Rank::VerifiedStartupRelay);
        let start = Instant::now();
        let direct = async { Ok(Rank::StartupDirect) }.boxed();
        assert!(choose([direct, std::future::pending().boxed()], Duration::from_secs(3), |r| *r).await.unwrap() == Rank::StartupDirect);
        assert_eq!(start.elapsed(), Duration::from_millis(750));
    }
}
