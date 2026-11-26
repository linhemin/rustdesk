import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

int? savedBitrateKbps(num? quality) {
  final kbps = (quality?.toInt() ?? 0) - kBitrateKbpsBase;
  return kbps >= 500 && kbps <= 200000 ? kbps : null;
}

class BitrateLimitDropdown extends StatelessWidget {
  const BitrateLimitDropdown({super.key, required this.kbps, this.onChanged});

  final int? kbps;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: kbps,
      hint: const Text('—'),
      onChanged: onChanged,
      items: [
        for (final rate in _bitrateSteps(kbps))
          DropdownMenuItem(value: rate, child: Text(_bitrateLabel(rate))),
      ],
    );
  }
}

String _bitrateLabel(int rate) =>
    '${rate % 1000 == 0 ? rate ~/ 1000 : rate / 1000} Mbps';

List<int> _bitrateSteps(int? kbps) => {
      500,
      1000,
      2000,
      3000,
      5000,
      8000,
      10000,
      15000,
      20000,
      25000,
      30000,
      40000,
      50000,
      60000,
      75000,
      100000,
      125000,
      150000,
      200000,
      if (kbps != null) kbps,
    }.toList()
      ..sort();

// A DropdownRoute lives below the session's OverlayEntry. Keep this picker
// in the editor so its choices share the same focus, scroll and hit testing.
class MobileBitratePicker extends StatefulWidget {
  const MobileBitratePicker({
    super.key,
    required this.kbps,
    required this.unlimited,
    required this.legacyQuality,
    required this.onChanged,
  });

  final int? kbps;
  final bool unlimited;
  final int legacyQuality;
  final ValueChanged<int?>? onChanged;

  @override
  State<MobileBitratePicker> createState() => _MobileBitratePickerState();
}

class _MobileBitratePickerState extends State<MobileBitratePicker> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.unlimited
        ? translate('No bitrate cap')
        : widget.kbps == null
            ? '${widget.legacyQuality}%'
            : _bitrateLabel(widget.kbps!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(translate(!widget.unlimited && widget.kbps == null
            ? 'Custom Image Quality'
            : 'Bitrate limit')),
        subtitle: Text(label),
        trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        onTap: widget.onChanged == null
            ? null
            : () => setState(() => _expanded = !_expanded),
      ),
      if (_expanded)
        Wrap(spacing: 6, runSpacing: 2, children: [
          for (final rate in <int?>[null, ..._bitrateSteps(widget.kbps)])
            ChoiceChip(
              label: Text(rate == null
                  ? translate('No bitrate cap')
                  : _bitrateLabel(rate)),
              showCheckmark: true,
              selectedColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.16),
              selected: rate == null
                  ? widget.unlimited
                  : !widget.unlimited && widget.kbps == rate,
              onSelected: widget.onChanged == null
                  ? null
                  : (_) {
                      setState(() => _expanded = false);
                      widget.onChanged!(rate);
                    },
            ),
        ]),
    ]);
  }
}

