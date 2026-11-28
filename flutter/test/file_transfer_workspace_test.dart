import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/file_transfer_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('deep paths show whole labels or an ancestor menu',
      (tester) async {
    const parts = [
      '/',
      'Users',
      'devin',
      'ft_demo_local',
      'projects',
      '2026',
      'q4'
    ];
    List<String>? opened;
    var editing = false;
    Widget workspace(double width) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: width,
                height: 32,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => editing = true,
                    child: FileTransferBreadcrumbs(
                        parts: parts, onSelected: (path) => opened = path)))));
    await tester.pumpWidget(workspace(400));
    expect(find.text('/'), findsOneWidget);
    expect(find.text('q4'), findsOneWidget);
    expect(find.text('projects'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('ft_demo_local'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('projects'));
    expect(opened, ['/', 'Users', 'devin', 'ft_demo_local', 'projects']);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ft_demo_local'));
    await tester.pumpAndSettle();
    expect(opened, ['/', 'Users', 'devin', 'ft_demo_local']);

    await tester.pumpWidget(workspace(1200));
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('ft_demo_local'), findsOneWidget);
    await tester.tap(find.text('devin'));
    expect(opened, ['/', 'Users', 'devin']);
    await tester.tapAt(
        tester.getTopRight(find.byType(FileTransferBreadcrumbs)) +
            const Offset(-20, 16));
    expect(editing, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(workspace(64));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('q4')).width, greaterThan(10));
    await tester.tap(find.text('q4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(opened, ['/', 'Users']);
  });

  testWidgets('long UNC roots and leaf names leave adjacent controls reachable',
      (tester) async {
    final root = r'\\server-with-a-long-name\share-with-a-long-name';
    final leaf = 'very-long-directory-${'name-' * 30}';
    List<String>? opened;
    var dropdownOpened = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 240,
                height: 32,
                child: Row(children: [
                  Expanded(
                      child: FileTransferBreadcrumbs(
                          parts: [root, leaf],
                          onSelected: (path) => opened = path)),
                  IconButton(
                      onPressed: () => dropdownOpened = true,
                      icon: const Icon(Icons.arrow_drop_down)),
                ])))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(leaf)).height, lessThan(32));
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    expect(dropdownOpened, isTrue);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(root));
    await tester.pumpAndSettle();
    expect(opened, [root]);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('a browser without local file access shows the remote pane',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FileTransferWorkspace(
          remote: SizedBox.expand(key: ValueKey('remote')),
          queue: Text('Active job'),
          localLabel: 'Local',
          remoteLabel: 'Remote',
          queueLabel: 'Status',
          queueCount: Text('1'),
        ),
      ),
    ));
    final remote = find.byKey(const ValueKey('remote'));
    expect(find.text('Local'), findsNothing);
    expect(tester.getSize(remote).width, 430);
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Active job'), findsOneWidget);
    expect(remote, findsNothing);

    await tester.binding.setSurfaceSize(const Size(1200, 700));
    await tester.pumpAndSettle();
    expect(tester.getSize(remote).width, 1200);
    expect(find.text('Active job'), findsOneWidget);
  });
}
