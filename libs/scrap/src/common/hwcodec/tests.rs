use super::{CodecInfo, HwCodecConfig, HwRamEncoder, CONFIG, CONFIG_SET_BY_IPC};
use crate::{
    codec::{enable_vram_option, Encoder, EncodingUpdate},
    vram::{VRamDecoder, VRamEncoder},
    AdapterDevice, CodecFormat,
};
use base::config::keys::{OPTION_ALLOW_D3D_RENDER, OPTION_ENABLE_HWCODEC};
use base::message_proto::{supported_decoding::PreferCodec, SupportedDecoding};
use hbb_common::config::{OVERWRITE_LOCAL_SETTINGS, OVERWRITE_SETTINGS};
use hwcodec::{
    common::{DataFormat, Driver},
    vram::{DecodeContext, FeatureContext},
};
use std::{collections::HashMap, mem, sync::Mutex};

static CONFIG_TEST_LOCK: Mutex<()> = Mutex::new(());

struct RestoreConfig {
    config: Option<HwCodecConfig>,
    set_by_ipc: bool,
    options: HashMap<String, String>,
    local_options: HashMap<String, String>,
}

impl Drop for RestoreConfig {
    fn drop(&mut self) {
        *CONFIG.lock().unwrap() = self.config.take();
        *CONFIG_SET_BY_IPC.lock().unwrap() = self.set_by_ipc;
        *OVERWRITE_SETTINGS.write().unwrap() = mem::take(&mut self.options);
        *OVERWRITE_LOCAL_SETTINGS.write().unwrap() = mem::take(&mut self.local_options);
    }
}

fn add_backend(config: &mut HwCodecConfig, driver: Driver, vendor: Driver, format: DataFormat) {
    let luid = match vendor {
        Driver::NV => 1,
        Driver::MFX => 2,
        Driver::AMF => 3,
        _ => unreachable!(),
    };
    config.vram_encode.push(FeatureContext {
        driver: driver.clone(),
        vendor: vendor.clone(),
        luid,
        data_format: format,
    });
    config.vram_decode.push(DecodeContext {
        device: None,
        driver,
        vendor,
        luid,
        data_format: format,
    });
}

#[test]
fn cached_sdk_entries_are_ignored_before_check_completes() {
    let _test = CONFIG_TEST_LOCK.lock().unwrap();
    let _restore = RestoreConfig {
        config: CONFIG.lock().unwrap().take(),
        set_by_ipc: mem::replace(&mut *CONFIG_SET_BY_IPC.lock().unwrap(), false),
        options: mem::take(&mut *OVERWRITE_SETTINGS.write().unwrap()),
        local_options: mem::take(&mut *OVERWRITE_LOCAL_SETTINGS.write().unwrap()),
    };
    OVERWRITE_SETTINGS
        .write()
        .unwrap()
        .insert(OPTION_ENABLE_HWCODEC.into(), "Y".into());
    OVERWRITE_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert(OPTION_ALLOW_D3D_RENDER.into(), "Y".into());
    assert!(enable_vram_option(false));

    let formats = [
        (CodecFormat::H264, DataFormat::H264),
        (CodecFormat::H265, DataFormat::H265),
    ];
    let mut cached = HwCodecConfig::default();
    for (_, format) in formats {
        // A RAM fallback keeps this selection test independent of attached displays.
        cached.ram_encode.push(CodecInfo {
            format,
            ..Default::default()
        });
        for vendor in [Driver::NV, Driver::MFX, Driver::AMF] {
            add_backend(&mut cached, vendor.clone(), vendor, format);
        }
    }
    *CONFIG.lock().unwrap() = Some(cached.clone());
    assert!(!HwCodecConfig::already_set());
    for (format, _) in formats {
        assert!(VRamEncoder::available(format).is_empty());
        for luid in 1..=3 {
            assert!(VRamDecoder::try_get(format, Some(luid)).is_none());
        }
    }
    assert_eq!(
        VRamDecoder::possible_available_without_check(),
        (false, false)
    );

    for (index, &(format, data_format)) in formats.iter().enumerate() {
        for vendor in [Driver::NV, Driver::MFX, Driver::AMF] {
            add_backend(&mut cached, Driver::FFMPEG, vendor, data_format);
        }
        *CONFIG.lock().unwrap() = Some(cached.clone());
        let encoders = VRamEncoder::available(format);
        assert_eq!(encoders.len(), 3);
        for encoder in encoders {
            assert_eq!(encoder.driver, Driver::FFMPEG);
            let device = AdapterDevice {
                luid: encoder.luid,
                ..Default::default()
            };
            assert_eq!(VRamEncoder::try_get(&device, format), Some(encoder.clone()));
            let decoder = VRamDecoder::try_get(format, Some(encoder.luid)).unwrap();
            assert_eq!(decoder.driver, Driver::FFMPEG);
            assert_eq!(decoder.vendor, encoder.vendor);
            assert_eq!(decoder.data_format, data_format);
        }
        assert!(VRamDecoder::available(format, Some(99)).is_empty());
        assert!(VRamDecoder::available(format, None).is_empty());
        assert_eq!(
            VRamDecoder::possible_available_without_check(),
            (true, index == 1)
        );
    }
    assert!(!HwCodecConfig::already_set());
    assert_eq!(
        HwCodecConfig::get().vram_encode.len(),
        cached.vram_encode.len()
    );
}

