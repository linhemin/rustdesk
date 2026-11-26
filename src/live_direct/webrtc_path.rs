use super::{PunchStatus, LITE_IDLE_WINDOW, LITE_TIMEOUT, PATH_TIMEOUT};
use hbb_common::{
    bail,
    bytes::{Bytes, BytesMut},
    futures_util::{future::BoxFuture, FutureExt},
    tokio::{
        self,
        sync::watch,
        time::{timeout, Duration, Instant},
    },
    webrtc::WebRTCStream,
    ResultType,
};
use std::future::pending;

pub(super) struct Rtc(pub(super) WebRTCStream);

impl Rtc {
    pub(super) async fn next(&mut self) -> Option<std::io::Result<BytesMut>> {
        self.0.next().await
    }

    pub(super) fn write(
        &self,
        bytes: Bytes,
        last: bool,
    ) -> BoxFuture<'static, (bool, ResultType<()>)> {
        let mut stream = self.0.clone();
        async move { (last, stream.send_bytes(bytes).await) }.boxed()
    }

    pub(super) fn stopped_receiving(
        &self,
        since: &mut Option<Instant>,
        last: &mut u64,
        now: Instant,
    ) -> bool {
        let received = self.0.rx_progress();
        let progressed = received != *last;
        *last = received;
        ice_stalled(since, now, self.0.is_disconnected(), progressed)
    }
}

impl Drop for Rtc {
    fn drop(&mut self) {
        self.0.close_detached();
    }
}

pub(super) fn ice_stalled(
    since: &mut Option<Instant>,
    now: Instant,
    disconnected: bool,
    progressed: bool,
) -> bool {
    if !disconnected || progressed {
        *since = None;
        return false;
    }
    now.duration_since(*since.get_or_insert(now)) >= PATH_TIMEOUT
}

pub(super) fn ice_needs_confirmed_path(io: Option<[u32; 6]>, direct_selected: bool) -> bool {
    matches!(io, Some([_, _, _, _, _, 0])) && !direct_selected
}

async fn ice_has_no_confirmed_path(pc: &WebRTCStream) -> bool {
    let (io, pair) = tokio::join!(
        pc.direct_punch_io(),
        timeout(Duration::from_millis(250), pc.is_relayed()),
    );
    // An inbound Binding request can be one-way. A matched reply or a selected
    // direct pair is enough to keep waiting for nomination and DTLS.
    pair.is_ok_and(|selected| ice_needs_confirmed_path(io, selected == Some(false)))
}

pub(super) async fn wait_lite_connected(pc: &mut WebRTCStream) -> ResultType<()> {
    let probe = pc.clone();
    let idle = async {
        tokio::time::sleep(LITE_IDLE_WINDOW).await;
        if !ice_has_no_confirmed_path(&probe).await {
            pending::<()>().await;
        }
    };
    tokio::select! {
        biased;
        connected = pc.wait_connected(LITE_TIMEOUT) => connected,
        _ = idle => bail!("No matched ICE reply or selected direct pair during the lightweight window"),
    }
}

pub(super) async fn wait_full_connected(
    pc: &mut WebRTCStream,
    ms: u64,
    mut status: watch::Receiver<PunchStatus>,
) -> Option<ResultType<()>> {
    let probe = pc.clone();
    let exhausted = async {
        let reported = status
            .wait_for(|status| {
                status.full.is_some_and(|sample| sample.empty_pool)
                    || status.full_peer.is_some_and(|sample| sample.empty_pool)
            })
            .await
            .is_ok();
        if !reported || !ice_has_no_confirmed_path(&probe).await {
            pending::<()>().await;
        }
    };
    tokio::select! {
        biased;
        connected = pc.wait_connected(ms) => Some(connected),
        _ = exhausted => None,
    }
}
