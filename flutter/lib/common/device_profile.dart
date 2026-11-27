import 'dart:convert';

import 'package:flutter/material.dart';

import '../common.dart';
import '../models/platform_model.dart';

const String kDeviceProfilesOptionKey = 'local-device-profiles-v1';

class DeviceConnectionProfile {
  const DeviceConnectionProfile({
    this.defaultMode = 'remote',
    this.quality = 'default',
    this.privacyMode = false,
    this.enableAudio = true,
    this.forceRelay = false,
  });

  final String defaultMode; // remote | file | terminal
  final String quality; // default | best | balanced | low
  final bool privacyMode;
  final bool enableAudio;
  final bool forceRelay;

  bool get isDefault =>
      defaultMode == 'remote' &&
      quality == 'default' &&
      !privacyMode &&
      enableAudio &&
      !forceRelay;

  Map<String, dynamic> toJson() => {
        'mode': defaultMode,
        'quality': quality,
        'privacy': privacyMode,
        'audio': enableAudio,
        'force_relay': forceRelay,
      };

  static DeviceConnectionProfile fromJson(dynamic raw) {
    if (raw is! Map) return const DeviceConnectionProfile();
    final mode = (raw['mode'] ?? 'remote').toString();
    final quality = (raw['quality'] ?? 'default').toString();
    return DeviceConnectionProfile(
      defaultMode:
          const {'remote', 'file', 'terminal'}.contains(mode) ? mode : 'remote',
      quality: const {'default', 'best', 'balanced', 'low'}.contains(quality)
          ? quality
          : 'default',
      privacyMode: raw['privacy'] == true,
      enableAudio: raw['audio'] != false,
      forceRelay: raw['force_relay'] == true,
    );
  }
}

Map<String, DeviceConnectionProfile> loadAllDeviceProfiles() {
  final raw = bind.getLocalFlutterOption(k: kDeviceProfilesOptionKey).trim();
  if (raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): DeviceConnectionProfile.fromJson(entry.value),
    };
  } catch (_) {
    return {};
  }
}

DeviceConnectionProfile loadDeviceProfile(String peerId) =>
    loadAllDeviceProfiles()[peerId.trim()] ?? const DeviceConnectionProfile();

Future<void> saveDeviceProfile(
  String peerId,
  DeviceConnectionProfile profile,
) async {
  final id = peerId.trim();
  if (id.isEmpty) return;
  final all = loadAllDeviceProfiles();
  if (profile.isDefault && !all.containsKey(id)) return;
  all[id] = profile;
  await bind.setLocalFlutterOption(
    k: kDeviceProfilesOptionKey,
    v: jsonEncode({
      for (final entry in all.entries) entry.key: entry.value.toJson(),
    }),
  );
}

Future<DeviceConnectionProfile?> showDeviceProfileDialog(
  BuildContext context, {
  required String peerId,
  required String peerTitle,
}) async {
  var current = loadDeviceProfile(peerId);
  var mode = current.defaultMode;
  var quality = current.quality;
  var privacy = current.privacyMode;
  var audio = current.enableAudio;
  var forceRelay = current.forceRelay;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('$peerTitle · ${translate('Settings')}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: mode,
                decoration: InputDecoration(labelText: translate('Connect')),
                items: [
                  DropdownMenuItem(
                      value: 'remote', child: Text(translate('Connect'))),
                  DropdownMenuItem(
                      value: 'file', child: Text(translate('Transfer file'))),
                  DropdownMenuItem(
                      value: 'terminal', child: Text(translate('Terminal'))),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => mode = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: quality,
                decoration: InputDecoration(labelText: translate('Display')),
                items: [
                  DropdownMenuItem(
                      value: 'default', child: Text(translate('Default'))),
                  DropdownMenuItem(
                      value: 'best', child: Text(translate('Good image quality'))),
                  DropdownMenuItem(
                      value: 'balanced', child: Text(translate('Balanced'))),
                  DropdownMenuItem(
                      value: 'low',
                      child: Text(translate('Optimize reaction time'))),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => quality = v);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(translate('Enable audio')),
                value: audio,
                onChanged: (v) => setLocal(() => audio = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(translate('Privacy mode')),
                value: privacy,
                onChanged: (v) => setLocal(() => privacy = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(translate('Connect via relay')),
                value: forceRelay,
                onChanged: (v) => setLocal(() => forceRelay = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('OK')),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return null;
  final next = DeviceConnectionProfile(
    defaultMode: mode,
    quality: quality,
    privacyMode: privacy,
    enableAudio: audio,
    forceRelay: forceRelay,
  );
  await saveDeviceProfile(peerId, next);
  return next;
}
