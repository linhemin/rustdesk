use base::message_proto::{message, video_frame, Message, VideoFrame};
use hbb_common::tokio::{
    sync::Notify,
    time::{Duration, Instant},
};
use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use super::video_service;

const MAX_PENDING_FRAMES: usize = 8;
const MAX_FRAME_AGE: Duration = Duration::from_millis(150);

pub(super) enum Event {
    Send(Instant, Arc<Message>),
    Refresh(i32),
}

#[derive(Default)]
pub(super) struct VideoQueue {
    pending: Mutex<Pending>,
    ready: Notify,
}

#[derive(Default)]
struct Pending {
    messages: VecDeque<(Instant, Arc<Message>)>,
    recovery: HashMap<i32, Recovery>,
    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    discarded_frames: usize,
}

enum Recovery {
    NeedsRefresh,
    WaitingForKeyframe,
}

impl VideoQueue {
    pub(super) fn push(&self, conn_id: i32, message: Arc<Message>) {
        let mut pending = self.pending.lock().unwrap();
        let now = Instant::now();
        if let Some(message::Union::VideoFrame(frame)) = &message.union {
            if pending.expired(now)
                || pending
                    .messages
                    .iter()
                    .filter(|(_, m)| m.has_video_frame())
                    .count()
                    >= MAX_PENDING_FRAMES
            {
                pending.discard_video(conn_id);
                self.ready.notify_one();
            }
            if pending.recovery.contains_key(&frame.display) {
                if !starts_with_keyframe(frame) {
                    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
                    {
                        pending.discarded_frames += crate::video_diagnostics::frame_count(frame);
                    }
                    video_service::notify_video_frame_fetched(
                        frame.display as usize,
                        conn_id,
                        None,
                    );
                    return;
                }
                pending.recovery.remove(&frame.display);
            }
        }
        pending.messages.push_back((now, message));
        self.ready.notify_one();
    }

    pub(super) async fn recv(&self, conn_id: i32) -> Event {
        loop {
            if let Some(event) = self.pending.lock().unwrap().next(conn_id) {
                return event;
            }
            self.ready.notified().await;
        }
    }

    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    pub(super) fn len(&self) -> usize {
        self.pending.lock().unwrap().messages.len()
    }

    #[cfg(all(windows, feature = "windows-video-diagnostics"))]
    pub(super) fn take_discarded_frames(&self) -> usize {
        std::mem::take(&mut self.pending.lock().unwrap().discarded_frames)
    }
}

impl Pending {
    fn expired(&self, now: Instant) -> bool {
        self.messages
            .iter()
            .find(|(_, message)| message.has_video_frame())
            .is_some_and(|(queued_at, _)| now.duration_since(*queued_at) >= MAX_FRAME_AGE)
    }

    fn discard_video(&mut self, conn_id: i32) {
        self.messages.retain(|(_, message)| {
            let Some(message::Union::VideoFrame(frame)) = &message.union else {
                return true;
            };
            self.recovery.insert(frame.display, Recovery::NeedsRefresh);
            #[cfg(all(windows, feature = "windows-video-diagnostics"))]
            {
                self.discarded_frames += crate::video_diagnostics::frame_count(frame);
            }
            // A dropped frame must not make the shared capture loop wait for this viewer.
            video_service::notify_video_frame_fetched(frame.display as usize, conn_id, None);
            false
        });
    }

    fn next(&mut self, conn_id: i32) -> Option<Event> {
        if self.expired(Instant::now()) {
            self.discard_video(conn_id);
        }
        if let Some((&display, state)) = self
            .recovery
            .iter_mut()
            .find(|(_, state)| matches!(state, Recovery::NeedsRefresh))
        {
            // Request recovery only once the connection's in-flight write has finished.
            *state = Recovery::WaitingForKeyframe;
            return Some(Event::Refresh(display));
        }
        self.messages
            .pop_front()
            .map(|(at, message)| Event::Send(at, message))
    }
}

fn starts_with_keyframe(frame: &VideoFrame) -> bool {
    use video_frame::Union::*;
    match &frame.union {
        Some(Vp8s(frames) | Vp9s(frames) | Av1s(frames) | H264s(frames) | H265s(frames)) => {
            frames.frames.first().is_some_and(|frame| frame.key)
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::{EncodedVideoFrame, EncodedVideoFrames, Misc, SwitchDisplay};
    use hbb_common::tokio;

    fn frame(display: i32, pts: i64, key: bool) -> Arc<Message> {
        let mut frame = VideoFrame {
            display,
            ..Default::default()
        };
        frame.set_h264s(EncodedVideoFrames {
            frames: vec![EncodedVideoFrame {
                pts,
                key,
                ..Default::default()
            }],
            ..Default::default()
        });
        let mut message = Message::new();
        message.set_video_frame(frame);
        Arc::new(message)
    }

    fn switch_display() -> Arc<Message> {
        let mut misc = Misc::new();
        misc.set_switch_display(SwitchDisplay::new());
        let mut message = Message::new();
        message.set_misc(misc);
        Arc::new(message)
    }

    async fn assert_sends(queue: &VideoQueue, expected: &Message) {
        let Event::Send(_, actual) = queue.recv(1).await else {
            panic!("expected a message to send");
        };
        assert_eq!(actual.as_ref(), expected);
    }

    #[tokio::test(start_paused = true)]
    async fn sends_current_frames_and_display_changes_in_order() {
        let queue = VideoQueue::default();
        let messages = [frame(0, 1, true), switch_display(), frame(1, 2, true)];
        for message in &messages {
            queue.push(1, message.clone());
        }
        for message in &messages {
            assert_sends(&queue, message).await;
        }
    }

    #[tokio::test(start_paused = true)]
    async fn skips_overflow_and_resumes_from_a_new_keyframe() {
        let queue = VideoQueue::default();
        let display_change = switch_display();
        for pts in 0..MAX_PENDING_FRAMES {
            queue.push(1, frame(0, pts as i64, pts == 0));
        }
        queue.push(1, display_change.clone());
        queue.push(1, frame(0, 100, false));
        assert!(matches!(queue.recv(1).await, Event::Refresh(0)));

        queue.push(1, frame(0, 101, false));
        let keyframe = frame(0, 102, true);
        let delta = frame(0, 103, false);
        queue.push(1, keyframe.clone());
        queue.push(1, delta.clone());
        for message in [&display_change, &keyframe, &delta] {
            assert_sends(&queue, message).await;
        }
    }

    #[tokio::test(start_paused = true)]
    async fn expires_stale_frames_even_when_no_new_frames_arrive() {
        let queue = VideoQueue::default();
        queue.push(1, frame(1, 0, true));
        tokio::time::advance(MAX_FRAME_AGE).await;
        assert!(matches!(queue.recv(1).await, Event::Refresh(1)));

        let other_display = frame(0, 1, false);
        queue.push(1, frame(1, 2, false));
        queue.push(1, other_display.clone());
        assert_sends(&queue, &other_display).await;
    }
}
