import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../common.dart';
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
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              ListTile(
                title: Text(widget.id),
                subtitle: Text(status),
                leading: const Icon(Icons.headset_rounded),
              ),
              SwitchListTile(
                title: Text(translate('Use local microphone')),
                subtitle: voice == VoiceCallStatus.waitingForResponse
                    ? Text(translate('Waiting'))
                    : null,
                value: voice != VoiceCallStatus.notStarted && active,
                onChanged:
                    allowed && !_changingMicrophone ? _setMicrophone : null,
              ),
              SwitchListTile(
                title: Text(translate('Use as remote speaker')),
                subtitle: ready && !playbackSupported
                    ? Text(translate('Unsupported'))
                    : null,
                value: ready && permissions['phone-audio-playing'] == true,
                onChanged: allowed && playbackSupported
                    ? (enabled) => bind.sessionPeerOption(
                        sessionId: session.sessionId,
                        name: 'phone-audio-playback',
                        value: enabled ? 'Y' : 'N')
                    : null,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: active && !_disconnecting
                      ? () async {
                          setState(() => _disconnecting = true);
                          await PhoneMicrophone.disconnect(session);
                          if (context.mounted) Navigator.pop(context);
                        }
                      : null,
                  child: Text(translate('Disconnect')),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
