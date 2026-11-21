import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/file_transfer_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
