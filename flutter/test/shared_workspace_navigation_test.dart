import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:rustdesk_ui/workspace_navigation.dart';

void main() {
  testWidgets('navigation retains selection across theme and rail size changes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = 0;
    var settingsOpened = 0;
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (_, isDark, __) => MaterialApp(
            theme: WorkspaceStyle.apply(
                isDark ? ThemeData.dark() : ThemeData.light()),
            home: StatefulBuilder(
                builder: (_, setState) => Scaffold(
                    body: WorkspaceNavigation(
                        brand: 'RustDesk',
                        mark: const Icon(Icons.desktop_windows),
                        destinations: const [
                          WorkspaceDestination('Connect', Icons.computer),
                          WorkspaceDestination('Devices', Icons.devices),
                        ],
                        current: selected,
                        onSelect: (index) => setState(() => selected = index),
                        settings: 'Settings',
                        onSettings: () => settingsOpened++,
                        child: Text('Page $selected')))))));

    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    dark.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);

    // A compact rail hides captions, not actions or their accessible names.
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(find.text('Devices'), findsNothing);
    await tester.tap(find.byTooltip('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Page 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(find.text('Page 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
