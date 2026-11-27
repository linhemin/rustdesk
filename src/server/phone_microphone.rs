use crate::audio_resampler::{AudioResampler, AudioResamplerConfig};
use bytes::Bytes;
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    Device, SampleFormat, Stream, StreamConfig,
};
use hbb_common::{
    bail, log,
    tokio::{self, sync::oneshot},
    ResultType,
};
use magnum_opus::{Channels, Decoder};
use ringbuf::{HeapConsumer, HeapRb};
use std::{
    io,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{sync_channel, RecvTimeoutError, SyncSender, TrySendError},
        Arc,
    },
    time::Duration,
};

const INPUT_RATE: u32 = 48_000;
const PACKET_FRAMES: usize = 960;
static CABLE_IN_USE: AtomicBool = AtomicBool::new(false);

#[cfg(windows)]
pub(super) fn cable_in_use() -> bool {
    CABLE_IN_USE.load(Ordering::Acquire)
}

#[cfg(windows)]
pub(super) fn is_windows_cable_endpoint(name: &str) -> bool {
    let name = name.trim();
    let endpoint = match name.split_once(" (") {
        Some((endpoint, driver))
            if driver
                .rsplit_once("- ")
                .map_or(driver, |(_, name)| name)
                .eq_ignore_ascii_case("VB-Audio Virtual Cable)") =>
        {
            endpoint
        }
        Some(_) => return false,
        None => name,
    };
    ["CABLE Input", "CABLE In 16ch", "CABLE Output"]
        .iter()
        .any(|candidate| endpoint.eq_ignore_ascii_case(candidate))
}

struct CableLease;

impl Drop for CableLease {
    fn drop(&mut self) {
        CABLE_IN_USE.store(false, Ordering::Release);
    }
}

pub(super) struct Sink(SyncSender<Bytes>);

impl Sink {
    pub(super) async fn open() -> ResultType<Self> {
        if CABLE_IN_USE.swap(true, Ordering::AcqRel) {
            return Err(io::Error::new(io::ErrorKind::WouldBlock, "VB-CABLE is in use").into());
        }
        let lease = CableLease;
        let (tx, rx) = sync_channel::<Bytes>(3);
        let (ready_tx, ready_rx) = oneshot::channel();
        std::thread::Builder::new()
            .name("phone microphone".into())
            .spawn(move || {
                let _lease = lease;
                let (stream, mut producer, mut decoder, mut resampler, channels, failed) =
                    match open_playback() {
                        Ok(playback) => playback,
                        Err(error) => {
                            let _ = ready_tx.send(Err(error));
                            return;
                        }
                    };
                if ready_tx.send(Ok(())).is_err() {
                    return;
                }
                let _stream = stream;
                while !failed.load(Ordering::Acquire) {
                    let packet = match rx.recv_timeout(Duration::from_millis(100)) {
                        Ok(packet) => packet,
                        Err(RecvTimeoutError::Timeout) => continue,
                        Err(RecvTimeoutError::Disconnected) => break,
                    };
                    let decoded = match decode_packet(&mut decoder, &packet)
                        .and_then(|pcm| Ok(resampler.process(&pcm)?))
                    {
                        Ok(decoded) => decoded,
                        Err(error) => {
                            log::warn!("Phone microphone stopped: {error}");
                            break;
                        }
                    };
                    if decoded.len() / 2 * channels > producer.free_len() {
                        continue;
                    }
                    for stereo in decoded.chunks_exact(2) {
                        if channels == 1 {
                            producer.push((stereo[0] + stereo[1]) * 0.5).ok();
                        } else {
                            producer.push_slice(stereo);
                            for _ in 2..channels {
                                producer.push(0.0).ok();
                            }
                        }
                    }
                }
            })?;
        tokio::time::timeout(Duration::from_secs(4), ready_rx).await???;
        Ok(Self(tx))
    }

    pub(super) fn packet(&self, packet: Bytes) -> ResultType<()> {
        if packet.is_empty() || packet.len() > 1275 {
            bail!("Invalid phone microphone packet");
        }
        match self.0.try_send(packet) {
            Ok(()) | Err(TrySendError::Full(_)) => Ok(()),
            Err(TrySendError::Disconnected(_)) => bail!("Phone microphone stopped"),
        }
    }
}

fn is_cable_playback(name: &str, macos: bool) -> bool {
    let name = name.trim().to_ascii_lowercase();
    if macos {
        name == "vb-cable" || name.starts_with("vb-cable (")
    } else {
        name == "cable input"
            || (name.starts_with("cable input (") && name.contains("vb-audio virtual cable"))
    }
}