customImageQualityWidget(
    {required double initQuality,
    required double initFps,
    required Function(double)? setQuality,
    required Function(double)? setFps,
    required bool showFps,
    required bool showMoreQuality,
    required bool actualBitrate}) {
  final autoBitrate = (!isWeb && initQuality == kAutoBitrate).obs;
  final bitrateKbps = RxnInt(savedBitrateKbps(initQuality));
  if (autoBitrate.value ||
      initQuality < kMinQuality ||
      initQuality > (showMoreQuality ? kMaxMoreQuality : kMaxQuality)) {
    initQuality = kDefaultQuality;
  }
  if (initFps < kMinFps || initFps > kMaxFps) {
    initFps = kDefaultFps;
  }
  final qualityValue = initQuality.obs;
  final fpsValue = initFps.obs;

  final RxBool moreQualityChecked = RxBool(qualityValue.value > kMaxQuality);
  final debouncerQuality = Debouncer<double>(
    Duration(milliseconds: 1000),
    onChanged: (value) {
      if (!autoBitrate.value && value == qualityValue.value) {
        setQuality?.call(value);
      }
    },
    initialValue: qualityValue.value,
  );
  final debouncerFps = Debouncer<double>(
    Duration(milliseconds: 1000),
    onChanged: setFps,
    initialValue: fpsValue.value,
  );

  onMoreChanged(bool? value) {
    if (value == null) return;
    moreQualityChecked.value = value;
    if (!value && qualityValue.value > 100) {
      qualityValue.value = 100;
    }
    debouncerQuality.value = qualityValue.value;
  }

  return Column(
    children: [
      if (actualBitrate && isMobile)
        Obx(() => MobileBitratePicker(
              kbps: bitrateKbps.value,
              unlimited: autoBitrate.value,
              legacyQuality: qualityValue.value.round(),
              onChanged: setQuality == null
                  ? null
                  : (value) {
                      autoBitrate.value = value == null;
                      if (value != null) bitrateKbps.value = value;
                      setQuality(value == null
                          ? kAutoBitrate
                          : kBitrateKbpsBase + value.toDouble());
                    },
            )),
      if (actualBitrate && !isMobile)
        Obx(() => ListTile(
              title: Text(translate('Bitrate limit')),
              trailing: BitrateLimitDropdown(
                kbps: bitrateKbps.value,
                onChanged: autoBitrate.value || setQuality == null
                    ? null
                    : (value) {
                        if (value == null) return;
                        bitrateKbps.value = value;
                        setQuality(kBitrateKbpsBase + value.toDouble());
                      },
              ),
            )),
      if (!actualBitrate)
        Obx(() => Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: qualityValue.value,
                    min: kMinQuality,
                    max: moreQualityChecked.value
                        ? kMaxMoreQuality
                        : kMaxQuality,
                    divisions: moreQualityChecked.value
                        ? ((kMaxMoreQuality - kMinQuality) / 10).round()
                        : ((kMaxQuality - kMinQuality) / 5).round(),
                    onChanged: setQuality == null || autoBitrate.value
                        ? null
                        : (double value) async {
                            qualityValue.value = value;
                            debouncerQuality.value = value;
                          },
                  ),
                ),
                Expanded(
                    flex: 1,
                    child: Text(
                      '${qualityValue.value.round()}%',
                      style: const TextStyle(fontSize: 15),
                    )),
                Expanded(
                    flex: isMobile ? 2 : 1,
                    child: Text(
                      translate('Bitrate'),
                      style: const TextStyle(fontSize: 15),
                    )),
                // mobile doesn't have enough space
                if (showMoreQuality && !isMobile)
                  Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Checkbox(
                            value: moreQualityChecked.value,
                            onChanged: autoBitrate.value ? null : onMoreChanged,
                          ),
                          Expanded(
                            child: Text(translate('More')),
                          )
                        ],
                      ))
              ],
            )),
      if (!actualBitrate && showMoreQuality && isMobile)
        Obx(() => Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Checkbox(
                      value: moreQualityChecked.value,
                      onChanged: autoBitrate.value ? null : onMoreChanged,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(translate('More')),
                )
              ],
            )),
      if (!isWeb && !(actualBitrate && isMobile))
        Obx(() => CheckboxListTile(
              title: Text(translate('No bitrate cap')),
              value: autoBitrate.value,
              onChanged: setQuality == null
                  ? null
                  : (value) {
                      if (value == null) return;
                      autoBitrate.value = value;
                      if (actualBitrate && !value) {
                        bitrateKbps.value ??= kDefaultBitrateKbps;
                      }
                      setQuality(value
                          ? kAutoBitrate
                          : actualBitrate
                              ? kBitrateKbpsBase + bitrateKbps.value!.toDouble()
                              : qualityValue.value);
                    },
              controlAffinity: ListTileControlAffinity.leading,
            )),
      if (showFps)
        Obx(() => Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: fpsValue.value,
                    min: kMinFps,
                    max: kMaxFps,
                    divisions: ((kMaxFps - kMinFps) / 5).round(),
                    onChanged: setFps == null
                        ? null
                        : (double value) async {
                            fpsValue.value = value;
                            debouncerFps.value = value;
                          },
                  ),
                ),
                Expanded(
                    flex: 1,
                    child: Text(
                      '${fpsValue.value.round()}',
                      style: const TextStyle(fontSize: 15),
                    )),
                Expanded(
                    flex: 2,
                    child: Text(
                      translate('FPS'),
                      style: const TextStyle(fontSize: 15),
                    ))
              ],
            )),
    ],
  );
}

