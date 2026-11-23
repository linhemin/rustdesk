import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/file_transfer_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expanded desktop queue stays below both full-width browsers',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FileTransferWorkspace(
          local: SizedBox.expand(key: ValueKey('local')),
          remote: SizedBox.expand(key: ValueKey('remote')),
          queue: Text('Active job'),
          localLabel: 'Local',
          remoteLabel: 'Remote',
          queueLabel: 'Status',
          queueCount: Text('1'),
        ),
      ),
    ));

    final local = find.byKey(const ValueKey('local'));
    final remote = find.byKey(const ValueKey('remote'));
    final browserWidth = tester.getSize(local).width;
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(tester.getSize(local).width, browserWidth);
    expect(tester.getSize(remote).width, browserWidth);
    expect(tester.getSize(local).height, greaterThan(700 * 2 / 3));
    expect(tester.getTopLeft(find.text('Active job')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(local).dy));

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Active job'), findsNothing);
    expect(tester.getSize(local).width, browserWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file panes retain their paths across queue and window changes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FileTransferWorkspace(
          local: TextField(key: ValueKey('local')),
          remote: TextField(key: ValueKey('remote')),
          queue: Text('Active job'),
          localLabel: 'Local',
          remoteLabel: 'Remote',
          queueLabel: 'Status',
          queueCount: Text('1'),
        ),
      ),
    ));

    await tester.enterText(find.byKey(const ValueKey('local')), 'Documents');
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    expect(find.text('Documents'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('remote')), 'Downloads');
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Active job'), findsOneWidget);
    expect(find.text('Downloads'), findsNothing);

    tester.view.physicalSize = const Size(1200, 600);
    await tester.pumpAndSettle();
    expect(find.text('Active job'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 280);
    await tester.pumpAndSettle();
    expect(find.text('Active job'), findsOneWidget);
    expect(find.text('Downloads'), findsNothing);
    expect(find.text('Documents'), findsNothing);
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
