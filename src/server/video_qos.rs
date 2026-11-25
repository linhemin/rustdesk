use super::*;
use base::config::keys::{CUSTOM_BITRATE_AUTO_FLAG, MAX_VIDEO_BITRATE_KBPS, MIN_VIDEO_BITRATE_KBPS};
use scrap::codec::{BitrateModel, Quality, BR_BALANCED, BR_BEST, BR_SPEED};
use std::{
    collections::VecDeque,
    time::{Duration, Instant},
};

/*
FPS adjust:
a. new user connected => set to INIT_FPS
b. TestDelay reply => update the user's fps from the excess delay, the reply's delay
   above the baseline this connection has shown so far:
     startup: two consecutive replies with excess < 50 ms permit doubling toward
       the viewer's cap; a higher excess or a brake ends this acceleration;
     excess < DELAY_THRESHOLD_150MS: a good reply; grows the fps, and after a
       reduction returns to the level held before it after two good replies;
     excess >= DELAY_THRESHOLD_150MS: a bad reply; nothing happens until three in a
       row confirm congestion, including after each reduction. FPS drops by a
       fifth at most; a second of excess cannot wait and halves it immediately.
       A recent fast restore also permits halving at 600 ms of excess.
   While the bitrate can still be reduced (ABR) it is reduced first and the fps keeps
   a floor: bitrate-targeted encoders do not send fewer bytes at fewer frames.
c. probe outstanding for more than two seconds => halve the fps for every further
   second, down to MIN_AUTO_FPS and never above the target it found; the late
   reply does not reduce again. Automatic reductions respect this floor unless
   the viewer requested a lower FPS cap.
d. second timeout / TestDelay reply => real fps is the minimum over all users;
   every user starts at INIT_FPS, adapts from its own target and is capped by its
   own limit, never by that minimum or by another user's limit

ratio adjust:
a. user set image quality => update to the maximum ratio of the latest quality
b. 3 seconds timeout => update ratio according to network delay
    When network delay < DELAY_THRESHOLD_150MS, increase ratio, max 150kbps;
    When a user calls for a reduction (two bad replies in a row, or a probe still
    out at the second tick past two seconds), decrease ratio by the step that user's
    own delay and confirmation call for, the most conservative step over all users;
    one slow reply or one short stall does not, and one user's spike is never paired
    with another user's confirmation.
c. confirmed congestion => decrease ratio at once, when the 3 seconds cooldown allows

delay:
    TestDelay shares the video stream, so it measures the queue in front of it rather
    than the path RTT. The baseline starts at the first reply and follows lower
    delays immediately. Old minima expire after 20 fresh replies; a higher window
    minimum is learned gradually only when the recent floor is no longer rising.
    Outstanding-probe checks and their late replies do not age this window.
*/

// Constants
pub const FPS: u32 = 30;
pub const MIN_FPS: u32 = 1;
pub const MAX_FPS: u32 = 120;
pub const INIT_FPS: u32 = 15;
const MIN_AUTO_FPS: u32 = 5;

// Bitrate ratio constants for different quality levels
const BR_MAX: f32 = 40.0; // 2000 * 2 / 100
const BR_MIN: f32 = 0.2;
const BR_MIN_HIGH_RESOLUTION: f32 = 0.1; // For high resolution, BR_MIN is still too high, so we set a lower limit
const MAX_BR_MULTIPLE: f32 = 1.0;

const HISTORY_DELAY_LEN: usize = 2;
const ADJUST_RATIO_INTERVAL: usize = 3; // Adjust quality ratio every 3 seconds
const DYNAMIC_SCREEN_THRESHOLD: usize = 2; // Allow increase quality ratio if encode more than 2 times in one second
const FAST_GROWTH_BELOW_KBPS: u32 = 8_000;
const DELAY_THRESHOLD_150MS: u32 = 150; // 150ms is the threshold for good network condition
const RESTORE_GUARD_SAMPLES: u8 = 5; // A restored level that congests this soon is lowered

#[derive(Default, Debug, Clone)]
struct UserDelay {
    stall_ticks: u8, // timer ticks the outstanding probe has been out beyond two seconds
    delay_history: VecDeque<u32>,
    fps: Option<u32>,
    rtt_calculator: RttCalculator,
    quick_increase_fps_count: usize,
    increase_fps_count: usize,
    consecutive_bad_samples: usize,
    fps_bad_samples: u8, // fresh bad replies since the last FPS reduction
    good_samples: usize, // since the last reduction, capped at 3
    replies_after_bitrate_reduction: Option<u8>,
    fps_before_congestion: Option<u32>, // level to return to once replies are good again
    samples_since_restore: Option<u8>,  // set by a restore, cleared once it proved stable
    stall_reference_fps: Option<u32>,   // fps when the outstanding probe passed two seconds
    startup_good_samples: u8,           // u8::MAX permanently ends startup acceleration
}

impl UserDelay {
    fn add_delay(&mut self, delay: u32) {
        if self.delay_history.len() >= HISTORY_DELAY_LEN {
            self.delay_history.pop_front();
        }
        self.delay_history.push_back(delay);
    }

    fn limit_fps_change(
        &mut self,
        current_fps: u32,
        fps: u32,
        delay: u32,
        bitrate_first: bool,
        braked: bool,
    ) -> u32 {
        // A spike stays in the average for several samples; confirm congestion with fresh samples.
        let delay = delay.saturating_sub(self.rtt_calculator.get_rtt().unwrap_or_default());
        if let Some(samples) = self.samples_since_restore.as_mut() {
            *samples = samples.saturating_add(1);
        }
        if delay < DELAY_THRESHOLD_150MS {
            self.consecutive_bad_samples = 0;
            self.fps_bad_samples = 0;
            self.replies_after_bitrate_reduction = None;
            self.good_samples = (self.good_samples + 1).min(3);
            return self.recover(current_fps, fps);
        }
        self.consecutive_bad_samples = (self.consecutive_bad_samples + 1).min(3);
        self.fps_bad_samples = (self.fps_bad_samples + 1).min(3);
        if let Some(replies) = self.replies_after_bitrate_reduction.as_mut() {
            *replies = (*replies + 1).min(2);
        }
        let failed_restore = delay >= 600
            && self
                .samples_since_restore
                .is_some_and(|samples| samples <= RESTORE_GUARD_SAMPLES);
        // A level that congests right after being restored is not the level to return to.
        if self
            .samples_since_restore
            .is_some_and(|samples| samples <= RESTORE_GUARD_SAMPLES)
            && (failed_restore || self.consecutive_bad_samples >= 3)
        {
            self.fps_before_congestion = Some(current_fps - current_fps / 4);
            self.samples_since_restore = None;
        }
        // The timeout brake already reduced for the probe this reply answers.
        if fps >= current_fps || braked {
            return current_fps;
        }
        // An extra second of delay cannot wait for another confirmation.
        if !failed_restore
            && delay < 1000
            && (self.fps_bad_samples < 3
                || (bitrate_first && self.replies_after_bitrate_reduction.unwrap_or_default() < 2))
        {
            return current_fps;
        }
        // A fast restore probes capacity. Roll it back promptly if the queue grows
        // again, rather than waiting through another ordinary confirmation window.
        let divisor = if delay >= 1000 || failed_restore {
            2
        } else {
            5
        };
        self.on_reduction(current_fps);
        fps.max(current_fps.saturating_sub((current_fps / divisor).max(1)))
    }

    // Fresh low-delay replies permit recovery even while the average contains a spike:
    // a little at first, then back to the level held before congestion.
    fn recover(&mut self, current_fps: u32, fps: u32) -> u32 {
        let gradual = current_fps + (current_fps / 10).max(1);
        let level = self
            .fps_before_congestion
            .filter(|level| *level > current_fps);
        match (self.good_samples, level) {
            (2 | 3, Some(level)) => {
                self.fps_before_congestion = None;
                self.samples_since_restore = Some(0);
                fps.max(level)
            }
            (3, None) => {
                self.fps_before_congestion = None;
                fps.max(current_fps + (current_fps / 5).max(2))
            }
            _ => gradual,
        }
    }

    fn accelerate_startup(
        &mut self,
        current_fps: u32,
        fps: u32,
        cap: u32,
        delay: u32,
        braked: bool,
    ) -> u32 {
        if self.startup_good_samples == u8::MAX {
            return fps;
        }
        let excess = delay.saturating_sub(self.rtt_calculator.get_rtt().unwrap_or_default());
        // A low-load sample does not establish capacity: require two clean replies
        // per step and abandon startup probing on the first sign of queue growth.
        if braked || excess >= 50 || current_fps >= cap {
            self.startup_good_samples = u8::MAX;
            return fps;
        }
        self.startup_good_samples += 1;
        if self.startup_good_samples < 2 {
            return fps;
        }
        self.startup_good_samples = 0;
        let accelerated = fps.max(current_fps.saturating_mul(2)).min(cap);
        if accelerated >= cap {
            self.startup_good_samples = u8::MAX;
        }
        accelerated
    }

    // The first reduction of an episode remembers the level to return to.
    fn on_reduction(&mut self, current_fps: u32) {
        self.startup_good_samples = u8::MAX;
        self.good_samples = 0;
        self.fps_bad_samples = 0;
        if self.fps_before_congestion.is_none() {
            self.fps_before_congestion = Some(current_fps);
        }
    }

    // Bitrate is cut on confirmation only: two bad replies in a row, or a probe still
    // outstanding at the second tick past two seconds.  One slow reply or one short
    // stall is jitter, and a static screen would never earn the cut back.
    fn needs_bitrate_reduction(&self) -> bool {
        self.consecutive_bad_samples >= 2 || self.stall_ticks >= 2
    }

