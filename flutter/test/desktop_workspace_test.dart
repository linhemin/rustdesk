import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui_preview/lib/desktop_main.dart';

void main() {
  Future<void> openCatalog(WidgetTester tester, {double width = 1440}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DesktopRuntimePreview());
  }

  testWidgets('session menus hide metrics and restore the collapsed toolbar',
      (tester) async {
    await openCatalog(tester);
    expect(find.text('QUALITY / SAMPLE'), findsOneWidget);
    await tester.tap(find.byTooltip('Display options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quality monitor'));
    await tester.pumpAndSettle();
    expect(find.text('QUALITY / SAMPLE'), findsNothing);
    await tester.tap(find.byTooltip('Close preview toolbar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show toolbar'), findsOneWidget);
    await tester.tap(find.byTooltip('Show toolbar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Display options'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sample transfer can be queued, paused, resumed and canceled',
      (tester) async {
    await openCatalog(tester);
    await tester.tap(find.text('File transfer'));
    await tester.pumpAndSettle();
    expect(find.text('No transfers in progress'), findsOneWidget);
    await tester.tap(find.text('design-system.zip').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send file'));
    await tester.pumpAndSettle();
    expect(find.text('In progress / sample'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause preview transfer'));
    await tester.pumpAndSettle();
    expect(find.text('Paused / sample'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume preview transfer'));
    await tester.pumpAndSettle();
    expect(find.text('In progress / sample'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel preview transfer'));
    await tester.pumpAndSettle();
    expect(find.text('No transfers in progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop catalog fits narrower windows in light and dark appearances',
      (tester) async {
    await openCatalog(tester, width: 900);
    await tester.tap(find.byTooltip('Dark appearance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('File transfer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Light appearance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
