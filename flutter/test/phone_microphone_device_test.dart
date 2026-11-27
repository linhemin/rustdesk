import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/mobile_remote_sessions.dart';
import 'package:flutter_hbb/mobile/pages/connection_page.dart';
import 'package:flutter_hbb/mobile/pages/phone_microphone_page.dart';
import 'package:flutter_hbb/mobile/pages/remote_page.dart';
import 'package:flutter_hbb/mobile/phone_microphone.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/utils/image.dart';
import 'package:flutter_test/flutter_test.dart' hide isWindows;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class _Binding extends Fake implements RustdeskImpl {
  _Binding({this.audioAvailable = false});

  final bool audioAvailable;
  final relayIds = <String>[];
  final disconnected = <int>[];
  final speakerOptions = <String>[];

  @override
  bool sessionPreparePhoneMicrophone(
          {required UuidValue sessionId,
          required String id,
          required bool forceRelay,
          dynamic hint}) =>
      audioAvailable;

  @override
  Stream<EventToUI> sessionStart(
          {required UuidValue sessionId, required String id, dynamic hint}) =>
      const Stream.empty();

  @override
  Future<void> sessionPeerOption(
      {required UuidValue sessionId,
      required String name,
      required String value,
      dynamic hint}) async {
    if (name == 'phone-audio-playback') speakerOptions.add(value);
  }

  @override
  Future<void> cmCloseConnection({required int connId, dynamic hint}) async {
    disconnected.add(connId);
  }

  @override
  Future<String> mainHandleRelayId({required String id, dynamic hint}) async {
    relayIds.add(id);
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #translate => call.namedArguments[#name],
        #mainGetBuildinOption ||
        #getLocalFlutterOption ||
        #mainGetLocalOption =>
          '',
        #cmCheckClickTime => Future<void>.value(),
        #cmGetClickTime => Future.value(0.0),
        #cmCanElevate => false,
        #mainGetFav => Future.value(<String>[]),
        #mainPeerHasPassword => Future.value(true),
        #mainGetPeerOption => Future.value(''),
        #sessionGetTrackpadSpeed => Future<int?>.value(),
        #sessionGetViewStyle ||
        #sessionGetScrollStyle =>
          Future<String?>.value(),
        #sessionGetEdgeScrollEdgeThickness => Future<int?>.value(),
        #sessionClose || #sessionSendMouse => Future<void>.value(),
        #mainHasGpuTextureRender || #mainGetUseTextureRender => false,
        #isDisableAb || #isDisableAccount || #isDisableGroupPanel => false,
        _ => super.noSuchMethod(call),
      };
}