    // The bitrate step this viewer's own evidence calls for, None when it calls for
    // none.  Severity and confirmation come from the same viewer; the controller
    // never pairs one viewer's spike with another viewer's confirmation.
    fn ratio_reduction(&self) -> Option<f32> {
        if !self.needs_bitrate_reduction() {
            return None;
        }
        let excess = self.avg_delay();
        let confirmed = self.consecutive_bad_samples >= 3;
        Some(if excess < 200 {
            0.95
        } else if excess < 300 {
            0.9
        } else if excess < 500 {
            if confirmed {
                0.7
            } else {
                0.85
            }
        } else if confirmed {
            0.5
        } else {
            0.8
        })
    }

    // Average delay above the baseline: what the queue adds on top of the path itself.
    fn avg_delay(&self) -> u32 {
        if self.delay_history.is_empty() {
            return DELAY_THRESHOLD_150MS;
        }
        let avg_delay = self.delay_history.iter().sum::<u32>() / self.delay_history.len() as u32;
        avg_delay.saturating_sub(self.rtt_calculator.get_rtt().unwrap_or_default())
    }
}

// User session data structure
#[derive(Default, Debug, Clone)]
struct UserData {
    auto_adjust_fps: Option<u32>,
    custom_fps: Option<u32>,
    fixed_screen_fps: Option<u32>,
    quality: Option<(i64, Quality)>, // (time, quality)
    bitrate_limit_kbps: Option<u32>,
    delay: UserDelay,
    record: bool,
    delivery: VecDeque<DeliverySample>,
    send_pressure: Option<Instant>,
    probe_blocked_until: Option<Instant>,
    joined_at: Option<Instant>, // set by on_connection_open; the start-up guard's clock
}

impl UserData {
    fn has_clear_video_path(&self, now: Instant) -> bool {
        self.delay.stall_ticks == 0
            && self.delay.good_samples >= 2
            && self.delay.avg_delay() < 24
            && !self.probe_blocked_until.is_some_and(|until| now < until)
            && self.delivery.iter().all(|sample| {
                now.saturating_duration_since(sample.at) > Duration::from_secs(5) || sample.queued < 6
            })
    }

    // The frame rate this viewer asked for, from its custom or auto-adjust limit.
    fn fps_cap(&self, apply_decoder_limit: bool) -> u32 {
        let fps = self.custom_fps.unwrap_or(FPS);
        if apply_decoder_limit {
            return self.auto_adjust_fps.unwrap_or(fps).min(fps).clamp(MIN_FPS, MAX_FPS);
        }
        fps.clamp(MIN_FPS, MAX_FPS)
    }
}

#[derive(Debug, Clone, Copy)]
struct DeliverySample {
    at: Instant,
    kbps: u32,
    fps: u32,
    queued: u32,
}

#[derive(Debug, Clone, Copy)]
struct AutoFrameSample {
    at: Instant,
    min_fps: u32,
    on_target: bool,
    headroom: bool,
    overloaded: bool,
}

#[derive(Default, Debug, Clone)]
struct DisplayData {
    send_counter: usize, // Number of times encode during period
    support_changing_quality: bool,
    gpu_texture_encode: bool,
    auto_frames: Option<AutoFrameSample>,
    bitrate_model: Option<BitrateModel>,
}

#[derive(Default)]
struct BitrateRecovery {
    previous_ratio: Option<f32>,
    encoder_blocked_until: Option<Instant>,
    auto_trial_from: Option<(f32, u32)>,
    auto_retry: Option<(Instant, u8)>,
    capped_failure: Option<(f32, Instant)>,
}

impl BitrateRecovery {
    fn remember_reduction(&mut self, before: f32, after: f32) {
        if after < before {
            self.previous_ratio = Some(self.previous_ratio.unwrap_or(before).max(before));
        }
    }

    fn encoder_ready(&self, now: Instant) -> bool {
        !self.encoder_blocked_until.is_some_and(|until| now < until)
    }

    fn capped_probe_target(&self, current: f32, target: f32, now: Instant) -> f32 {
        let Some((failed, _)) = self.capped_failure.filter(|(_, until)| now < *until) else {
            return target;
        };
        let upper = target.min(failed);
        if upper <= current * 1.02 {
            current
        } else {
            current + (upper - current) * 0.5
        }
    }

    fn fast_uncapped_growth(&self, now: Instant) -> bool {
        self.auto_retry.is_none_or(|(retry_at, _)| {
            now.saturating_duration_since(retry_at) >= Duration::from_secs(15)
        })
    }
}

// Main QoS controller structure
pub struct VideoQoS {
    fps: u32,
    ratio: f32,
    users: HashMap<i32, UserData>,
    displays: HashMap<String, DisplayData>,
    bitrate_store: u32,
    adjust_ratio_instant: Instant,
    bitrate_recovery: BitrateRecovery,
    applied_bitrate_target: Option<(u32, f32)>,
    abr_config: bool,
    first_reply_adjusts_ratio: bool, // false on Linux, where it can create vaapi twice
    #[cfg(test)]
    test_now: Option<Instant>,
}

impl Default for VideoQoS {
    fn default() -> Self {
        VideoQoS {
            fps: FPS,
            ratio: BR_BALANCED,
            users: Default::default(),
            displays: Default::default(),
            bitrate_store: 0,
            adjust_ratio_instant: Instant::now(),
            bitrate_recovery: BitrateRecovery::default(),
            applied_bitrate_target: None,
            abr_config: true,
            first_reply_adjusts_ratio: !cfg!(target_os = "linux"),
            #[cfg(test)]
            test_now: None,
        }
    }
}

// Clock; tests drive a virtual clock so timing is deterministic.
impl VideoQoS {
    fn now(&self) -> Instant {
        #[cfg(test)]
        if let Some(now) = self.test_now {
            return now;
        }
        Instant::now()
    }

    fn since(&self, instant: Instant) -> Duration {
        self.now().saturating_duration_since(instant)
    }

    #[cfg(test)]
    fn advance_ms(&mut self, ms: u64) {
        self.test_now = Some(self.now() + Duration::from_millis(ms));
    }
}

// Basic functionality
impl VideoQoS {
    // Calculate seconds per frame based on current FPS
    pub fn spf(&self) -> Duration {
        Duration::from_secs_f32(1. / (self.fps() as f32))
    }

    // Get current FPS within valid range
    pub fn fps(&self) -> u32 {
        if let Some(target) = self.fixed_target() {
            return target;
        }
        let fps = self.fps;
        if fps >= MIN_FPS && fps <= MAX_FPS {
            fps
        } else {
            FPS
        }
    }

    // Store bitrate for later use
    pub fn store_bitrate(&mut self, bitrate: u32) {
        self.bitrate_store = bitrate;
    }

    // Get stored bitrate
    pub fn bitrate(&self) -> u32 {
        self.bitrate_store
    }

    pub(super) fn back_off_encoder_bitrate(&mut self) {
        if self.displays.len() != 1 || !self.in_vbr_state() || !self.latest_quality().is_custom() {
            return;
        }
        if self.latest_quality() == Quality::Auto {
            self.back_off_auto_bitrate(0.85);
            return;
        }
        let current = self.ratio();
        let now = self.now();
        self.bitrate_recovery.encoder_blocked_until = Some(now + Duration::from_secs(2));
        let encoder_floor = Quality::Auto.ratio().max(self.min_ratio());
        let next = (current * 0.75).max(encoder_floor);
        if next < current {
            self.bitrate_recovery.remember_reduction(current, next);
            self.ratio = next;
            self.adjust_ratio_instant = now;
            hbb_common::throttled_log!(
                Duration::from_secs(5),
                debug,
                "video encoder missed frame budget, quality ratio {current:.3} -> {next:.3}"
            );
        }
    }

    fn back_off_auto_bitrate(&mut self, factor: f32) {
        let now = self.now();
        if self.latest_quality() != Quality::Auto
            || self.displays.len() != 1
            || !self.in_vbr_state()
            || !self.bitrate_recovery.encoder_ready(now)
        {
            return;
        }
        let before = self.ratio;
        let capped = self.requested_bitrate_limit().is_some();
        let factor = if capped { factor.min(0.75) } else { factor };
        let next = self
            .bitrate_recovery
            .auto_trial_from
            .take()
            .map_or(before * factor, |(stable, _)| stable)
            .max(self.min_ratio());
        if next >= before {
            return;
        }
        let failures = self
            .bitrate_recovery
            .auto_retry
            .filter(|(retry_at, _)| now.saturating_duration_since(*retry_at) < Duration::from_secs(15))
            .map_or(0, |(_, n)| (n + 1).min(2));
        if capped {
            let failed = self
                .bitrate_recovery
                .capped_failure
                .filter(|(_, until)| now < *until)
                .map_or(before, |(recent, _)| recent.min(before));
            self.bitrate_recovery.capped_failure = Some((failed, now + Duration::from_secs(24)));
        }
        // Repeated failures extend the pause, with a finite retry after a scene change.
        let retry_seconds = if capped { 4 } else { 6 };
        self.bitrate_recovery.auto_retry =
            Some((now + Duration::from_secs(retry_seconds << failures), failures));
        self.bitrate_recovery.encoder_blocked_until = Some(now + Duration::from_secs(2));
        self.bitrate_recovery.previous_ratio = None;
        self.ratio = next;
        self.adjust_ratio_instant = now;
        for user in self.users.values_mut() {
            user.delivery.clear();
            if user.delay.needs_bitrate_reduction()
                && user.delay.replies_after_bitrate_reduction.is_none()
            {
                user.delay.replies_after_bitrate_reduction = Some(0);
            }
        }
        self.reset_send_counters();
        log::trace!("auto video bitrate backed off from {before:.3} to {next:.3}");
    }

