import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

import '../ui_preview/lib/mobile_catalog.dart';

void main() {
  testWidgets('phone catalog is scrollable with large text in both appearances',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final dark in [false, true]) {
      for (final entry in MobileScreensCatalog.screens.entries) {
        await tester.pumpWidget(MaterialApp(
          theme: WorkspaceStyle.apply(dark ? ThemeData.dark() : ThemeData()),
          home: Scaffold(body: MobileScreensCatalog(key: UniqueKey())),
        ));
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        final target = find.text(entry.value).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${entry.key}, dark=$dark');
      }
    }
  });

  testWidgets('mobile server dialog stays inside a narrow phone and dismisses',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData()),
      home: const Scaffold(body: MobileScreensCatalog()),
    ));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Server dialog').last);
    await tester.tap(find.text('Server dialog').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit server settings'));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(AlertDialog));
    expect(bounds.left, greaterThanOrEqualTo(20));
    expect(bounds.right, lessThanOrEqualTo(300));
    expect(find.text('API server'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
