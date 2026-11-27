use bytes::Bytes;
#[cfg(not(target_os = "linux"))]
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use hbb_common::{anyhow::Context, tokio::sync::mpsc, ResultType};
use magnum_opus::{Application, Channels, Encoder};
use std::{sync::mpsc as sync, time::Duration};

pub(super) struct Capture(mpsc::Receiver<Bytes>);

impl Capture {
    #[cfg(target_os = "linux")]
    pub(super) fn start() -> ResultType<Self> {
        hbb_common::bail!("Mobile microphone capture unavailable")
    }

    #[cfg(not(target_os = "linux"))]
    pub(super) fn start() -> ResultType<Self> {
        let (tx, rx) = mpsc::channel(4);
        std::thread::Builder::new()
            .name("phone microphone capture".into())
            .spawn(move || {
                if let Err(err) = record(tx) {
                    hbb_common::log::warn!("Phone microphone capture stopped: {err}");
                }
            })?;
        Ok(Self(rx))
    }

    pub(super) async fn next(active: &mut Option<Self>) -> Option<Bytes> {
        match active {
            Some(active) => active.0.recv().await,
            None => std::future::pending().await,
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn record(packets: mpsc::Sender<Bytes>) -> ResultType<()> {
    let device = cpal::default_host()
        .default_input_device()
        .context("No microphone")?;
    #[cfg(target_os = "android")]
    // The pinned Oboe backend probes AudioRecord with output channel masks.
    // Request the standard mono voice input directly instead of probing for stereo.
    let (format, config) = (
        cpal::SampleFormat::I16,
        cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(44_100),
            buffer_size: cpal::BufferSize::Default,
        },
    );
    #[cfg(not(target_os = "android"))]
    let (format, config) = {
        let supported = device.default_input_config()?;
        (
            supported.sample_format(),
            cpal::StreamConfig::from(supported),
        )
    };
    let channels = usize::from(config.channels);
    if channels == 0 {
        hbb_common::bail!("Microphone has no input channels");
    }
    let mut resampler = crate::audio_resampler::FixedFrameAudioResampler::new(
        crate::audio_resampler::AudioResamplerConfig {
            input_rate: config.sample_rate.0,
            output_rate: 48_000,
            channels: 1,
        },
        960,
    )?;
    let mut encoder = Encoder::new(48_000, Channels::Mono, Application::Voip)?;
    if !matches!(
        format,
        cpal::SampleFormat::F32 | cpal::SampleFormat::I16 | cpal::SampleFormat::I32
    ) {
        hbb_common::bail!("Unsupported microphone input format: {format}");
    }
    let (pcm, capture) = sync::sync_channel(4);
    let failed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let failure = failed.clone();
    let stream = device.build_input_stream_raw(
        &config,
        format,
        move |data, _| {
            fn mono<T: cpal::SizedSample>(samples: &[T], channels: usize) -> Vec<f32>
            where
                f32: cpal::FromSample<T>,
            {
                samples
                    .chunks_exact(channels)
                    .map(|frame| {
                        frame.iter().map(|s| s.to_sample::<f32>()).sum::<f32>() / channels as f32
                    })
                    .collect()
            }
            let samples = match format {
                cpal::SampleFormat::F32 => data.as_slice::<f32>().map(|s| mono(s, channels)),
                cpal::SampleFormat::I16 => data.as_slice::<i16>().map(|s| mono(s, channels)),
                cpal::SampleFormat::I32 => data.as_slice::<i32>().map(|s| mono(s, channels)),
                _ => None,
            };
            if let Some(samples) = samples {
                let _ = pcm.try_send(samples);
            }
        },
        move |_| failure.store(true, std::sync::atomic::Ordering::Release),
        None,
    )?;
    stream.play()?;
    while !packets.is_closed() && !failed.load(std::sync::atomic::Ordering::Acquire) {
        match capture.recv_timeout(Duration::from_millis(50)) {
            Ok(samples) => {
                let mut encoded = Ok(());
                resampler.process_with(&samples, |frame| {
                    match encoder.encode_vec_float(frame, 1275) {
                        Ok(packet) => {
                            let _ = packets.try_send(Bytes::from(packet));
                        }
                        Err(err) => encoded = Err(err),
                    }
                })?;
                encoded?;
            }
            Err(sync::RecvTimeoutError::Timeout) => continue,
            Err(sync::RecvTimeoutError::Disconnected) => break,
        }
    }
    Ok(())
}

pub(super) fn accepts_server_message(
    msg: &base::message_proto::Message,
    playback: bool,
) -> bool {
    use base::message_proto::{message::Union, misc, permission_info::Permission};
    match msg.union.as_ref() {
        Some(
            Union::Hash(_)
            | Union::LoginResponse(_)
            | Union::VoiceCallResponse(_)
            | Union::TestDelay(_),
        ) => true,
        Some(Union::VoiceCallRequest(req)) => !req.is_connect,
        Some(Union::AudioFrame(_)) => playback,
        Some(Union::Misc(m)) => match m.union.as_ref() {
            Some(misc::Union::CloseReason(_)) => true,
            Some(misc::Union::AudioFormat(_)) => playback,
            Some(misc::Union::PermissionInfo(p)) => {
                p.permission.enum_value() == Ok(Permission::Audio)
            }
            _ => false,
        },
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::{
        AudioFormat, AudioFrame, Clipboard, FileAction, LoginResponse, Message, Misc, VideoFrame,
        VoiceCallResponse,
    };
    #[test]
    fn phone_microphone_session_receives_audio_only_when_playback_is_on() {
        let mut msg = Message::new();
        msg.set_login_response(LoginResponse::new());
        assert!(accepts_server_message(&msg, false));
        msg.set_voice_call_response(VoiceCallResponse::new());
        assert!(accepts_server_message(&msg, false));
        let mut misc = Misc::new();
        misc.set_audio_format(AudioFormat::new());
        msg.set_misc(misc);
        assert!(!accepts_server_message(&msg, false));
        assert!(accepts_server_message(&msg, true));
        msg.set_audio_frame(AudioFrame::new());
        assert!(!accepts_server_message(&msg, false));
        assert!(accepts_server_message(&msg, true));
        msg.set_file_action(FileAction::new());
        assert!(!accepts_server_message(&msg, true));
        msg.set_video_frame(VideoFrame::new());
        assert!(!accepts_server_message(&msg, true));
        msg.set_clipboard(Clipboard::new());
        assert!(!accepts_server_message(&msg, true));
    }
}
