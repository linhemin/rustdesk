use hbb_common::tokio::time::{Duration, Instant};
use std::sync::{Arc, OnceLock};

const REFRESH_AT: [Duration; 2] = [Duration::from_secs(3), Duration::from_secs(10)];

#[derive(Default)]
pub(super) struct FirstImage {
    waiting: Option<(Instant, i32)>,
    retries: usize,
    pub(super) submitted: Arc<OnceLock<Instant>>,
    #[cfg(all(target_os = "ios", feature = "p2p-remote-diagnostics"))]
    pub(super) received: Option<Instant>,
}

impl FirstImage {
    pub(super) fn wait(&mut self, display: i32) {
        self.waiting = Some((Instant::now(), display));
    }

    pub(super) fn refresh_due(&mut self, now: Instant) -> Option<i32> {
        if self.submitted.get().is_some() {
            return None;
        }
        let (since, display) = self.waiting?;
        if now.duration_since(since) < *REFRESH_AT.get(self.retries)? {
            return None;
        }
        self.retries += 1;
        Some(display)
    }

    #[cfg(all(target_os = "ios", feature = "p2p-remote-diagnostics"))]
    pub(super) fn append_report(&self, report: &mut String) {
        let Some((since, _)) = self.waiting else {
            return;
        };
        let relative = |at: Option<Instant>| {
            at.map_or_else(
                || "pending".to_owned(),
                |at| at.saturating_duration_since(since).as_millis().to_string(),
            )
        };
        report.push_str(&format!(
            "\nvideo_startup elapsed_ms={} first_packet_ms={} first_submitted_ms={} refreshes={}",
            since.elapsed().as_millis(),
            relative(self.received),
            relative(self.submitted.get().copied()),
            self.retries,
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn startup_refresh_is_bounded_and_stops_when_an_image_is_submitted() {
        let now = Instant::now();
        let mut image = FirstImage {
            waiting: Some((now, 2)),
            ..Default::default()
        };
        assert_eq!(image.refresh_due(now + Duration::from_secs(2)), None);
        assert_eq!(image.refresh_due(now + Duration::from_secs(3)), Some(2));
        assert_eq!(image.refresh_due(now + Duration::from_secs(9)), None);
        assert_eq!(image.refresh_due(now + Duration::from_secs(10)), Some(2));
        assert_eq!(image.refresh_due(now + Duration::from_secs(30)), None);

        let mut image = FirstImage {
            waiting: Some((now, 2)),
            ..Default::default()
        };
        image.submitted.set(now).unwrap();
        assert_eq!(image.refresh_due(now + Duration::from_secs(3)), None);
    }
}
