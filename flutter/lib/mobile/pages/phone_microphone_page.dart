import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../common.dart';
import '../../common/widgets/workspace.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../phone_microphone.dart';
import '../ios_p2p_diagnostics.dart';

class PhoneMicrophonePage extends StatefulWidget {
  const PhoneMicrophonePage(
      {super.key, required this.id, required this.session});
  final String id;
  final FFI session;

  static Future<void> open(BuildContext context, String peerId) async {
    final input = peerId.replaceAll(' ', '');
    if (input.isEmpty) return;
    final id = await bind.mainHandleRelayId(id: input);
    if (id.isEmpty || !context.mounted) return;
    final session = await PhoneMicrophone.startStandalone(id, id != input);
    if (session == null || !context.mounted) return;
    await showSession(context, id, session);
  }

  static Future<void> showSession(
      BuildContext context, String id, FFI session) async {
    if (session.closed || session.phoneAudioVisible) return;
    session.phoneAudioVisible = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PhoneMicrophonePage(id: id, session: session),
      ));
    } finally {
      session.phoneAudioVisible = false;
    }
  }

  @override
  State<PhoneMicrophonePage> createState() => _PhoneMicrophonePageState();
}

class _PhoneMicrophonePageState extends State<PhoneMicrophonePage> {
  FFI get session => widget.session;
  bool _changingMicrophone = false;
  bool _disconnecting = false;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  int _meterTick = 0;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _meterTick = (_meterTick + 1) % 4;
        _updateElapsed();
      });
    });
  }

  void _updateElapsed() {
    final opened = PhoneMicrophone.openedAt;
    _elapsed = opened == null ? Duration.zero : DateTime.now().difference(opened);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _setMicrophone(bool enabled) async {
    setState(() => _changingMicrophone = true);
    try {
      if (enabled) {
        if (!await PhoneMicrophone.prepare(session)) return;
        if (!mounted ||
            session.closed ||
            !identical(PhoneMicrophone.standalone, session)) {
          await PhoneMicrophone.stop(session);
          return;
        }
        await bind.sessionRequestPhoneMicrophone(sessionId: session.sessionId);
      } else {
        await bind.sessionCloseVoiceCall(sessionId: session.sessionId);
        await PhoneMicrophone.stop(session);
      }
    } finally {
      if (mounted) setState(() => _changingMicrophone = false);
    }
  }

  Future<void> _copyP2pDiagnostics() async {
    final opened = PhoneMicrophone.openedAt;
    try {
      final model = session.ffiModel;
      final path = formatIosMediaSample(
        opened: opened ?? DateTime.now(),
        now: DateTime.now(),
        direct: model.direct,
        transport: model.cachedPeerData.streamType,
      );
      final report = isIOS && recordIosP2pDiagnostics && opened != null
          ? await readIosP2pDiagnostics(
              await getApplicationDocumentsDirectory(), opened)
          : null;
      final quality = session.qualityMonitorModel;
      final sessionReports = {
        ...quality.udpReports,
        ...quality.localUdpReports.values,
      };
      if (!mounted || session.closed) return;
      await Clipboard.setData(ClipboardData(
          text: [
        'RustDesk audio session',
        path,
        ...sessionReports,
        if (report != null) 'iOS P2P timeline\n$report',
      ].join('\n')));
      if (mounted) showToast(translate('Copied'));
    } catch (_) {
      if (mounted) showToast(translate('Failed'));
    }
  }

  Future<void> _copyAudioDiagnostics() async {
    try {
      final report = await bind.sessionGetOption(
          sessionId: session.sessionId, arg: 'ios-remote-audio-report');
      if (!mounted || report == null || report.isEmpty) return;
      final route = await const MethodChannel('rustdesk/phone-microphone')
          .invokeMethod<String>('output-status')
          .catchError((Object _) => null);
      if (!mounted) return;
      await Clipboard.setData(
          ClipboardData(text: [report, if (route != null) route].join('\n')));
      if (mounted) showToast(translate('Copied'));
    } catch (_) {
      if (mounted) showToast(translate('Failed'));
    }
  }

  Future<void> _recordP2p() async {
    await bind.mainSetLocalOption(key: kOptionRecordP2pDiagnostics, value: 'Y');
    recordIosP2pDiagnostics = true;
    if (mounted) {
      setState(() {});
      showToast(translate('Reconnect'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Audio mode')),
        actions: [
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: _copyP2pDiagnostics,
                  child: Text(translate('Copy P2P diagnostics'))),
              if (isIOS)
                PopupMenuItem(
                    value: _copyAudioDiagnostics,
                    child: Text(translate('Diagnostics'))),
              if (isIOS && !recordIosP2pDiagnostics)
                PopupMenuItem(
                    value: _recordP2p,
                    child: Text(translate('Record P2P diagnostics'))),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: session.ffiModel,
        builder: (context, _) => Obx(() {
          final active = identical(PhoneMicrophone.standalone, session);
          final permissions = session.ffiModel.permissions;
          final ready = active && permissions['phone-audio-ready'] == true;
          final allowed =
              ready && permissions['audio'] != false && !_disconnecting;
          final playbackSupported =
              permissions['phone-audio-supported'] == true;
          final voice = session.chatModel.voiceCallStatus.value;
          final quality = session.qualityMonitorModel;
          final direct = quality.directConnection;
          final transport = quality.activeTransport;
          final status = ready && direct != null
              ? [
                  translate(direct ? 'Direct Connection' : 'Relay Connection'),
                  if (transport != null) transport,
                ].join(' · ')
              : translate(ready
                  ? 'Connected'
                  : active
                      ? 'Waiting'
                      : 'Disconnected');
          final micActive = voice == VoiceCallStatus.connected && active;
          final micRequested = voice != VoiceCallStatus.notStarted && active;
          final theme = Theme.of(context);
          final accent = micActive
              ? WorkspaceStyle.success(context)
              : theme.colorScheme.primary;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WorkspacePanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.headset_rounded, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.id,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                status,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (ready)
                          Text(
                            _formatDuration(_elapsed),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: theme.hintColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 5; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 4,
                              height: micActive
                                  ? 10.0 + ((i + _meterTick) % 4) * 6.0
                                  : 6.0,
                              decoration: BoxDecoration(
                                color: micActive ? accent : theme.dividerColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: micActive
                              ? WorkspaceStyle.success(context)
                              : theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: micActive
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                        onPressed: allowed && !_changingMicrophone
                            ? () => _setMicrophone(!micRequested)
                            : null,
                        child: Icon(
                          micActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              WorkspacePanel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(translate('Use local microphone')),
                      subtitle: voice == VoiceCallStatus.waitingForResponse
                          ? Text(translate('Waiting'))
                          : null,
                      value: micRequested,
                      onChanged: allowed && !_changingMicrophone
                          ? _setMicrophone
                          : null,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: Text(translate('Use as remote speaker')),
                      subtitle: ready && !playbackSupported
                          ? Text(translate('Unsupported'))
                          : null,
                      value:
                          ready && permissions['phone-audio-playing'] == true,
                      onChanged: allowed && playbackSupported
                          ? (enabled) => bind.sessionPeerOption(
                              sessionId: session.sessionId,
                              name: 'phone-audio-playback',
                              value: enabled ? 'Y' : 'N')
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: WorkspaceStyle.danger(context),
                  side: BorderSide(
                      color: WorkspaceStyle.danger(context).withOpacity(0.4)),
                ),
                icon: const Icon(Icons.call_end_rounded, size: 18),
                onPressed: active && !_disconnecting
                    ? () async {
                        setState(() => _disconnecting = true);
                        await PhoneMicrophone.disconnect(session);
                        if (context.mounted) Navigator.pop(context);
                      }
                    : null,
                label: Text(translate('Disconnect')),
              ),
            ],
          );
        }),
      ),
    );
  }
}
