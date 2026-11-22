import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/widgets/apple_settings_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settings_ui/settings_ui.dart';

void main() {
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
