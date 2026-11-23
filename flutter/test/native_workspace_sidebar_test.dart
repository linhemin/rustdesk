import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/native/apple_workspace_navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/workspace_navigation.dart';

void main() {
  testWidgets(
      'embedded macOS list selects destinations without duplicate chrome',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    late MethodChannel native;
    Map<dynamic, dynamic>? configuration;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        native = MethodChannel(
            'rustdesk/apple_workspace_navigation/${call.arguments['id']}');
        messenger.setMockMethodCallHandler(native, (call) async {
          if (call.method == 'update') configuration = call.arguments;
          return null;
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
                body: WorkspaceNavigation(
                    brand: 'RustDesk',
                    mark: const Text('R'),
                    destinations: const [
                      WorkspaceDestination('Home', Icons.home)
                    ],
                    current: 0,
                    onSelect: (_) {},
                    child: const SizedBox(),
                    nativeNavigation: AppleWorkspaceNavigation(
                        labels: const [
                          'Home',
                          'Incoming',
                          'Remote',
                          'Files',
                          'Terminal'
                        ],
                        symbols: const [
                          'house',
                          'laptopcomputer',
                          'display.2',
                          'folder',
                          'terminal'
                        ],
                        selected: selected,
                        compact: false,
                        navigationOnly: true,
                        onSelect: (index) =>
                            setState(() => selected = index)))))));
    await tester.pumpAndSettle();
    expect(configuration!['navigationOnly'], isTrue);
    expect(configuration!['settings'], isNull);
    expect(configuration!['brand'], isNull);
    await messenger.handlePlatformMessage(
        native.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('select', 4)),
        null);
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(configuration!['selected'], 4);
    tester.view.physicalSize = const Size(600, 200);
    await tester.pumpAndSettle();
    expect(find.byType(AppKitView), findsOneWidget);
    expect(tester.getSize(find.byType(AppKitView)).height, lessThan(190));
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
}
