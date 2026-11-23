import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/widgets/apple_settings_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:settings_ui/settings_ui.dart';

void main() {
  testWidgets('settings search filters rows and retains row and QR actions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var query = '';
    var selected = false;
    var scanned = false;
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData(platform: TargetPlatform.iOS)),
      home: StatefulBuilder(
          builder: (context, update) => Scaffold(
                body: AppleSettingsList(
                  searchQuery: query,
                  header: AppleSettingsHeader(
                      title: 'Settings',
                      searchHint: 'Search',
                      controller: controller,
                      onSearch: (value) => update(() => query = value),
                      scan: IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => scanned = true)),
                  sections: [
                    SettingsSection(title: const Text('Connection'), tiles: [
                      SettingsTile.navigation(
                          title: const Text('UDP hole punching'),
                          onPressed: (_) => selected = true),
                    ]),
                    SettingsSection(title: const Text('General'), tiles: [
                      SettingsTile(title: const Text('Appearance')),
                    ]),
                  ],
                ),
              )),
    ));
    await tester.enterText(find.byType(TextField), 'UDP');
    await tester.pump();
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('General'), findsNothing);
    await tester.tap(find.text('UDP hole punching'));
    await tester.tap(find.byIcon(Icons.qr_code_scanner));
    expect(selected, isTrue);
    expect(scanned, isTrue);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Appearance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone full-page server fields scale with settings rows',
      (tester) async {
    final theme = WorkspaceStyle.apply(
        ThemeData(useMaterial3: false, platform: TargetPlatform.iOS));
    final controller = TextEditingController(text: 'example.invalid');
    addTearDown(controller.dispose);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
          body: Column(children: [
        Expanded(
            child: AppleSettingsList(sections: [
          SettingsSection(
              tiles: [SettingsTile(title: const Text('Connection'))]),
        ])),
        AppleSettingsField(label: 'ID Server', controller: controller),
      ])),
    ));
    await tester.pumpAndSettle();
    final row =
        DefaultTextStyle.of(tester.element(find.text('Connection'))).style;
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.style.fontSize, row.fontSize);
    expect(input.style.fontWeight, row.fontWeight);
    final renderedInput = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(renderedInput.textScaler.scale(input.style.fontSize!),
        closeTo(23.2, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings retain actions and fixed switches at large text sizes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);

    var presses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: Scaffold(
                    body: AppleSettingsList(sections: [
                  SettingsSection(tiles: [
                    SettingsTile.navigation(
                      title: const Text('Display settings'),
                      description: const Text('Default display options'),
                      value: const Text('Adaptive'),
                      trailing: const Icon(Icons.desktop_windows),
                      onPressed: (_) => presses++,
                    ),
                    SettingsTile.switchTile(
                      title: const Text('Enable UDP hole punching'),
                      initialValue: true,
                      onToggle: null,
                    ),
                  ]),
                ])),
              )),
    ));

    expect(find.text('Adaptive'), findsOneWidget);
    expect(find.text('Default display options'), findsOneWidget);
    expect(find.byIcon(Icons.desktop_windows), findsOneWidget);
    await tester.tap(find.text('Display settings'));
    expect(presses, 1);
    await tester.ensureVisible(find.byType(CupertinoSwitch));
    await tester.tap(find.text('Enable UDP hole punching'));
    final locked = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(locked.value, isTrue);
    expect(locked.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
}
