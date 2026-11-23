import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/device_card.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

void main() {
  testWidgets(
      'phone device actions remain reachable with long names and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    var fileTransfers = 0;
    var menus = 0;
    var selections = 0;
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: WorkspaceStyle.apply(ThemeData(brightness: brightness)),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                  child: GestureDetector(
                onLongPress: () => selections++,
                child: DeviceCard(
                  name: 'MacBook Pro M4 · A very long workspace name',
                  remoteId: '842 190 531',
                  platform: 'macOS',
                  platformIcon: Icons.desktop_mac_outlined,
                  online: true,
                  status: 'Online',
                  note: 'Saved device note',
                  actions: [
                    IconButton(
                        tooltip: 'Transfer file',
                        onPressed: () => fileTransfers++,
                        icon: const Icon(Icons.folder_outlined)),
                    IconButton(
                        tooltip: 'More',
                        onPressed: () => menus++,
                        icon: const Icon(Icons.more_horiz)),
                  ],
                ),
              )),
            ),
          ),
        ),
      ));
      await tester.tap(find.byTooltip('Transfer file'));
      await tester.tap(find.byTooltip('More'));
      await tester.longPress(find.text('842 190 531 · Online'));
      expect(find.text('842 190 531 · Online'), findsOneWidget);
      expect(find.text('Saved device note'), findsOneWidget);
      expect(find.textContaining('ms'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(fileTransfers, 2);
    expect(menus, 2);
    expect(selections, 2);
  });

  testWidgets(
      'desktop card shows saved identity, offline status, and selection',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData.dark()),
      home: const Scaffold(
        body: SizedBox(
          width: 300,
          height: 156,
          child: DeviceCard(
            name: 'Office workstation',
            remoteId: '391 048 227',
            platform: 'Windows',
            platformIcon: Icons.laptop_windows_outlined,
            online: false,
            status: 'Offline',
            details: 'owner@workstation',
            note: 'Build machine',
            grid: true,
            selected: true,
            passwordSaved: true,
            actions: [Checkbox(value: true, onChanged: null)],
          ),
        ),
      ),
    ));
    expect(find.text('Office workstation'), findsOneWidget);
    expect(find.text('391 048 227 · owner@workstation'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.key_rounded), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop card keeps actions visible with enlarged text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData(platform: TargetPlatform.windows)),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
          body: SizedBox(
              width: 340,
              height: 226,
              child: DeviceCard(
                name: 'Workstation with a long device name',
                remoteId: '391 048 227',
                platform: 'Windows',
                platformIcon: Icons.window_outlined,
                online: true,
                status: 'Online',
                note: 'Build machine',
                grid: true,
                actions: [
                  for (final label in ['Transfer file', 'Terminal', 'Connect'])
                    TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.all(6),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 11)),
                        onPressed: () {},
                        child: Text(label)),
                  IconButton(
                      constraints:
                          const BoxConstraints.tightFor(width: 28, height: 28),
                      padding: EdgeInsets.zero,
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz)),
                ],
              )),
        ),
      ),
    ));
    for (final label in ['Windows', 'Transfer file', 'Terminal', 'Connect']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