fn open_playback() -> ResultType<(
    Stream,
    ringbuf::HeapProducer<f32>,
    Decoder,
    AudioResampler,
    usize,
    Arc<AtomicBool>,
)> {
    let device = cpal::default_host()
        .output_devices()?
        .find(|device| {
            device
                .name()
                .is_ok_and(|name| is_cable_playback(&name, cfg!(target_os = "macos")))
        })
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "VB-CABLE playback device is missing",
            )
        })?;
    let supported = device.default_output_config()?;
    let sample_format = supported.sample_format();
    let config: StreamConfig = supported.into();
    let channels = usize::from(config.channels);
    let sample_rate = config.sample_rate.0;
    let decoder = Decoder::new(INPUT_RATE, Channels::Stereo)?;
    let resampler = AudioResampler::new(AudioResamplerConfig {
        input_rate: INPUT_RATE,
        output_rate: sample_rate,
        channels: 2,
    })?;
    let capacity = (sample_rate as usize / 10) * channels;
    if capacity == 0 {
        bail!("Invalid VB-CABLE output configuration");
    }
    let (producer, consumer) = HeapRb::<f32>::new(capacity).split();
    let failed = Arc::new(AtomicBool::new(false));
    let stream = match sample_format {
        SampleFormat::F32 => make_stream::<f32>(&device, &config, consumer, failed.clone()),
        SampleFormat::F64 => make_stream::<f64>(&device, &config, consumer, failed.clone()),
        SampleFormat::I16 => make_stream::<i16>(&device, &config, consumer, failed.clone()),
        SampleFormat::I32 => make_stream::<i32>(&device, &config, consumer, failed.clone()),
        SampleFormat::U16 => make_stream::<u16>(&device, &config, consumer, failed.clone()),
        format => bail!("Unsupported VB-CABLE sample format: {format:?}"),
    }?;
    stream.play()?;
    Ok((stream, producer, decoder, resampler, channels, failed))
}

fn make_stream<T: cpal::SizedSample + cpal::FromSample<f32>>(
    device: &Device,
    config: &StreamConfig,
    mut consumer: HeapConsumer<f32>,
    failed: Arc<AtomicBool>,
) -> ResultType<Stream> {
    Ok(device.build_output_stream(
        config,
        move |output: &mut [T], _| {
            for sample in output {
                *sample = T::from_sample(consumer.pop().unwrap_or(0.0));
            }
        },
        move |error| {
            if !failed.swap(true, Ordering::AcqRel) {
                log::warn!("VB-CABLE playback stopped: {error}");
            }
        },
        None,
    )?)
}

fn decode_packet(decoder: &mut Decoder, packet: &[u8]) -> ResultType<[f32; PACKET_FRAMES * 2]> {
    let mut samples = [0.0f32; PACKET_FRAMES * 2];
    if decoder.decode_float(packet, &mut samples, false)? != PACKET_FRAMES {
        bail!("Phone microphone requires 20 ms audio frames");
    }
    Ok(samples)
}

#[cfg(test)]
mod tests {
    use super::*;
    use magnum_opus::{Application, Encoder};

    #[test]
    fn cable_selection_uses_only_the_standard_playback_endpoint() {
        assert!(is_cable_playback(
            "CABLE Input (VB-Audio Virtual Cable)",
            false
        ));
        assert!(is_cable_playback("VB-Cable", true));
        assert!(!is_cable_playback(
            "CABLE Output (VB-Audio Virtual Cable)",
            false
        ));
        assert!(!is_cable_playback(
            "CABLE-A Input (VB-Audio Cable A)",
            false
        ));
        assert!(!is_cable_playback("VB-Cable A", true));
        assert!(!is_cable_playback("MacBook Speakers", true));
    }

    #[cfg(windows)]
    #[test]
    fn phone_cable_is_excluded_from_return_audio() {
        for endpoint in [
            "CABLE Output",
            "CABLE Input (VB-Audio Virtual Cable)",
            "CABLE In 16ch (VB-Audio Virtual Cable)",
            "CABLE Output (2- VB-Audio Virtual Cable)",
        ] {
            assert!(is_windows_cable_endpoint(endpoint));
        }
        assert!(!is_windows_cable_endpoint("Speakers (Realtek Audio)"));
        assert!(!is_windows_cable_endpoint("CABLE-A Output (VB-Audio Cable A)"));
    }

    #[test]
    fn phone_voice_decodes_to_stereo_and_preserves_twenty_ms_frames() {
        let mut encoder = Encoder::new(INPUT_RATE, Channels::Mono, Application::Voip).unwrap();
        let voice: Vec<_> = (0..PACKET_FRAMES)
            .map(|i| (i as f32 * 0.06).sin() * 0.4)
            .collect();
        let packet = encoder.encode_vec_float(&voice, 1275).unwrap();
        let mut decoder = Decoder::new(INPUT_RATE, Channels::Stereo).unwrap();
        let pcm = decode_packet(&mut decoder, &packet).unwrap();
        assert!(pcm.iter().any(|s| s.abs() > 0.05));
        assert!(pcm.chunks_exact(2).all(|frame| frame[0] == frame[1]));
        let short = encoder.encode_vec_float(&voice[..480], 1275).unwrap();
        assert!(decode_packet(&mut decoder, &short).is_err());
    }
}