customImageQualitySetting() {
  final qualityKey = 'custom_image_quality';
  final fpsKey = 'custom-fps';

  final legacyQuality =
      double.tryParse(bind.mainGetUserDefaultOption(key: qualityKey)) ??
          kDefaultQuality;
  final actualBitrate = !isWeb && !isOptionFixed(qualityKey);
  final settingKey = actualBitrate ? kKeyCustomVideoBitrate : qualityKey;
  final initQuality =
      double.tryParse(bind.mainGetUserDefaultOption(key: settingKey)) ??
          legacyQuality;
  final isQualityFixed = isOptionFixed(settingKey);
  final initFps =
      (double.tryParse(bind.mainGetUserDefaultOption(key: fpsKey)) ??
          kDefaultFps);
  final isFpsFixed = isOptionFixed(fpsKey);

  return customImageQualityWidget(
      initQuality: initQuality,
      initFps: initFps,
      setQuality: isQualityFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(
                  key: settingKey, value: v.round().toString());
            },
      setFps: isFpsFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(key: fpsKey, value: v.toString());
            },
      showFps: true,
      showMoreQuality: true,
      actualBitrate: actualBitrate);
}

List<Widget> ServerConfigImportExportWidgets(
  List<TextEditingController> controllers,
  List<RxString> errMsgs,
) {
  import() {
    Clipboard.getData(Clipboard.kTextPlain).then((value) {
      importConfig(controllers, errMsgs, value?.text);
    });
  }

  export() {
    try {
      final text = ServerConfig(
              idServer: controllers[0].text.trim(),
              relayServer: controllers[1].text.trim(),
              apiServer: controllers[2].text.trim(),
              key: controllers[3].text.trim())
          .encode();
      Clipboard.setData(ClipboardData(text: text));
      showToast(translate('Export server configuration successfully'));
    } on FormatException catch (e) {
      errMsgs[1].value = translate(e.message);
    }
  }

  return [
    Tooltip(
      message: translate('Import server config'),
      child: IconButton(
          icon: Icon(Icons.paste, color: Colors.grey), onPressed: import),
    ),
    Tooltip(
        message: translate('Export Server Config'),
        child: IconButton(
            icon: Icon(Icons.copy, color: Colors.grey), onPressed: export))
  ];
}

List<(String, String)> otherDefaultSettings() {
  List<(String, String)> v = [
    ('View Mode', kOptionViewOnly),
    if ((isDesktop || isWebDesktop))
      ('show_monitors_tip', kKeyShowMonitorsToolbar),
    if ((isDesktop || isWebDesktop))
      ('Collapse toolbar', kOptionCollapseToolbar),
    ('Show remote cursor', kOptionShowRemoteCursor),
    ('Follow remote cursor', kOptionFollowRemoteCursor),
    ('Follow remote window focus', kOptionFollowRemoteWindow),
    if ((isDesktop || isWebDesktop)) ('Zoom cursor', kOptionZoomCursor),
    ('Show quality monitor', kOptionShowQualityMonitor),
    ('Mute', kOptionDisableAudio),
    if (isDesktop) ('Enable file copy and paste', kOptionEnableFileCopyPaste),
    ('Disable clipboard', kOptionDisableClipboard),
    ('Lock after session end', kOptionLockAfterSessionEnd),
    ('Privacy mode', kOptionPrivacyMode),
    ('True color (4:4:4)', kOptionI444),
    ('Reverse mouse wheel', kKeyReverseMouseWheel),
    ('swap-left-right-mouse', kOptionSwapLeftRightMouse),
    if (isDesktop)
      (
        'Show displays as individual windows',
        kKeyShowDisplaysAsIndividualWindows
      ),
    if (isDesktop)
      (
        'Use all my displays for the remote session',
        kKeyUseAllMyDisplaysForTheRemoteSession
      ),
    ('Keep terminal sessions on disconnect', kOptionTerminalPersistent),
    (
      'Allow terminal apps to copy to clipboard',
      kOptionAllowTerminalClipboardWrite
    ),
  ];

  return v;
}