    pub(super) fn observe_auto_frames(
        &mut self,
        name: &str,
        min_fps: u32,
        on_target: bool,
        headroom: bool,
        overloaded: bool,
    ) {
        let now = self.now();
        if let Some(display) = self.displays.get_mut(name) {
            let sustained = overloaded
                && display.auto_frames.is_some_and(|previous| {
                    previous.overloaded
                        && now.saturating_duration_since(previous.at) < Duration::from_secs(3)
                });
            display.auto_frames = Some(AutoFrameSample {
                at: now,
                min_fps,
                on_target,
                headroom,
                overloaded,
            });
            if sustained {
                self.back_off_auto_bitrate(0.85);
            }
        }
    }

    fn auto_frame_sample(&self, now: Instant) -> Option<AutoFrameSample> {
        let sample = self.displays.values().next()?.auto_frames?;
        (now.saturating_duration_since(sample.at) < Duration::from_secs(3)).then_some(sample)
    }

    pub(super) fn auto_target_fps(&self) -> u32 {
        self.fixed_target().unwrap_or_else(|| {
            self.users
                .values()
                .map(|user| user.custom_fps.unwrap_or(FPS))
                .min()
                .unwrap_or(FPS)
        })
    }

    pub(super) fn observe_video_send_pressure(&mut self, id: i32, pressured: bool) {
        let now = self.now();
        let Some(user) = self.users.get_mut(&id) else {
            return;
        };
        let sustained = pressured
            && user
                .send_pressure
                .is_some_and(|at| now.saturating_duration_since(at) < Duration::from_secs(3));
        user.send_pressure = pressured.then_some(now);
        if sustained {
            self.back_off_auto_bitrate(0.85);
        }
    }

    // Get current bitrate ratio with bounds checking
    pub fn ratio(&mut self) -> f32 {
        let quality = self.latest_quality();
        let cap = self.custom_bitrate_cap().unwrap_or(f32::MAX);
        if let Some(kbps) = self.requested_bitrate_limit().filter(|_| quality == Quality::Auto) {
            if self
                .displays
                .values()
                .any(|display| display.bitrate_model.is_some())
            {
                if self.applied_bitrate_target.is_none_or(|(previous, old_cap)| {
                    previous != kbps || self.ratio >= old_cap
                }) {
                    self.ratio = cap;
                }
                self.applied_bitrate_target = Some((kbps, cap));
            }
        } else {
            self.applied_bitrate_target = None;
        }
        if !self.ratio.is_finite()
            || self.ratio < BR_MIN_HIGH_RESOLUTION.min(cap)
            || (quality != Quality::Auto && self.ratio > BR_MAX)
        {
            self.ratio = BR_BALANCED;
        }
        self.ratio = self.ratio.min(cap);
        self.ratio
    }

    // Check if any user is in recording mode
    pub fn record(&self) -> bool {
        self.users.iter().any(|u| u.1.record)
    }

    pub fn set_support_changing_quality(&mut self, video_service_name: &str, support: bool) {
        if let Some(display) = self.displays.get_mut(video_service_name) {
            display.support_changing_quality = support;
        }
    }

    // Check if variable bitrate encoding is supported and enabled
    pub fn in_vbr_state(&self) -> bool {
        // A single frame-priority stream can apply a new rate at encoder recreation.
        self.abr_config
            && (self.displays.values().all(|display| display.support_changing_quality)
                || (self.displays.len() == 1 && self.latest_quality() == Quality::Auto))
    }
}

// User session management
impl VideoQoS {
    // Initialize new user session
    pub fn on_connection_open(&mut self, id: i32) {
        if self.requested_bitrate_limit().is_none() {
            self.bitrate_recovery = BitrateRecovery::default();
            if self.latest_quality() == Quality::Auto {
                self.ratio = self.ratio.min(Quality::Auto.ratio());
            }
        }
        let user = UserData {
            joined_at: Some(self.now()),
            ..Default::default()
        };
        self.users.insert(id, user);
        self.abr_config = Config::get_option("enable-abr") != "N";
    }

    // Clean up user session
    pub fn on_connection_close(&mut self, id: i32) {
        let previous_limit = self.requested_bitrate_limit();
        self.users.remove(&id);
        if self.users.is_empty() {
            *self = Default::default();
            return;
        }
        if previous_limit.is_none() || previous_limit != self.requested_bitrate_limit() {
            self.bitrate_recovery = BitrateRecovery::default();
        }
        // The stream follows the remaining viewers at once; a departed viewer's
        // start-up guard left with its entry.
        self.adjust_fps();
    }

    pub fn set_fixed_screen_fps(&mut self, id: i32, request: i32) {
        let target = match request {
            -1 => None,
            15..=120 => Some(request as u32),
            _ => return,
        };
        if let Some(user) = self.users.get_mut(&id) {
            user.fixed_screen_fps = target;
            self.adjust_fps();
        }
    }

    pub fn fixed_target(&self) -> Option<u32> {
        let mut users = self.users.values();
        let initial = users.next()?.fixed_screen_fps?;
        users.try_fold(initial, |lowest, user| user.fixed_screen_fps.map(|fps| fps.min(lowest)))
    }

    pub fn set_gpu_texture_encode(&mut self, name: &str, enabled: bool) {
        if let Some(display) = self.displays.get_mut(name) {
            display.gpu_texture_encode = enabled;
        }
    }

    pub fn gpu_texture_encode(&self) -> bool {
        !self.displays.is_empty() && self.displays.values().all(|display| display.gpu_texture_encode)
    }

    pub fn user_custom_fps(&mut self, id: i32, fps: u32) {
        if fps < MIN_FPS || fps > MAX_FPS {
            return;
        }
        if let Some(user) = self.users.get_mut(&id) {
            user.custom_fps = Some(fps);
            user.auto_adjust_fps = None;
        }
    }

    pub fn user_auto_adjust_fps(&mut self, id: i32, fps: u32) {
        if fps < MIN_FPS || fps > MAX_FPS {
            return;
        }
        if let Some(user) = self.users.get_mut(&id) {
            user.auto_adjust_fps = Some(fps);
        }
    }

    #[cfg(test)]
    fn user_image_quality(&mut self, id: i32, image_quality: i32) {
        self.user_image_quality_with_limit(id, image_quality, 0);
    }

    pub fn user_image_quality_with_limit(&mut self, id: i32, image_quality: i32, kbps: u32) {
        let convert_quality = |q: i32| -> Quality {
            if q == ImageQuality::Balanced.value() {
                Quality::Balanced
            } else if q == ImageQuality::Low.value() {
                Quality::Low
            } else if q == ImageQuality::Best.value() {
                Quality::Best
            } else if q & CUSTOM_BITRATE_AUTO_FLAG != 0 {
                Quality::Auto
            } else {
                let b = ((q >> 8 & 0xFFF) * 2) as f32 / 100.0;
                Quality::Custom(b.clamp(BR_MIN, BR_MAX))
            }
        };

        let limit = (MIN_VIDEO_BITRATE_KBPS..=MAX_VIDEO_BITRATE_KBPS)
            .contains(&kbps)
            .then_some(kbps);
        let quality = if limit.is_some() {
            Quality::Auto
        } else {
            convert_quality(image_quality)
        };
        let previous = self.latest_quality();
        let previous_limit = self.requested_bitrate_limit();
        if let Some(user) = self.users.get_mut(&id) {
            let had_quality = user.quality.is_some();
            user.bitrate_limit_kbps = limit;
            user.quality = Some((hbb_common::get_time(), quality));
            let latest = self.latest_quality();
            let limit_changed = previous_limit != self.requested_bitrate_limit();
            if previous != latest || limit_changed {
                self.bitrate_recovery = BitrateRecovery::default();
                self.applied_bitrate_target = None;
                if limit_changed && latest == Quality::Auto {
                    for viewer in self.users.values_mut() {
                        viewer.delivery.clear();
                    }
                }
            }
            if !(had_quality && quality == Quality::Auto && latest == Quality::Auto) {
                self.ratio = latest.ratio();
            }
        }
    }

    pub fn user_record(&mut self, id: i32, v: bool) {
        if let Some(user) = self.users.get_mut(&id) {
            user.record = v;
        }
    }

