import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui_preview/lib/main.dart';

void main() {
  testWidgets('connection form validates and never starts a real session',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RustDeskPreview());
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a remote ID'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123 456 789');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('UI preview only — no remote connection is made.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device search and settings navigation work on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RustDeskPreview());
    await tester.enterText(find.byType(TextField).last, 'Office');
    await tester.pumpAndSettle();
    expect(find.text('Office workstation'), findsOneWidget);
    expect(find.text('Studio Mac'), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    final toggle = find.byType(SwitchListTile).first;
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone layouts remain scrollable with enlarged text in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const RustDeskPreview());
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Dark appearance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
