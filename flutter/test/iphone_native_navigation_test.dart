import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/native/apple_workspace_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('three iOS tabs use the system bar and native height',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    const layout = MethodChannel('rustdesk/apple_workspace_navigation/layout');
    messenger.setMockMethodCallHandler(layout, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(layout, null));
    late MethodChannel native;
    Map<dynamic, dynamic>? configuration;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        native = MethodChannel(
            'rustdesk/apple_workspace_navigation/${call.arguments['id']}');
        messenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'update') configuration = call.arguments;
          return 80.0;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(native, null));
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
                extendBody: true,
                bottomNavigationBar: AppleWorkspaceNavigation(
                  labels: const ['连接', '文件', '设置'],
                  symbols: const ['display.2', 'folder', 'gearshape'],
                  selected: selected,
                  compact: true,
                  onSelect: (index) => setState(() => selected = index),
                ),
              )),
    ));
    await tester.pumpAndSettle();
    final view = find.byType(UiKitView);
    final portrait = tester.getRect(view);
    expect(portrait, const Rect.fromLTWH(31, 794, 340, 80));
    expect(configuration!['labels'], ['连接', '文件', '设置']);
    expect(configuration!.containsKey('quickConnect'), isFalse);

    Future<void> fromNative(String method, [Object? argument]) async {
      await messenger.handlePlatformMessage(
          native.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, argument)),
          null);
      await tester.pump();
    }

    for (final index in [1, 2, 0]) {
      await fromNative('select', index);
      expect(configuration!['selected'], index);
    }

    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewPadding =
        const FakeViewPadding(left: 47, right: 47, bottom: 21);
    tester.view.padding =
        const FakeViewPadding(left: 47, right: 47, bottom: 21);
    await tester.pumpAndSettle();
    final landscape = tester.getRect(view);
    expect(landscape.width, portrait.width);
    expect(landscape.height, portrait.height);
    expect(landscape.bottom, 390);
    expect(landscape.center.dx, 422);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
