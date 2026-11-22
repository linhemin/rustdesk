import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/pages/connection_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/native/apple_workspace_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  final options = <String, String>{};

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) =>
      options[k] ?? '';

  @override
  Future<void> setLocalFlutterOption(
      {required String k, required String v, dynamic hint}) async {
    options[k] = v;
  }

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  setUpAll(() {
    isTest = true;
    platformFFI.setBindingForTesting(_Binding());
  });

  test('a fresh directory has a saved sort order before opening Favorites', () {
    expect(bind.getLocalFlutterOption(k: kOptionPeerSorting), isEmpty);
    expect(peerSort.value, PeerSortType.remoteId);
    expect(bind.getLocalFlutterOption(k: kOptionPeerSorting),
        PeerSortType.remoteId);
  });

  testWidgets(
      'floating iOS tabs leave the sides and capsule corners interactive',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = call.arguments['id'];
        final channel =
            MethodChannel('rustdesk/apple_workspace_navigation/$id');
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      extendBody: true,
      body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand()),
      bottomNavigationBar: AppleWorkspaceNavigation(
          labels: const ['Connection', 'Settings'],
          symbols: const ['display.2', 'gearshape'],
          selected: 0,
          compact: true,
          onSelect: (_) {}),
    )));
    await tester.pump();
    final view = find.byType(UiKitView);
    final portrait = tester.getRect(view);
    expect(portrait.height, closeTo(76, 0.01));
    expect(portrait.bottom, closeTo(844 - 17, 0.01));
    expect(portrait.width, closeTo(270.75, 0.01));
    await tester.tapAt(Offset(8, portrait.center.dy));
    await tester.tapAt(portrait.topLeft + const Offset(2, 2));
    expect(taps, 2);
    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewPadding =
        const FakeViewPadding(left: 47, right: 47, bottom: 21);
    await tester.pump();
    final rotated = tester.getRect(view);
    expect(rotated.height, closeTo(60, 0.01));
    expect(rotated.bottom, closeTo(390 - 10.5, 0.01));
    expect(rotated.center.dx, closeTo(422, 0.01));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone device search opens when tapped near the target edge',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const Scaffold(body: Center(child: PeerSearchBar()))));
    final icon = find.byIcon(Icons.search_rounded);
    await tester.tapAt(tester.getCenter(icon) - const Offset(20, 20));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
      'iPhone ID suggestions stay usable above the keyboard on rotation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    addTearDown(tester.view.reset);
    final peer = Peer.fromJson({'id': '123456789', 'alias': 'Studio Mac'});
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Align(
                alignment: Alignment.bottomCenter,
                child: IPhoneConnectionForm(
                    initialId: '',
                    peers: [peer],
                    onMatches: (_) {},
                    onSubmit: submitted.add,
                    onCancel: () {})))));
    final field = find.byType(TextField);
    await tester.enterText(field, 'Studio M');
    await tester.pump();
    final suggestion = find.text('Studio Mac');
    expect(tester.getBottomLeft(suggestion).dy, lessThan(568 - 230));
    tester.view.physicalSize = const Size(568, 320);
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    await tester.pump();
    await tester.ensureVisible(suggestion);
    await tester.tap(suggestion);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '123 456 789');
    expect(submitted, isEmpty);
    await tester.ensureVisible(find.byTooltip('Clear'));
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    await tester.tap(find.byTooltip('Connect'));
    expect(submitted, isEmpty);
    await tester.enterText(field, '123 456 789');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    expect(submitted, ['123456789']);
    expect(tester.takeException(), isNull);
  });
}
