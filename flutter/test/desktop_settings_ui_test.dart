import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/desktop_settings.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

import '../ui_preview/lib/desktop_settings_catalog.dart';

void main() {
  testWidgets('all desktop categories and dialogs render in both appearances',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DesktopSettingsCatalog()));
    for (var appearance = 0; appearance < 2; appearance++) {
      for (final page in desktopSettingsPages) {
        await tester
            .tap(find.widgetWithText(WorkspaceSettingsNavItem, page.$1));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(WorkspaceSettingsHeader, page.$1),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (var index = 0; index < desktopDialogNames.length; index++) {
        await tester.tap(find.byTooltip('Dialog catalog'));
        await tester.pumpAndSettle();
        final item =
            find.widgetWithText(PopupMenuItem<int>, desktopDialogNames[index]);
        await tester.scrollUntilVisible(item, 200,
            scrollable: find.byType(Scrollable).last);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceDesktopDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find
            .text(index == 15
                ? 'Close'
                : index == 4
                    ? 'Dismiss'
                    : 'Cancel')
            .last);
        await tester.pumpAndSettle();
      }
      if (appearance == 0) {
        await tester.tap(find.byTooltip('Dark appearance'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('login fixture validates fields without saving credentials',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceDesktopStyle.apply(WorkspaceStyle.apply(ThemeData())),
      home: const Scaffold(body: CatalogDialog(index: 0)),
    ));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .obscureText,
        isTrue);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'production sections wrap long labels and retain navigation actions',
      (tester) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme:
          WorkspaceDesktopStyle.apply(WorkspaceStyle.apply(ThemeData.dark())),
      home: Scaffold(
          body: ListView(children: [
        WorkspaceSettingsNavItem(
            label: 'Security and connection permissions',
            icon: Icons.shield_outlined,
            selected: true,
            onTap: () => tapped = true),
        const WorkspaceSettingsSection(
            title: 'Long translated settings section heading',
            children: [
              Text('Existing controls remain owned by the application.')
            ]),
      ])),
    ));
    await tester.tap(find.byType(WorkspaceSettingsNavItem));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