String getOtherDefaultSettingOption(String key) {
  if (key == kOptionAllowTerminalClipboardWrite) {
    return bind.mainGetLocalOption(key: key);
  }
  return bind.mainGetUserDefaultOption(key: key);
}

Future<void> setOtherDefaultSettingOption(String key, String value) {
  if (key == kOptionAllowTerminalClipboardWrite) {
    return bind.mainSetLocalOption(
      key: key,
      value: value == kTerminalClipboardWriteAllowed
          ? kTerminalClipboardWriteAllowed
          : kTerminalClipboardWriteDenied,
    );
  }
  return bind.mainSetUserDefaultOption(key: key, value: value);
}

bool isOtherDefaultSettingReadOnly(String key) =>
    isOptionFixed(key) ||
    (key == kOptionAllowTerminalClipboardWrite && bind.isDisableSettings());

class TrackpadSpeedWidget extends StatefulWidget {
  final SimpleWrapper<int> value;
  // If null, no debouncer will be applied.
  final Function(int)? onDebouncer;
  final ValueChanged<String>? onTextChanged;
  // IME actions call TextField.onSubmitted without reaching the dialog's
  // raw Enter handler, so the dialog needs a separate submission callback.
  final ValueChanged<String>? onTextSubmitted;

  TrackpadSpeedWidget({
    Key? key,
    required this.value,
    this.onDebouncer,
    this.onTextChanged,
    this.onTextSubmitted,
  });

  @override
  TrackpadSpeedWidgetState createState() => TrackpadSpeedWidgetState();
}

class TrackpadSpeedWidgetState extends State<TrackpadSpeedWidget> {
  final TextEditingController _controller = TextEditingController();
  late final Debouncer<int> debouncerSpeed;

  set value(int v) => widget.value.value = v;
  int get value => widget.value.value;

  void updateValue(int newValue) {
    setState(() {
      value = newValue.clamp(kMinTrackpadSpeed, kMaxTrackpadSpeed);
      // Scale the trackpad speed value to a percentage for display purposes.
      _controller.text = value.toString();
      if (widget.onDebouncer != null) {
        debouncerSpeed.setValue(value);
      }
    });
    widget.onTextChanged?.call(_controller.text);
  }

  void updateTextValue(String text) {
    widget.onTextChanged?.call(text);
    final newValue = int.tryParse(text);
    if (newValue == null ||
        newValue < kMinTrackpadSpeed ||
        newValue > kMaxTrackpadSpeed) {
      return;
    }
    setState(() => value = newValue);
  }

  void submitTextValue(String text) {
    final onTextSubmitted = widget.onTextSubmitted;
    if (onTextSubmitted != null) {
      onTextSubmitted(text);
      return;
    }
    if (widget.onTextChanged != null) {
      return;
    }
    final newValue = int.tryParse(text);
    if (newValue == null) {
      return;
    }
    updateValue(newValue);
  }

  @override
  void initState() {
    super.initState();
    debouncerSpeed = Debouncer<int>(
      Duration(milliseconds: 1000),
      onChanged: widget.onDebouncer,
      initialValue: widget.value.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.text.isEmpty) {
      _controller.text = value.toString();
    }
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Slider(
            value: value.toDouble(),
            min: kMinTrackpadSpeed.toDouble(),
            max: kMaxTrackpadSpeed.toDouble(),
            divisions: ((kMaxTrackpadSpeed - kMinTrackpadSpeed) / 10).round(),
            onChanged: (double v) => updateValue(v.round()),
          ),
        ),
        Expanded(
            flex: 1,
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: updateTextValue,
                    onSubmitted: submitTextValue,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    ),
                  ),
                ).marginOnly(right: 8.0),
                Text(
                  '%',
                  style: const TextStyle(fontSize: 15),
                )
              ],
            )),
      ],
    );
  }
}
