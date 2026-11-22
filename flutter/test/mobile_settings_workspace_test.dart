import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show CustomAlertDialog;
import 'package:flutter_hbb/mobile/widgets/apple_settings_list.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart'
    show serverSettingsTextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:settings_ui/settings_ui.dart';

void main() {
  testWidgets(
      'iPhone server fields match settings rows at the system text size',
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
          body: Stack(children: [
        AppleSettingsList(sections: [
          SettingsSection(
              tiles: [SettingsTile(title: const Text('Connection'))]),
        ]),
        CustomAlertDialog(
          title: const Text('ID / Relay Server'),
          content: serverSettingsTextFormField(
              label: 'ID Server', controller: controller, errorMsg: ''),
        ),
      ])),
    ));
    await tester.pumpAndSettle();
    final row =
        DefaultTextStyle.of(tester.element(find.text('Connection'))).style;
    final title =
        DefaultTextStyle.of(tester.element(find.text('ID / Relay Server')))
            .style;
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.style.fontSize, row.fontSize);
    expect(input.style.fontWeight, row.fontWeight);
    final renderedInput = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(renderedInput.textScaler.scale(input.style.fontSize!),
        closeTo(25.6, .01));
    expect(title.fontSize, greaterThan(row.fontSize!));
    expect(
        title.fontSize, lessThan(theme.appBarTheme.titleTextStyle!.fontSize!));
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