    pub fn user_video_delivery(&mut self, id: i32, kbps: u32, fps: u32, queued: u32) {
        let now = self.now();
        let target = self.bitrate();
        let quality = self.latest_quality();
        let adaptive_custom = quality.is_custom();
        let floor_adaptation = self.displays.len() == 1
            && self.in_vbr_state()
            && (quality == Quality::Best || adaptive_custom)
            && target > 0
            && (!adaptive_custom || self.since(self.adjust_ratio_instant).as_secs() >= 1);
        let min_ratio = self.min_ratio();
        let mut pressure = false;
        let auto = quality == Quality::Auto && self.displays.len() == 1;
        let capped = auto && self.requested_bitrate_limit().is_some();
        let mut backoff_factor = 0.85;
        let sender = auto.then(|| self.auto_frame_sample(now)).flatten();
        // An actual video sample with less than one frame per second rounds to
        // zero FPS. Empty windows also report zero delivered bitrate.
        let min_fps = if adaptive_custom { 0 } else { 6 };
        if let Some(user) = self.users.get_mut(&id) {
            if !(min_fps..=1000).contains(&fps) || !(1..=1_000_000).contains(&kbps) || queued > 100
            {
                user.delivery.clear();
                return;
            }
            if user.delivery.back().is_some_and(|sample| {
                now.saturating_duration_since(sample.at) > Duration::from_secs(5)
            }) {
                user.delivery.clear();
            }
            if user.delivery.len() == 3 {
                user.delivery.pop_front();
            }
            user.delivery.push_back(DeliverySample {
                at: now,
                kbps,
                fps,
                queued,
            });
            pressure = auto
                && user
                    .delivery
                    .iter()
                    .rev()
                    .take(2)
                    .filter(|sample| {
                        now.saturating_duration_since(sample.at) < Duration::from_secs(3)
                            && (sample.queued >= 6 || sender.is_some_and(|sent| {
                                sent.on_target && sample.fps < sent.min_fps
                            }))
                    })
                    .count()
                    == 2;
            if capped && pressure && target > 0 && queued >= 6 {
                if let Some(previous) = user
                    .delivery
                    .iter()
                    .rev()
                    .nth(1)
                    .filter(|sample| sample.queued >= 6)
                {
                    let rate = kbps.min(previous.kbps);
                    backoff_factor = (rate as f32 * 1.10 / target as f32).clamp(0.40, 0.85);
                }
            }
            if !pressure && floor_adaptation && user.delivery.len() == 3 {
                let oldest_queue = user.delivery[0].queued;
                let previous_queue = user.delivery[1].queued;
                let delivery_floor = user
                    .delivery
                    .iter()
                    .map(|sample| sample.kbps)
                    .min()
                    .unwrap_or(target);
                // A low delivered rate alone is common on a still desktop. Act only
                // when active samples also show that the receiver is falling behind.
                if previous_queue >= oldest_queue
                    && queued >= previous_queue.saturating_add(3)
                    && queued >= 6
                    && kbps < target.saturating_mul(4) / 5
                    && user.delay.avg_delay() >= 24
                {
                    pressure = auto;
                    if !pressure {
                        let factor =
                            (delivery_floor as f32 * 1.10 / target as f32).clamp(0.55, 0.85);
                        let next = (self.ratio * factor).max(min_ratio);
                        if adaptive_custom {
                            self.bitrate_recovery.remember_reduction(self.ratio, next);
                            self.adjust_ratio_instant = now;
                        }
                        self.ratio = next;
                    }
                    let until = now + Duration::from_secs(6);
                    user.probe_blocked_until =
                        Some(user.probe_blocked_until.map_or(until, |old| old.max(until)));
                    user.delivery.clear();
                }
            }
        }
        if pressure {
            self.back_off_auto_bitrate(backoff_factor);
        }
    }

    // Three fresh samples confirm the receiver has kept up. In frame-priority mode only
    // the newest rate is compared to the target, which may have changed each second.
    fn delivery_growth_budget(&self, target_kbps: u32) -> (u32, bool) {
        let now = self.now();
        if target_kbps == 0 || self.users.is_empty() || self.displays.len() != 1 {
            return (150, false);
        }
        let frame_priority = self.latest_quality() == Quality::Auto;
        let min_fps = if frame_priority {
            let Some(sender) = self.auto_frame_sample(now).filter(|sample| sample.headroom) else {
                return (150, false);
            };
            sender.min_fps
        } else {
            0
        };
        let mut floor = u32::MAX;
        let mut complete = true;
        let max_age = Duration::from_secs(if frame_priority { 5 } else { 7 });
        for viewer in self.users.values() {
            if viewer.delivery.len() != 3
                || viewer
                    .delivery
                    .iter()
                    .any(|sample| now.saturating_duration_since(sample.at) > max_age)
            {
                complete = false;
                continue;
            }
            if viewer
                .delivery
                .iter()
                .filter(|sample| sample.queued >= 25)
                .count()
                >= 2
            {
                return (0, false);
            }
            if viewer
                .probe_blocked_until
                .is_some_and(|deadline| now < deadline)
            {
                complete = false;
            }
            if frame_priority
                && viewer
                    .delivery
                    .iter()
                    .any(|sample| sample.queued >= 6 || sample.fps < min_fps)
            {
                complete = false;
            }
            let delivered = if frame_priority {
                viewer.delivery.back().map(|sample| sample.kbps)
            } else {
                viewer.delivery.iter().map(|sample| sample.kbps).min()
            };
            floor = floor.min(delivered.unwrap_or(0));
        }
        if !complete {
            return (150, false);
        }
        if frame_priority && self.requested_bitrate_limit().is_some() {
            return (0, true);
        }
        if floor < target_kbps.saturating_mul(8) / 10 {
            // A clean, moving desktop can undershoot the encoder target. Probe gently
            // without treating unused encoder budget as evidence of lost bandwidth.
            if frame_priority && floor >= target_kbps.div_ceil(8) {
                return ((target_kbps / 10).clamp(150, 600), true);
            }
            return (150, false);
        }
        if frame_priority {
            if target_kbps < FAST_GROWTH_BELOW_KBPS {
                let room = FAST_GROWTH_BELOW_KBPS - target_kbps;
                return ((floor / 2).max(150).min(room), true);
            }
            let strong_delivery = floor >= target_kbps.saturating_mul(9) / 10;
            let (divisor, max_step) =
                if strong_delivery && self.bitrate_recovery.fast_uncapped_growth(now) {
                    (5, 10_000)
                } else {
                    (10, 5_000)
                };
            return ((floor / divisor).clamp(150, max_step), true);
        }
        ((floor / 10).clamp(150, 1200), true)
    }

    fn can_recover_bitrate(&self) -> bool {
        let now = self.now();
        self.displays.len() == 1
            && self.video_path_ready(now)
            && self.users.values().all(|viewer| {
                viewer.delivery.iter().filter(|sample| {
                    now.saturating_duration_since(sample.at) <= Duration::from_secs(5)
                }).count() >= 2
            })
    }

    fn video_path_ready(&self, now: Instant) -> bool {
        !self.users.is_empty()
            && self.bitrate_recovery.encoder_ready(now)
            && self.users.values().all(|viewer| viewer.has_clear_video_path(now))
    }

    fn bitrate_recovery_target(&self, quality: Quality, custom_cap: f32) -> f32 {
        let base = quality.ratio() * MAX_BR_MULTIPLE;
        let target = if quality == Quality::Auto {
            self.ratio
        } else {
            base
        };
        target.min(custom_cap)
    }

    pub(super) fn settled_quality_ready(&self, waiting: Duration) -> bool {
        let quality = self.latest_quality();
        quality.is_custom()
            && self.video_path_ready(self.now())
            && (waiting >= Duration::from_secs(3)
                || self.ratio >= self.bitrate_recovery_target(
                    quality,
                    self.custom_bitrate_cap().unwrap_or(f32::MAX),
                ))
    }