void main() {
  testWidgets('the iPhone device card opens the microphone for the saved peer',
      (tester) async {
    isTest = true;
    final wasMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = wasMobile);
    final binding = _Binding();
    platformFFI.setBindingForTesting(binding);
    await initGlobalFFI();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final peer = Peer.fromJson({
      'id': '123456789',
      'platform': 'Windows',
      'alias': 'Studio PC',
    });
    await tester.pumpWidget(ChangeNotifierProvider<PeerTabModel>.value(
      value: gFFI.peerTabModel,
      child: MaterialApp(
        theme: MyTheme.lightTheme.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(height: 72, child: RecentPeerCard(peer: peer)),
          ),
        ),
      ),
    ));
    final action = find.widgetWithIcon(IconButton, Icons.headset_mic_outlined);
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(binding.relayIds, [peer.id]);

    tester.view.physicalSize = const Size(402, 874);
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.more_horiz));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio mode'));
    await tester.pumpAndSettle();
    expect(binding.relayIds, [peer.id, peer.id]);
  });

  testWidgets('multiple remote sessions keep one independent audio session',
      (tester) async {
    isTest = true;
    final binding = _Binding(audioAvailable: true);
    platformFFI.setBindingForTesting(binding);
    await initGlobalFFI();
    final audio = (await PhoneMicrophone.startStandalone('333333333', false))!;
    addTearDown(() async {
      MobileRemoteSessions.sessions.clear();
      await PhoneMicrophone.disconnect(audio);
    });
    audio.ffiModel.updatePermission({
      'phone-audio-supported': 'true',
      'phone-audio-ready': 'true',
    }, audio.id);
    audio.ffiModel.setConnectionType(audio.id, true, false, 'Relay');
    MobileRemoteSessions.sessions.addAll([
      MobileRemoteSession('111111111'),
      MobileRemoteSession('222222222'),
    ]);
    expect(await PhoneMicrophone.startStandalone('444444444', false), isNull);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IPhoneDeviceWorkspace(
          devices: const SizedBox(),
          onEnterId: () {},
        ),
      ),
    ));
    expect(find.text('Active sessions'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '111111111  ·  Waiting'),
        findsOneWidget);
    expect(find.widgetWithText(ActionChip, '222222222  ·  Waiting'),
        findsOneWidget);
    await tester
        .tap(find.widgetWithText(ActionChip, '333333333  ·  Connected'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneMicrophonePage), findsOneWidget);
    expect(find.text('Relay Connection · TCP'), findsOneWidget);
    audio.ffiModel.setConnectionType(audio.id, true, true, 'WebRTC');
    await tester.pump();
    expect(find.text('Direct Connection · WebRTC'), findsOneWidget);
    expect(find.text('Relay Connection · TCP'), findsNothing);
    final speaker =
        find.widgetWithText(SwitchListTile, 'Use as remote speaker');
    final microphone =
        find.widgetWithText(SwitchListTile, 'Use local microphone');
    expect(tester.widget<SwitchListTile>(microphone).value, isFalse);
    await tester.tap(speaker);
    await tester.pump();
    expect(binding.speakerOptions, ['Y']);
    expect(audio.chatModel.voiceCallStatus.value, VoiceCallStatus.notStarted);
    audio.ffiModel.updatePermission({'phone-audio-playing': 'true'}, audio.id);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(speaker).value, isTrue);
    expect(tester.widget<SwitchListTile>(microphone).value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the mobile canvas paints the foreground session image and scale',
      (tester) async {
    isTest = true;
    platformFFI.setBindingForTesting(_Binding());
    await initGlobalFFI();
    final session = MobileRemoteSession('111111111');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(Colors.red, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final frame = picture.toImageSync(12, 12);
    picture.dispose();
    await session.ffi.imageModel.update(frame);
    session.ffi.canvasModel.update(0, 0, 2);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.imageModel),
        ChangeNotifierProvider.value(value: gFFI.canvasModel),
      ],
      child: MaterialApp(
        home: session.withModels(ImagePaint(ffiModel: session.ffi.ffiModel)),
      ),
    ));
    final paint = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(ImagePaint), matching: find.byType(CustomPaint)))
        .painter as ImagePainter;
    expect(paint.image, same(frame));
    expect(paint.scale, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    session.ffi.imageModel.disposeImage();
  });

  testWidgets(
      'the phone microphone shows one button that disconnects the session',
      (tester) async {
    isTest = true;
    final binding = _Binding();
    platformFFI.setBindingForTesting(binding);
    await initGlobalFFI();
    final mic =
        Client(7, true, false, false, 'iPhone', '123456789', false, false, true)
          ..isPhoneMicrophone = true
          ..phoneMicrophoneCall = true
          ..inVoiceCall = true;
    await tester.pumpWidget(ChangeNotifierProvider<ServerModel>.value(
      value: gFFI.serverModel,
      child: MaterialApp(
        theme: MyTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 286,
              height: 450,
              child: buildConnectionCard(mic),
            ),
          ),
        ),
      ),
    ));

    expect(find.text(isWindows ? 'CABLE Output' : 'VB-Cable'), findsOneWidget);
    expect(find.text('Audio input'), findsNothing);
    final disconnect = find.text('Disconnect');
    expect(disconnect, findsOneWidget);
    await tester.tap(disconnect);
    await tester.pump(const Duration(milliseconds: 150));
    expect(binding.disconnected, [mic.id]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
