import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/autocomplete.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_test/flutter_test.dart' hide isWindows, isMacOS;
import 'package:provider/provider.dart';
import 'package:rustdesk_ui/device_card.dart';

class _Binding extends Fake implements RustdeskImpl {
  String savedPeerTab = '';

  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #translate => call.namedArguments[#name],
        #mainHandleRelayId => Future.value(call.namedArguments[#id] as String),
        #mainGetLastRemoteId => Future.value(''),
        #mainIsUsingPublicServer => Future.value(false),
        #isDisableAb ||
        #isDisableAccount ||
        #isDisableGroupPanel ||
        #isOutgoingOnly ||
        #mainIsOptionFixed =>
          false,
        #getLocalFlutterOption => switch (call.namedArguments[#k]) {
            kOptionPeerTabIndex => savedPeerTab,
            _ => '',
          },
        #mainGetBuildinOption ||
        #mainGetLocalOption =>
          '',
        #mainLoadRecentPeers ||
        #mainLoadLanPeers ||
        #queryOnlines ||
        #setLocalFlutterOption =>
          Future<void>.value(),
        _ => super.noSuchMethod(call),
      };
}

void main() {
  test('autocomplete survives closing another connection input', () async {
    isTest = true;
    platformFFI.setBindingForTesting(_Binding());
    await initGlobalFFI();
    final inline = AllPeersLoader()..init((update) => update());
    final sheet = AllPeersLoader()..init((update) => update());
    addTearDown(inline.clear);
    inline.peers.add(Peer.fromJson({'id': '123456789'}));
    sheet.clear();

    await platformFFI.tryHandle({
      'name': 'callback_query_onlines',
      'onlines': '123456789',
      'offlines': '',
    });
    expect(inline.peers.single.online, isTrue);
  });

  testWidgets('recent device opens with the selected desktop connection mode',
      (tester) async {
    isTest = true;
    final binding = _Binding()..savedPeerTab = '${PeerTabIndex.owned.index}';
    platformFFI.setBindingForTesting(binding);
    await initGlobalFFI();
    await gFFI.userModel.validateStoredAccount();
    expect(gFFI.peerTabModel.currentTab, PeerTabIndex.recent.index);
    stateGlobal.isPortrait.value = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 590);
    addTearDown(tester.view.reset);

    const channel = MethodChannel('mixin.one/flutter_multi_window_channel');
    final requests = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'connect');
      requests.add(call.arguments['arguments'] as Map);
      return true;
    });
    gFFI.recentPeersModel.peers.add(Peer.fromJson(
        {'id': '123456789', 'alias': 'Studio Mac', 'platform': 'Mac OS'}));
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 510));
    }

    Future<void> mount({bool devicesOnly = false}) async {
      await tester.pumpWidget(ChangeNotifierProvider<PeerTabModel>.value(
          value: gFFI.peerTabModel,
          child: MaterialApp(
              theme: MyTheme.lightTheme,
              home: Scaffold(body: ConnectionPage(devicesOnly: devicesOnly)))));
      await settle();
      await settle();
    }

    await mount();
    if (isWindows || isMacOS) {
      tester.view.physicalSize = const Size(3840, 1080);
      await settle();
      expect(
          tester.getRect(find.byType(TextField).first).right, lessThan(1200));
      tester.view.physicalSize = const Size(760, 590);
      await settle();
    }
    final modes = [
      'Control Remote Desktop',
      'Transfer file',
      'Terminal',
      'View camera'
    ];
    for (var i = 0; i < modes.length; i++) {
      await tester.tap(find.text(modes[i]).first);
      await settle();
      await tester.tap(find.text('Studio Mac'));
      await settle();
      expect(requests.length, i + 1);
      final request = requests.last;
      expect(request['id'], '123456789');
      expect(request['isFileTransfer'], i == 1);
      expect(request['isTerminal'], i == 2);
      expect(request['isViewCamera'], i == 3);
    }
    for (final action in [
      ('Transfer file', true, false),
      ('Terminal', false, true),
      ('Connect', false, false),
    ]) {
      await tester.tap(find.descendant(
          of: find.byType(DeviceCard), matching: find.text(action.$1)));
      await settle();
      expect(requests.last['id'], '123456789');
      expect(requests.last['isFileTransfer'], action.$2);
      expect(requests.last['isTerminal'], action.$3);
      expect(requests.last['isViewCamera'], isFalse);
    }
    await mount(devicesOnly: true);
    expect(peerCardUiType.value, PeerUiType.grid);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    if (isWindows || isMacOS) {
      await tester.tap(find.byTooltip('Search'));
      await settle();
      final search = find.byType(TextField);
      await tester.enterText(search, 'not a sample device');
      await settle();
      expect(find.text('Empty'), findsOneWidget);
      expect(find.text('Studio Mac'), findsNothing);
      await tester.enterText(search, 'Studio');
      await settle();
      expect(find.text('Empty'), findsNothing);
      expect(find.text('Studio Mac'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await settle();
    }
    await mount();
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '987654321');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
    await settle();
    expect(requests.last['id'], '987654321');
    expect(gFFI.userModel.isLogin, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