    pub fn user_network_delay(&mut self, id: i32, delay: u32) {
        let quality = self.latest_quality();
        let target_ratio = quality.ratio();
        // Fewer frames only save bytes with encoders that size frames for a fixed rate;
        // bitrate-targeted encoders keep the bitrate, so the bitrate has to come down first.
        let bitrate_first = self.can_reduce_bitrate();
        let apply_decoder_limit =
            quality != Quality::Auto || self.displays.len() != 1 || !bitrate_first;

        // For bad network, small fps means quick reaction and high quality
        let (min_fps, normal_fps) = if target_ratio >= BR_BEST {
            (8, 16)
        } else if target_ratio >= BR_BALANCED {
            (10, 20)
        } else {
            (12, 24)
        };

        // Calculate minimum acceptable delay-fps product
        let dividend_ms = DELAY_THRESHOLD_150MS * min_fps;

        let mut adjust_ratio = false;
        let mut reduce_bitrate = false;
        let mut auto_pressure = false;
        let now = self.now();
        let enhanced_best = self.abr_config && quality == Quality::Best;
        if let Some(user) = self.users.get_mut(&id) {
            let delay = delay.max(10);
            // The reply closes the outstanding probe, braked or not.
            user.delay.stall_ticks = 0;
            let braked = user.delay.stall_reference_fps.take().is_some();
            let old_avg_delay = user.delay.avg_delay();
            if !braked {
                user.delay.rtt_calculator.update(delay);
            }
            // A trial above the normal ceiling must not wait for the ordinary
            // congestion brake. Queuing is measurable before frames start dropping.
            let queue_ms = delay.saturating_sub(user.delay.rtt_calculator.get_rtt().unwrap_or(delay));
            auto_pressure = quality == Quality::Auto
                && (braked || queue_ms >= 100 || (queue_ms >= 24 && old_avg_delay >= 24));
            if auto_pressure || (quality != Quality::Auto && (queue_ms >= 24 || braked)) {
                let cooldown = if quality == Quality::Auto { 6 } else { 60 };
                user.probe_blocked_until = Some(now + Duration::from_secs(cooldown));
                let ordinary_cap = target_ratio * MAX_BR_MULTIPLE;
                if enhanced_best && !user.delivery.is_empty() && self.ratio > ordinary_cap {
                    self.ratio = ordinary_cap;
                }
            }
            user.delay.add_delay(delay);
            let mut avg_delay = user.delay.avg_delay();
            avg_delay = avg_delay.max(10);
            // Each viewer adapts from its own target, starts at INIT_FPS and is capped
            // by its own limit.  The stream follows the slowest viewer in adjust_fps;
            // neither that minimum nor another viewer's limit feeds back into it.
            let user_cap = user.fps_cap(apply_decoder_limit);
            let current_fps = user.delay.fps.unwrap_or(INIT_FPS.min(user_cap));
            let mut fps = current_fps;

            // Adaptive FPS adjustment based on network delay:
            if avg_delay < 50 {
                user.delay.quick_increase_fps_count += 1;
                let mut step = if fps < normal_fps { 1 } else { 0 };
                if user.delay.quick_increase_fps_count >= 3 {
                    // After 3 consecutive good samples, increase more aggressively
                    user.delay.quick_increase_fps_count = 0;
                    step = 5;
                }
                fps = min_fps.max(fps + step);
            } else if avg_delay < 100 {
                let step = if avg_delay < old_avg_delay {
                    if fps < normal_fps {
                        1
                    } else {
                        0
                    }
                } else {
                    0
                };
                fps = min_fps.max(fps + step);
            } else if avg_delay < DELAY_THRESHOLD_150MS {
                fps = min_fps.max(fps);
            } else {
                let devide_fps = ((fps as f32) / (avg_delay as f32 / DELAY_THRESHOLD_150MS as f32))
                    .ceil() as u32;
                if avg_delay < 200 {
                    fps = min_fps.max(devide_fps);
                } else if avg_delay < 300 {
                    fps = min_fps.min(devide_fps);
                } else if avg_delay < 600 {
                    fps = dividend_ms / avg_delay;
                } else {
                    fps = (dividend_ms / avg_delay).min(devide_fps);
                }
            }

            if avg_delay < DELAY_THRESHOLD_150MS {
                user.delay.increase_fps_count += 1;
            } else {
                user.delay.increase_fps_count = 0;
            }
            if user.delay.increase_fps_count >= 3 {
                // After 3 stable samples, try increasing FPS
                user.delay.increase_fps_count = 0;
                fps += 1;
            }

            // Reset quick increase counter if network condition worsens
            if avg_delay > 50 {
                user.delay.quick_increase_fps_count = 0;
            }

            if bitrate_first {
                // While the bitrate can still come down, the frame rate keeps its floor.
                fps = fps.max(min_fps);
            }
            fps = fps.max(MIN_AUTO_FPS.min(user_cap));
            fps = user
                .delay
                .limit_fps_change(current_fps, fps, delay, bitrate_first, braked);
            fps = user
                .delay
                .accelerate_startup(current_fps, fps, user_cap, delay, braked);
            reduce_bitrate = bitrate_first
                && user.delay.needs_bitrate_reduction()
                && user.delay.replies_after_bitrate_reduction.is_none();
            fps = fps.clamp(MIN_FPS, user_cap);
            // first network delay message
            adjust_ratio = user.delay.fps.is_none();
            user.delay.fps = Some(fps);
            let base = user.delay.rtt_calculator.get_rtt().unwrap_or_default();
            log::trace!(
                "qos_trace t={} id={id} delay={delay} base={base} excess={} avg={avg_delay} bad={} good={} braked={braked} fps={fps} ratio={:.3} reduce_bitrate={reduce_bitrate}",
                hbb_common::get_time(),
                delay.saturating_sub(base),
                user.delay.consecutive_bad_samples,
                user.delay.good_samples,
                self.ratio,
            );
        }
        if auto_pressure {
            self.back_off_auto_bitrate(0.85);
        }
        self.adjust_fps();
        // A viewer's first reply is one more trigger of the periodic adjustment and
        // keeps its cooldown: a viewer joining right after a cut must not spend the
        // other viewers' evidence a second time.
        if adjust_ratio
            && self.first_reply_adjusts_ratio
            && self.since(self.adjust_ratio_instant).as_secs() >= ADJUST_RATIO_INTERVAL as u64
        {
            self.adjust_ratio(false);
        }
        if reduce_bitrate
            && self.since(self.adjust_ratio_instant).as_secs()
                >= if quality.is_custom() { 1 } else { ADJUST_RATIO_INTERVAL as u64 }
        {
            self.adjust_ratio(false);
        }
    }

    pub fn user_delay_response_elapsed(&mut self, id: i32, elapsed: u128) {
        let Some(user) = self.users.get_mut(&id) else {
            return;
        };
        if elapsed <= 2000 {
            return;
        }
        user.delay.stall_ticks = user.delay.stall_ticks.saturating_add(1);
        user.delay.add_delay(elapsed as u32);
        // Halve for every second the probe stays out beyond the first: two seconds
        // halve, three quarter, and so on down to the floor.
        let reference = match user.delay.stall_reference_fps {
            Some(reference) => reference,
            None => {
                let reference = user.delay.fps.unwrap_or(INIT_FPS.min(user.fps_cap(true)));
                user.delay.stall_reference_fps = Some(reference);
                user.delay.on_reduction(reference);
                reference
            }
        };
        let divisor = 1u32 << ((elapsed / 1000) as u32).saturating_sub(1).min(5);
        let user_cap = user.fps_cap(true);
        // The floor is a floor, not a lift: a target already below it stays.
        let current = user.delay.fps.unwrap_or(reference);
        let fps = (reference / divisor)
            .clamp(MIN_AUTO_FPS.min(user_cap), user_cap)
            .min(current);
        user.delay.fps = Some(fps);
        let reduce_bitrate = user.delay.needs_bitrate_reduction();
        log::trace!(
            "qos_trace t={} id={id} timeout={elapsed} fps={fps}",
            hbb_common::get_time()
        );
        self.back_off_auto_bitrate(0.8);
        self.adjust_fps();
        if reduce_bitrate
            && self.latest_quality().is_custom()
            && self.can_reduce_bitrate()
            && self.since(self.adjust_ratio_instant).as_secs() >= 1
        {
            self.adjust_ratio(false);
        }
    }
}

// Common adjust functions
impl VideoQoS {
    pub fn new_display(&mut self, video_service_name: String) {
        self.displays
            .insert(video_service_name, DisplayData::default());
    }

    pub fn remove_display(&mut self, video_service_name: &str) {
        self.displays.remove(video_service_name);
    }

    pub(super) fn set_bitrate_model(&mut self, name: &str, model: BitrateModel) -> Option<f32> {
        if let Some(display) = self.displays.get_mut(name) {
            display.bitrate_model = Some(model);
        }
        self.requested_bitrate_limit().map(|_| self.ratio())
    }

    pub fn update_display_data(&mut self, video_service_name: &str, send_counter: usize) {
        if let Some(display) = self.displays.get_mut(video_service_name) {
            display.send_counter += send_counter;
        }
        self.adjust_fps();
        let abr_enabled = self.in_vbr_state();
        if abr_enabled {
            let quality = self.latest_quality();
            let interval = if quality == Quality::Auto
                || (matches!(quality, Quality::Custom(cap) if self.ratio < cap)
                    && self.can_recover_bitrate())
            {
                1
            } else {
                ADJUST_RATIO_INTERVAL
            };
            if self.since(self.adjust_ratio_instant).as_secs() >= interval as u64 {
                let dynamic_screen = self
                    .displays
                    .iter()
                    .any(|d| d.1.send_counter >= ADJUST_RATIO_INTERVAL * DYNAMIC_SCREEN_THRESHOLD);
                self.adjust_ratio(dynamic_screen);
            }
        } else {
            let quality = self.latest_quality();
            self.ratio = if quality == Quality::Auto && self.requested_bitrate_limit().is_some() {
                self.custom_bitrate_cap().unwrap_or_else(|| quality.ratio())
            } else {
                quality.ratio()
            };
        }
    }

    #[inline]
    fn highest_fps(&self) -> u32 {
        let apply_decoder_limit = self.latest_quality() != Quality::Auto
            || self.displays.len() != 1
            || !self.can_reduce_bitrate();
        self.users
            .values()
            .map(|u| u.fps_cap(apply_decoder_limit))
            .min()
            .unwrap_or(FPS)
            .clamp(MIN_FPS, MAX_FPS)
    }

    // Get latest quality settings from all users
    pub fn latest_quality(&self) -> Quality {
        self.users
            .iter()
            .map(|(_, u)| u.quality)
            .filter(|q| *q != None)
            .max_by(|a, b| a.unwrap_or_default().0.cmp(&b.unwrap_or_default().0))
            .flatten()
            .unwrap_or((0, Quality::Balanced))
            .1
    }

    pub(super) fn requested_bitrate_limit(&self) -> Option<u32> {
        self.users
            .values()
            .filter_map(|user| user.bitrate_limit_kbps)
            .min()
    }

    fn custom_bitrate_cap(&self) -> Option<f32> {
        let absolute = self.requested_bitrate_limit().into_iter().flat_map(|kbps| {
            self.displays
                .values()
                .filter_map(move |d| d.bitrate_model.map(|model| model.ratio_at_limit(kbps)))
        });
        self.users
            .values()
            .filter_map(|user| match user.quality {
                Some((_, Quality::Custom(ratio))) => Some(ratio),
                _ => None,
            })
            .chain(absolute)
            .reduce(f32::min)
    }

    // Lowest ratio the latest quality allows: keeps about 1Mbps at high resolutions.
    fn min_ratio(&self) -> f32 {
        let current_bitrate = self.bitrate();
        let ratio_1mbps = if current_bitrate > 0 {
            Some((self.ratio * 1000.0 / current_bitrate as f32).max(BR_MIN_HIGH_RESOLUTION))
        } else {
            None
        };
        match self.latest_quality() {
            Quality::Best => {
                let mut min = BR_BEST / 2.5;
                if let Some(ratio_1mbps) = ratio_1mbps {
                    if min > ratio_1mbps {
                        min = ratio_1mbps;
                    }
                }
                min.max(BR_MIN)
            }
            Quality::Balanced => {
                let mut min = (BR_BALANCED / 2.0).min(0.4);
                if let Some(ratio_1mbps) = ratio_1mbps {
                    if min > ratio_1mbps {
                        min = ratio_1mbps;
                    }
                }
                min.max(BR_MIN_HIGH_RESOLUTION)
            }
            Quality::Low | Quality::Auto | Quality::Custom(_) => BR_MIN_HIGH_RESOLUTION,
        }
    }

