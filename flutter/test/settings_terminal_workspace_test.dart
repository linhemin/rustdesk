import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/terminal_toolbar.dart';
import 'package:flutter_hbb/desktop/widgets/settings_workspace.dart';
import 'package:flutter_hbb/mobile/widgets/apple_settings_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:settings_ui/settings_ui.dart';

void main() {
  testWidgets(
      'terminal actions stay reachable with a long peer on a small phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final actions = <String>[];

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TerminalToolbar(
      peer: 'a-very-long-remote-device.example.invalid',
      copyLabel: 'Copy',
      pasteLabel: 'Paste',
      closeLabel: 'Disconnect',
      onCopy: () => actions.add('copy'),
      onPaste: () => actions.add('paste'),
      onClose: () => actions.add('disconnect'),
    ))));

    await tester.tap(find.byTooltip('Copy'));
    await tester.tap(find.byTooltip('Paste'));
    await tester.tap(find.byTooltip('Disconnect'));
    expect(actions, ['copy', 'paste', 'disconnect']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inset settings keep navigation and managed switches intact',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var presses = 0;
    var toggles = 0;

    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData(platform: TargetPlatform.iOS)),
      home: Scaffold(
          body: AppleSettingsList(sections: [
        SettingsSection(title: const Text('Connection'), tiles: [
          SettingsTile.navigation(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Network'),
              onPressed: (_) => presses++),
          SettingsTile.switchTile(
              title: const Text('Enable UDP hole punching'),
              initialValue: true,
              onToggle: (_) => toggles++),
          SettingsTile.switchTile(
              title: const Text('Managed option'),
              initialValue: true,
              onToggle: null),
        ]),
      ])),
    ));

    await tester.tap(find.text('Network'));
    await tester.tap(find.text('Enable UDP hole punching'));
    await tester.ensureVisible(find.text('Managed option'));
    await tester.tap(find.text('Managed option'));
    expect(presses, 1);
    expect(toggles, 1);
    final managed =
        tester.widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch)).last;
    expect(managed.value, isTrue);
    expect(managed.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop settings navigation still invokes its destination',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData(platform: TargetPlatform.windows)),
      home: Scaffold(
          body: SizedBox(
              width: 216,
              child: WorkspaceSettingsNavItem(
                label: 'Network',
                icon: Icons.hub_outlined,
                selected: true,
                onTap: () => presses++,
              ))),
    ));
    await tester.tap(find.text('Network'));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });
}