#[test]
fn amd_encoder_failure_preserves_other_formats_and_adapter_backends() {
    let _test = CONFIG_TEST_LOCK.lock().unwrap();
    let _restore = RestoreConfig {
        config: CONFIG.lock().unwrap().take(),
        set_by_ipc: *CONFIG_SET_BY_IPC.lock().unwrap(),
        options: OVERWRITE_SETTINGS.read().unwrap().clone(),
        local_options: OVERWRITE_LOCAL_SETTINGS.read().unwrap().clone(),
    };
    let mut config = HwCodecConfig::default();
    config.ram_encode = IntoIterator::into_iter([
        ("h264_qsv", DataFormat::H264),
        ("h264_amf", DataFormat::H264),
        ("hevc_amf", DataFormat::H265),
    ])
    .map(|(name, format)| CodecInfo {
        name: name.to_owned(),
        format,
        ..Default::default()
    })
    .collect();
    add_backend(&mut config, Driver::FFMPEG, Driver::AMF, DataFormat::H264);
    add_backend(&mut config, Driver::FFMPEG, Driver::AMF, DataFormat::H265);
    let amd_texture = config.vram_encode[0].clone();
    *CONFIG.lock().unwrap() = Some(config);
    OVERWRITE_SETTINGS
        .write()
        .unwrap()
        .insert(OPTION_ENABLE_HWCODEC.into(), "Y".into());

    for (prefer, expected) in [
        (PreferCodec::Auto, CodecFormat::H265),
        (PreferCodec::PreferHardware, CodecFormat::H265),
        (PreferCodec::H264, CodecFormat::H264),
    ] {
        Encoder::update(EncodingUpdate::Update(
            1,
            SupportedDecoding {
                ability_vp9: 1,
                ability_h264: 1,
                ability_h265: 1,
                prefer: prefer.into(),
                ..Default::default()
            },
        ));
        let selected = Encoder::negotiated_codec();
        Encoder::update(EncodingUpdate::Remove(1));
        assert_eq!(selected, expected);
    }

    let amd = AdapterDevice {
        luid: amd_texture.luid,
        vendor_id: 0x1002,
        ..Default::default()
    };
    assert_eq!(
        VRamEncoder::try_get(&amd, CodecFormat::H264),
        Some(amd_texture.clone())
    );
    HwCodecConfig::remove_texture_encoder(&amd_texture);
    assert!(VRamEncoder::try_get(&amd, CodecFormat::H264).is_none());
    assert!(VRamEncoder::try_get(&amd, CodecFormat::H265).is_some());
    assert_eq!(
        HwRamEncoder::try_get_for_adapter(CodecFormat::H264, amd.vendor_id)
            .unwrap()
            .name,
        "h264_amf"
    );

    HwRamEncoder::disable_candidate("h264_amf");
    assert_eq!(
        HwRamEncoder::try_get_for_adapter(CodecFormat::H264, amd.vendor_id)
            .unwrap()
            .name,
        "h264_qsv"
    );
    assert_eq!(
        HwRamEncoder::try_get_for_adapter(CodecFormat::H265, amd.vendor_id)
            .unwrap()
            .name,
        "hevc_amf"
    );
}

#[test]
#[ignore = "Requires a working hardware encoder"]
fn windows_hardware_probe_finds_a_working_h26x_encoder() {
    let config: HwCodecConfig =
        hbb_common::serde_json::from_str(&super::check_available_hwcodec()).unwrap();
    eprintln!("RAM encoders: {:?}", config.ram_encode);
    eprintln!("Texture encoders: {:?}", config.vram_encode);
    assert!(!config.ram_encode.is_empty() || !config.vram_encode.is_empty());
}