    // Whether congestion can still be answered with a lower bitrate.  Within two
    // percent of the floor another step is not worth waiting a cooldown for.
    fn can_reduce_bitrate(&self) -> bool {
        self.in_vbr_state() && !self.displays.is_empty() && self.ratio > self.min_ratio() * 1.02
    }

    // Every ratio adjustment starts a new window for the dynamic screen counters.
    fn reset_send_counters(&mut self) {
        self.displays.values_mut().for_each(|d| d.send_counter = 0);
    }

    // Adjust quality ratio based on network delay and screen changes
    fn adjust_ratio(&mut self, dynamic_screen: bool) {
        if !self.in_vbr_state() {
            return;
        }
        // Get maximum delay from all users
        let max_delay = self.users.iter().map(|u| u.1.delay.avg_delay()).max();
        let Some(max_delay) = max_delay else {
            return;
        };
        // Each viewer judges its own delay; the stream takes the most conservative
        // step any viewer asks for.
        let reduction = self
            .users
            .values()
            .filter_map(|u| u.delay.ratio_reduction())
            .reduce(f32::min);
        if reduction.is_none() && max_delay >= DELAY_THRESHOLD_150MS {
            // Elevated but unconfirmed: no change, and no cooldown either, so a
            // confirmation on the next reply is acted on at once.
            self.reset_send_counters();
            return;
        }

        let quality = self.latest_quality();
        let target_ratio = quality.ratio();
        let current_ratio = self.ratio;
        let current_bitrate = self.bitrate();
        let encoder_ready =
            !quality.is_custom() || self.bitrate_recovery.encoder_ready(self.now());

        let (growth_kbps, caught_up) = self.delivery_growth_budget(current_bitrate);
        let ratio_growth_limit = if current_bitrate > 0 {
            Some(current_bitrate.saturating_add(growth_kbps) as f32 * current_ratio / current_bitrate as f32)
        } else {
            None
        };

        // Best can probe above the old fixed limit on sustained motion. Never send
        // synthetic traffic to prove capacity: evaluate the next step using delivered
        // video and queue feedback. Keep the last clear still frame when activity ends.
        let base_cap = target_ratio * MAX_BR_MULTIPLE;
        let now = self.now();
        let has_absolute_target = self.requested_bitrate_limit().is_some();
        let auto_probe = quality == Quality::Auto
            && encoder_ready
            && !self.bitrate_recovery.auto_retry.is_some_and(|(retry_at, _)| now < retry_at)
            && (dynamic_screen || has_absolute_target)
            && caught_up
            && reduction.is_none()
            && self.users.values().all(|viewer| {
                viewer.has_clear_video_path(now) && viewer.send_pressure.is_none_or(|at| {
                    now.saturating_duration_since(at) >= Duration::from_secs(3)
                })
            });
        if auto_probe
            && self
                .bitrate_recovery
                .auto_trial_from
                .is_some_and(|(_, attempted_from)| current_bitrate <= attempted_from)
        {
            self.back_off_auto_bitrate(0.85);
            return;
        }
        let custom_cap = self.custom_bitrate_cap().unwrap_or(f32::MAX);
        let capped_probe = auto_probe && has_absolute_target;
        let recovery_target = self.bitrate_recovery_target(quality, custom_cap);
        let recover = !auto_probe
            && quality.is_custom()
            && current_bitrate > 0
            && current_ratio < recovery_target
            && reduction.is_none()
            && self.can_recover_bitrate();
        let max = if quality == Quality::Auto {
            if auto_probe {
                f32::MAX
            } else {
                current_ratio
            }
        } else if quality == Quality::Best && self.abr_config {
            if dynamic_screen && caught_up && max_delay < 50 {
                base_cap * 2.5
            } else if current_ratio > base_cap {
                if dynamic_screen && !caught_up { (current_ratio * 0.90).max(base_cap) }
                else { current_ratio }
            } else { base_cap }
        } else { base_cap };
        let max = max.min(custom_cap);
        let min = self.min_ratio().min(max);

        let mut v = current_ratio;

        // Three bad replies in a row confirm congestion; with a bitrate-targeted
        // encoder the bitrate is then the only thing that drains the queue, so it
        // comes down hard.  Increases need every viewer below the threshold.
        if let Some(factor) = reduction {
            if quality == Quality::Auto && self.displays.len() == 1 {
                self.back_off_auto_bitrate(factor);
                return;
            }
            v = current_ratio * factor;
        } else if capped_probe {
            self.bitrate_recovery.auto_trial_from = None;
            v = self.bitrate_recovery.capped_probe_target(current_ratio, custom_cap, now);
        } else if auto_probe {
            let step = if current_bitrate < FAST_GROWTH_BELOW_KBPS {
                1.50
            } else if self.bitrate_recovery.fast_uncapped_growth(now) {
                1.20
            } else {
                1.10
            };
            v = current_ratio * step;
        } else if recover {
            let step = (current_bitrate / 5).clamp(150, 1200);
            let next_bitrate = current_bitrate.saturating_add(step);
            v = (current_ratio * next_bitrate as f32 / current_bitrate as f32)
                .min(recovery_target);
        } else if dynamic_screen && encoder_ready && max_delay < 50 {
            v = current_ratio * 1.15;
        } else if dynamic_screen && encoder_ready && max_delay < 100 {
            v = current_ratio * 1.1;
        } else if dynamic_screen && encoder_ready {
            v = current_ratio * 1.05;
        }

        // Limit quality increase rate for better stability
        if let Some(limit) = ratio_growth_limit {
            if !capped_probe
                && !recover
                && v > limit
                && (auto_probe || growth_kbps == 0 || current_ratio >= BR_SPEED)
            {
                v = limit;
            }
        }

        if reduction.is_some() {
            for user in self.users.values_mut() {
                if user.delay.needs_bitrate_reduction()
                    && user.delay.replies_after_bitrate_reduction.is_none()
                {
                    // One outstanding probe may have started before the bitrate change.
                    user.delay.replies_after_bitrate_reduction =
                        Some(if v.clamp(min, max) < current_ratio {
                            0
                        } else {
                            2
                        });
                }
            }
        }
        let next = v.clamp(min, max);
        if auto_probe && next > current_ratio {
            self.bitrate_recovery.auto_trial_from = Some((current_ratio, current_bitrate));
            // Feedback collected before the change cannot validate the higher rate.
            for user in self.users.values_mut() {
                user.delivery.clear();
            }
        }
        if reduction.is_some() && quality.is_custom() {
            self.bitrate_recovery.remember_reduction(current_ratio, next);
        }
        self.ratio = next;
        if self.bitrate_recovery.previous_ratio.is_some_and(|before| next >= before) {
            self.bitrate_recovery.previous_ratio = None;
        }
        self.reset_send_counters();
        self.adjust_ratio_instant = self.now();
    }

    // Adjust fps based on network delay and user response time
    fn adjust_fps(&mut self) {
        let highest_fps = self.highest_fps();
        // Get minimum fps from all users
        let mut fps = self
            .users
            .iter()
            .map(|u| u.1.delay.fps.unwrap_or(INIT_FPS))
            .min()
            .unwrap_or(INIT_FPS);

        // Every viewer inside its first second keeps the stream at INIT_FPS to
        // ensure stability; each viewer carries its own start-up clock.
        if self.users.values().any(|u| {
            u.joined_at
                .is_some_and(|joined| self.since(joined).as_secs() < 1)
        }) {
            fps = fps.min(INIT_FPS);
        }

        // Ensure fps stays within valid range
        self.fps = fps.clamp(MIN_FPS, highest_fps);
    }
}

#[derive(Default, Debug, Clone)]
struct RttCalculator {
    baseline: Option<u32>,
    samples: VecDeque<u32>,
}

impl RttCalculator {
    const WINDOW_SAMPLES: usize = 20;
    const MAX_INCREASE_MS: u32 = 50;

    pub fn update(&mut self, delay: u32) {
        if self.samples.len() >= Self::WINDOW_SAMPLES {
            self.samples.pop_front();
        }
        self.samples.push_back(delay);
        let baseline = self.baseline.unwrap_or(delay).min(delay);
        self.baseline = Some(baseline);

        if self.samples.len() < Self::WINDOW_SAMPLES {
            return;
        }
        let half = Self::WINDOW_SAMPLES / 2;
        let older_min = self.samples.iter().take(half).min().copied();
        let recent_min = self.samples.iter().skip(half).min().copied();
        let (Some(older_min), Some(recent_min)) = (older_min, recent_min) else {
            return;
        };
        // A rising floor can be a growing queue. Allow 10 ms of probe granularity,
        // but wait for it to settle before forgetting the old baseline.
        if recent_min > older_min.saturating_add(10) {
            return;
        }
        let rise = older_min.min(recent_min).saturating_sub(baseline);
        if rise > 0 {
            self.baseline = Some(baseline + (rise / 2).clamp(1, Self::MAX_INCREASE_MS));
        }
    }

    pub fn get_rtt(&self) -> Option<u32> {
        self.baseline
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scrap::{
        aom::AomEncoderConfig,
        codec::{base_bitrate, EncoderCfg},
    };

    fn stable_qos() -> VideoQoS {
        let mut qos = VideoQoS::default();
        qos.advance_ms(2000);
        qos.users.insert(1, UserData::default());
        for _ in 0..12 {
            qos.user_network_delay(1, 10);
        }
        assert_eq!(qos.fps(), FPS);
        qos
    }

    fn clear_frame_sample(qos: &mut VideoQoS, fps: u32) {
        qos.observe_auto_frames("monitor", (fps * 9).div_ceil(10), true, true, false);
    }

    fn monitor_bitrate_model(width: u32, height: u32) -> BitrateModel {
        EncoderCfg::AOM(AomEncoderConfig {
            width,
            height,
            quality: 1.0,
            keyframe_interval: None,
        })
        .bitrate_model()
    }

    #[test]
    fn a_30_fps_source_can_probe_under_a_60_fps_setting() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_custom_fps(1, 60);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG | (50 << 8));
        qos.store_bitrate(2000);
        qos.adjust_ratio(true);
        assert_eq!(qos.ratio(), 1.0);
        for _ in 0..3 {
            clear_frame_sample(&mut qos, 30);
            qos.user_video_delivery(1, 1950, 30, 0);
        }
        qos.adjust_ratio(true);
        assert!((1.45..=1.50).contains(&qos.ratio()));
        qos.user_image_quality(1, 50 << 8);
        qos.adjust_ratio(true);
        assert!(qos.ratio() <= 1.0);
    }

    #[test]
    fn lower_decoder_feedback_cannot_make_a_60_fps_stream_probe_at_30() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG);
        qos.user_custom_fps(1, 60);
        qos.user_auto_adjust_fps(1, 30);
        qos.store_bitrate(2000);
        assert_eq!(qos.auto_target_fps(), 60);
        for _ in 0..24 {
            qos.user_network_delay(1, 10);
        }
        assert_eq!(qos.fps(), 60);
        for _ in 0..2 {
            clear_frame_sample(&mut qos, 60);
            qos.user_video_delivery(1, 2000, 30, 0);
        }
        qos.adjust_ratio(true);
        assert!(qos.ratio() < 1.0);
        assert_eq!(qos.fps(), 60);
    }

    #[test]
    fn absolute_target_applies_on_setup_and_after_resolution_or_option_changes() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.user_image_quality_with_limit(1, 50 << 8, 50_000);
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let ratio = qos
                .set_bitrate_model("monitor", monitor_bitrate_model(width, height))
                .unwrap();
            assert_eq!((base_bitrate(width, height) as f32 * ratio) as u32, 50_000);
        }
        for kbps in [75_000, 25_000, 500] {
            qos.user_image_quality_with_limit(1, 50 << 8, kbps);
            assert_eq!((base_bitrate(3840, 2160) as f32 * qos.ratio()) as u32, kbps);
        }
        qos.user_image_quality(1, ImageQuality::Best.value());
        assert_eq!(qos.ratio(), BR_BEST);
    }

    #[test]
    fn capped_stream_reduces_on_load_and_recovers_after_motion_returns() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_bitrate_model("monitor", monitor_bitrate_model(1920, 1080));
        qos.user_image_quality_with_limit(1, 50 << 8, 80_000);
        let target = qos.ratio();
        qos.store_bitrate(80_000);
        for _ in 0..2 {
            qos.advance_ms(1000);
            qos.observe_auto_frames("monitor", 54, false, false, true);
        }
        let reduced = qos.ratio();
        assert!(reduced < target * 0.8);
        qos.user_image_quality_with_limit(1, 50 << 8, 80_000);
        assert_eq!(qos.ratio(), reduced);
        for _ in 0..5 {
            qos.advance_ms(1000);
            qos.observe_auto_frames("monitor", 0, false, false, false);
            qos.user_network_delay(1, 10);
            qos.update_display_data("monitor", 0);
            assert_eq!(qos.ratio(), reduced);
        }

        let mut recovered_early = false;
        for second in 0..30 {
            qos.advance_ms(1000);
            let bitrate = (base_bitrate(1920, 1080) as f32 * qos.ratio()) as u32;
            qos.store_bitrate(bitrate);
            clear_frame_sample(&mut qos, 60);
            // A highly compressible scene still presents 60 real frames per second.
            qos.user_video_delivery(1, 500, 60, 0);
            qos.user_network_delay(1, 10);
            qos.update_display_data("monitor", 60);
            let ratio = qos.ratio();
            assert!(ratio <= target);
            recovered_early |= second < 6 && ratio > reduced * 1.10;
        }
        assert!(recovered_early);
        assert_eq!(qos.ratio(), target);
    }

    #[test]
    fn a_large_direct_target_backs_off_promptly_when_delivery_queues_up() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_bitrate_model("monitor", monitor_bitrate_model(1920, 1080));
        qos.user_image_quality_with_limit(1, 50 << 8, 160_000);
        let target = qos.ratio();
        qos.store_bitrate(160_000);
        for second in 0..2 {
            qos.advance_ms(1000);
            clear_frame_sample(&mut qos, 60);
            qos.user_video_delivery(1, 60_000, 30, 12);
            if second == 0 {
                assert_eq!(qos.ratio(), target);
            }
        }
        let bitrate = (base_bitrate(1920, 1080) as f32 * qos.ratio()) as u32;
        assert!((60_000..=66_100).contains(&bitrate), "{bitrate}");
    }

    #[test]
    fn removing_the_cap_keeps_the_applied_rate_and_probes_when_delivery_is_below_target() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, 70 << 8);
        qos.store_bitrate(3241);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG | (50 << 8));
        assert_eq!(qos.ratio(), 1.4);
        for _ in 0..3 {
            qos.advance_ms(1000);
            clear_frame_sample(&mut qos, 30);
            qos.user_video_delivery(1, 580, 30, 0);
            qos.update_display_data("monitor", 30);
        }
        let probed = qos.ratio();
        assert!(probed > 1.4 && probed <= 1.55);

        qos.advance_ms(1000);
        qos.user_video_delivery(1, 580, 30, 10);
        qos.update_display_data("monitor", 30);
        assert_eq!(qos.ratio(), probed);
    }

    #[test]
    fn uncapped_stream_rechecks_a_previous_limit_with_bounded_probes() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG);
        qos.set_fixed_screen_fps(1, 60);

        let mut probes_at_50 = 0;
        let mut peak_after_change = 0;
        for second in 0..86 {
            qos.advance_ms(1000);
            let before = qos.ratio();
            let kbps = (before * 50_000.0).round() as u32;
            let capacity = if second < 45 { 50_000 } else { 100_000 };
            qos.store_bitrate(kbps);
            clear_frame_sample(&mut qos, 60);
            let overloaded = kbps > capacity;
            qos.user_video_delivery(
                1,
                kbps.min(capacity),
                if overloaded { 30 } else { 60 },
                if overloaded { 12 } else { 0 },
            );
            qos.user_network_delay(1, 10);
            qos.update_display_data("monitor", 60);
            let after = qos.ratio();
            assert!(
                after <= before * 1.2001,
                "second {second}, {before} -> {after}"
            );
            assert_eq!(qos.fps(), 60);
            if second < 45 {
                probes_at_50 += u32::from(after > before);
                if second >= 2 {
                    assert!((1.0..=1.2001).contains(&after));
                }
            } else {
                peak_after_change = peak_after_change.max(kbps.min(capacity));
            }
        }
        assert!(
            (2..=3).contains(&probes_at_50),
            "{probes_at_50} probes in 45 seconds"
        );
        assert!(
            peak_after_change >= 95_000,
            "recovered to {peak_after_change} kbps"
        );
    }

    #[test]
    fn an_encoder_that_cannot_increase_bitrate_holds_during_cooldown() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG);
        // This encoder changes the configured rate only when it is recreated.
        qos.store_bitrate(16_000);
        for second in 0..12 {
            qos.advance_ms(1000);
            clear_frame_sample(&mut qos, 60);
            qos.user_video_delivery(1, 16_000, 60, 0);
            qos.update_display_data("monitor", 60);
            if second == 2 {
                assert_eq!(qos.ratio(), 1.2);
            } else if (5..11).contains(&second) {
                assert_eq!(qos.ratio(), 1.0);
            }
        }
    }

    #[test]
    fn a_capped_session_can_lower_bitrate_on_the_next_second() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, 100 << 8);
        qos.store_bitrate(4000);
        qos.user_network_delay(1, 80);
        qos.adjust_ratio(true);
        for (rate, queue) in [(2500, 2), (2400, 4), (2200, 8)] {
            qos.advance_ms(350);
            qos.user_video_delivery(1, rate, 30, queue);
        }
        assert!(qos.ratio() < 2.0);
    }

    #[test]
    fn sparse_video_holds_bitrate_until_fresh_frames_can_validate_an_increase() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG);
        qos.ratio = 3.0;
        qos.store_bitrate(9_000);
        qos.user_network_delay(1, 120);
        let reduced = qos.ratio();
        assert!(reduced < 3.0);

        for _ in 0..15 {
            qos.advance_ms(1000);
            qos.store_bitrate((reduced * 3000.0) as u32);
            qos.observe_auto_frames("monitor", 27, false, false, false);
            qos.user_network_delay(1, 10);
            qos.user_video_delivery(1, 120, 0, 0);
            qos.update_display_data("monitor", 1);
            assert_eq!(qos.ratio(), reduced);
        }
    }

    #[test]
    fn sparse_video_recovers_only_with_a_clear_queue_and_respects_the_numeric_cap() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, 100 << 8);
        qos.ratio = 1.5;
        let initial_fps = qos.fps();

        for _ in 0..3 {
            qos.advance_ms(1000);
            qos.store_bitrate(4500);
            qos.user_video_delivery(1, 100, 1, 8);
            qos.update_display_data("monitor", 1);
        }
        assert_eq!(qos.ratio(), 1.5);
        for _ in 0..6 {
            qos.advance_ms(1000);
            let bitrate = (qos.ratio() * 3000.0) as u32;
            qos.store_bitrate(bitrate);
            qos.user_video_delivery(1, 100, 1, 0);
            qos.update_display_data("monitor", 1);
        }
        assert_eq!(qos.ratio(), 2.0);
        assert_eq!(qos.fps(), initial_fps);
    }

    #[test]
    fn encode_pressure_reduces_bitrate_without_lowering_requested_fps() {
        for option in [100 << 8, CUSTOM_BITRATE_AUTO_FLAG] {
            let mut qos = stable_qos();
            qos.new_display("monitor".into());
            qos.set_support_changing_quality("monitor", true);
            qos.user_image_quality(1, option);
            qos.set_fixed_screen_fps(1, 60);
            qos.store_bitrate(8_000);
            qos.ratio = 2.0;
            let initial_ratio = qos.ratio();

            qos.back_off_encoder_bitrate();
            qos.update_display_data("monitor", 30);

            assert!(qos.ratio() < initial_ratio);
            assert_eq!(qos.fps(), 60);
            for _ in 0..12 {
                qos.back_off_encoder_bitrate();
            }
            if option == CUSTOM_BITRATE_AUTO_FLAG {
                assert!(qos.ratio() >= 1.69); // one reduction while it takes effect
            } else {
                assert_eq!(qos.ratio(), Quality::Auto.ratio());
            }
        }
    }

    #[test]
    fn uncapped_rate_reduces_when_active_encoding_or_delivery_misses_60_fps() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.user_image_quality(1, CUSTOM_BITRATE_AUTO_FLAG);
        qos.set_fixed_screen_fps(1, 60);
        qos.store_bitrate(50_000);
        for _ in 0..3 {
            qos.advance_ms(1000);
            qos.observe_auto_frames("monitor", 54, false, false, false);
            qos.user_video_delivery(1, 50_000, 30, 0);
            qos.update_display_data("monitor", 30);
            assert_eq!(qos.ratio(), 1.0);
        }
        for _ in 0..2 {
            qos.advance_ms(1000);
            qos.observe_auto_frames("monitor", 54, false, false, true);
            qos.user_video_delivery(1, 50_000, 30, 0);
            qos.update_display_data("monitor", 30);
        }
        let after_encoding_pressure = qos.ratio();
        assert!(after_encoding_pressure < 1.0);
        qos.store_bitrate(42_500);
        for _ in 0..2 {
            qos.advance_ms(1000);
            clear_frame_sample(&mut qos, 60);
            qos.user_video_delivery(1, 42_500, 30, 0);
            qos.update_display_data("monitor", 60);
        }
        assert!(qos.ratio() < after_encoding_pressure);
        let after_delivery_pressure = qos.ratio();
        qos.advance_ms(2000);
        qos.observe_video_send_pressure(1, true);
        assert_eq!(qos.ratio(), after_delivery_pressure);
        qos.advance_ms(1000);
        qos.observe_video_send_pressure(1, true);
        assert!(qos.ratio() < after_delivery_pressure);
        assert_eq!(qos.fps(), 60);
    }

    #[test]
    fn delivery_feedback_gates_probe_growth_and_expires() {
        let mut qos = stable_qos();
        qos.displays.insert("monitor".into(), DisplayData::default());
        assert_eq!(qos.delivery_growth_budget(8000), (150, false));
        for _ in 0..3 {
            qos.advance_ms(1000);
            qos.user_video_delivery(1, 7500, 50, 0);
        }
        assert_eq!(qos.delivery_growth_budget(8000), (750, true));
        qos.users.insert(2, UserData::default());
        assert_eq!(qos.delivery_growth_budget(8000), (150, false));
        for _ in 0..2 { qos.user_video_delivery(1, 8000, 35, 45); }
        assert_eq!(qos.delivery_growth_budget(8000), (0, false));
        qos.users.remove(&2);
        qos.advance_ms(8000);
        assert_eq!(qos.delivery_growth_budget(8000), (150, false));
        qos.user_video_delivery(1, 80, 1, 0);
        assert!(qos.users[&1].delivery.is_empty());
    }

    #[test]
    fn excess_delay_rolls_back_a_best_quality_probe_and_pauses_the_next_trial() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.users.get_mut(&1).unwrap().quality = Some((1, Quality::Best));
        qos.ratio = BR_BEST * MAX_BR_MULTIPLE * 1.25;
        for _ in 0..3 { qos.user_video_delivery(1, 8100, 60, 0); }
        assert!(qos.delivery_growth_budget(8000).1);
        qos.user_network_delay(1, 65);
        assert!(qos.ratio <= BR_BEST * MAX_BR_MULTIPLE);
        assert_eq!(qos.delivery_growth_budget(8000), (150, false));
        qos.advance_ms(59_000);
        for _ in 0..3 { qos.user_video_delivery(1, 8100, 60, 0); }
        assert!(!qos.delivery_growth_budget(8000).1);
        qos.advance_ms(1100);
        assert!(qos.delivery_growth_budget(8000).1);
    }

    #[test]
    fn falling_delivery_and_growing_backlog_lower_best_quality_before_slow_probe_brake() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.users.get_mut(&1).unwrap().quality = Some((1, Quality::Best));
        qos.ratio = BR_BEST;
        qos.store_bitrate(8000);
        qos.user_network_delay(1, 80);
        for (rate, queue) in [(4600, 0), (4500, 0), (4000, 0)] {
            qos.advance_ms(500);
            qos.user_video_delivery(1, rate, 30, queue);
        }
        assert_eq!(qos.ratio(), BR_BEST);
        for (rate, queue) in [(4600, 2), (4500, 4), (4000, 8)] {
            qos.advance_ms(500);
            qos.user_video_delivery(1, rate, 30, queue);
        }
        assert!(qos.ratio() < BR_BEST * 0.8);
    }

    #[test]
    fn best_quality_can_probe_above_its_original_ceiling_only_with_delivery_evidence() {
        let mut qos = stable_qos();
        qos.new_display("monitor".into());
        qos.set_support_changing_quality("monitor", true);
        qos.users.get_mut(&1).unwrap().quality = Some((1, Quality::Best));
        qos.ratio = BR_BEST;
        qos.store_bitrate(8000);
        qos.adjust_ratio(true);
        assert_eq!(qos.ratio, BR_BEST);
        for _ in 0..3 { qos.user_video_delivery(1, 7900, 55, 0); }
        qos.adjust_ratio(true);
        assert!(qos.ratio > BR_BEST && qos.ratio < BR_BEST * 1.15);
        qos.users.get_mut(&1).unwrap().quality = Some((2, Quality::Custom(BR_BEST)));
        qos.adjust_ratio(true);
        assert!(qos.ratio <= BR_BEST);
    }

    #[test]
    fn occasional_spikes_do_not_accumulate_congestion() {
        let mut qos = stable_qos();
        for delay in [800, 10, 10].repeat(20) {
            qos.user_network_delay(1, delay);
            assert_eq!(qos.fps(), FPS);
        }
    }

    #[test]
    fn delay_history_keeps_two_samples() {
        let mut delay = UserDelay::default();
        for sample in [1, 2, 3] {
            delay.add_delay(sample);
        }
        assert_eq!(delay.delay_history.len(), HISTORY_DELAY_LEN);
    }

    #[test]
    fn response_timeout_recovers_in_two_good_replies() {
        let mut qos = stable_qos();
        qos.user_delay_response_elapsed(1, 3000);
        assert_eq!(qos.fps(), 7);
        qos.user_network_delay(1, 3200);
        assert_eq!(
            qos.fps(),
            7,
            "the late reply belongs to the stall that was braked"
        );
        qos.user_delay_response_elapsed(1, 0);
        qos.user_network_delay(1, 10);
        assert_eq!(
            qos.fps(),
            8,
            "one good reply must not restore the full frame rate"
        );
        qos.user_network_delay(1, 10);
        assert_eq!(
            qos.fps(),
            FPS,
            "the second good reply restores the frame rate"
        );
        qos.user_network_delay(1, 10);
        assert_eq!(qos.fps(), FPS, "the third keeps the restored frame rate");
    }

    #[test]
    fn restore_aims_lower_after_a_restore_that_congested() {
        let mut qos = stable_qos();
        for _ in 0..2 {
            qos.user_network_delay(1, 1200);
        }
        assert_eq!(qos.fps(), 8);
        qos.user_network_delay(1, 10);
        qos.user_network_delay(1, 10);
        assert_eq!(qos.fps(), FPS);
        // The restored level congests at once, so the next restore aims lower.
        for _ in 0..3 {
            qos.user_network_delay(1, 400);
        }
        assert!(qos.fps() < FPS);
        qos.user_network_delay(1, 10);
        qos.user_network_delay(1, 10);
        assert!(
            qos.fps() < FPS,
            "no return to the level that failed: {}",
            qos.fps()
        );
        qos.user_network_delay(1, 10);
        assert_eq!(qos.fps(), FPS, "ordinary recovery can still reach the cap");
    }

    mod adaptation;
    mod baseline;
    mod jitter;
    mod recovery;
    mod sim;
    mod smoke;
    mod startup;
}
