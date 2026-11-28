import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/file_transfer_workspace.dart';
import 'package:flutter_hbb/desktop/widgets/session_whiteboard.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/android_sliding_navigation_bar.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/device_card.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

class _TestBinding extends Fake implements RustdeskImpl {
  Completer<void>? sortSave;
  String? savedSort;

  @override
  Future<void> setLocalFlutterOption(
      {required String k, required String v, dynamic hint}) {
    savedSort = v;
    return sortSave?.future ?? Future<void>.value();
  }

  @override
  String translate({required String name, required String locale, dynamic hint}) =>
      name;

  @override
  dynamic noSuchMethod(Invocation invocation) => switch (invocation.memberName) {
        #getLocalFlutterOption ||
        #mainGetLocalOption ||
        #mainGetOptionSync ||
        #mainGetBuildinOption =>
          '',
        _ => super.noSuchMethod(invocation),
      };
}

void main() {
  final binding = _TestBinding();
  setUpAll(() {
    isTest = true;
    platformFFI.setBindingForTesting(binding);
  });

  test('ColorThemeExtension.lerp interpolates each color field independently',
      () {
    final light = ColorThemeExtension.light;
    final dark = ColorThemeExtension.dark;
    final mid = light.lerp(dark, 0.5) as ColorThemeExtension;

    expect(mid.border, Color.lerp(light.border, dark.border, 0.5));
    expect(mid.border2, Color.lerp(light.border2, dark.border2, 0.5));
    expect(mid.border3, Color.lerp(light.border3, dark.border3, 0.5));
    expect(mid.highlight, Color.lerp(light.highlight, dark.highlight, 0.5));
    expect(
        mid.drag_indicator, Color.lerp(light.drag_indicator, dark.drag_indicator, 0.5));
    expect(mid.shadow, Color.lerp(light.shadow, dark.shadow, 0.5));
    expect(mid.me, Color.lerp(light.me, dark.me, 0.5));
    expect(mid.divider, Color.lerp(light.divider, dark.divider, 0.5));
  });

  test('WorkspaceStyle.apply exposes surfaceContainerLow and filledButtonTheme',
      () {
    for (final brightness in Brightness.values) {
      final themed = WorkspaceStyle.apply(ThemeData(brightness: brightness));
      expect(themed.colorScheme.surfaceContainerLow, isNotNull);
      expect(themed.colorScheme.onSurfaceVariant, isNotNull);
      expect(themed.filledButtonTheme.style, isNotNull);
    }
  });

  testWidgets('DeviceCard supports both single tap and long press on mouse/touch',
      (tester) async {
    var tapped = 0;
    var longPressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData.light()),
      home: Scaffold(
        body: GestureDetector(
          onTap: () => tapped++,
          onLongPress: () => longPressed++,
          child: const DeviceCard(
            name: 'Workstation',
            remoteId: '123 456 789',
            platform: 'Linux',
            platformIcon: Icons.terminal_rounded,
            online: true,
            status: 'Online',
            actions: [],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Workstation'));
    await tester.pump();
    expect(tapped, 1);

    await tester.longPress(find.text('Workstation'));
    await tester.pump();
    expect(longPressed, 1);
  });

  testWidgets(
      'device sorting closes its menu before saving the preference',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Column(children: [Text('Devices'), PeerSortDropdown()]),
            ),
          )),
          child: const Text('Open devices'),
        );
      })),
    ));
    await tester.tap(find.text('Open devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
    final item = find.byWidgetPredicate((widget) =>
        widget is RadioListTile<String> && widget.value != widget.groupValue);
    final choice = tester.widget<RadioListTile<String>>(item.first).value;
    final save = Completer<void>();
    binding.sortSave = save;
    addTearDown(() => binding.sortSave = null);

    await tester.tap(item.first);
    await tester.pumpAndSettle();
    expect(binding.savedSort, choice);
    expect(find.byType(RadioListTile<String>), findsNothing);
    save.complete();
    await tester.pumpAndSettle();
    expect(find.text('Devices'), findsOneWidget);
  });

  testWidgets(
      'CustomAlertDialog handles Escape and Enter keys and disposes cleanly',
      (tester) async {
    var submitted = 0;
    var cancelled = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomAlertDialog(
          title: const Text('Confirm'),
          content: const Text('Proceed?'),
          actions: [
            TextButton(
              onPressed: () => cancelled++,
              child: const Text('Cancel'),
            ),
          ],
          onSubmit: () => submitted++,
          onCancel: () => cancelled++,
        ),
      ),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submitted, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(cancelled, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FileTransferWorkspace stays collapsed by default and auto-expands when active jobs start',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var activeCount = 0;
    late StateSetter updateState;

    await tester.pumpWidget(MaterialApp(
      theme: WorkspaceStyle.apply(ThemeData.light()),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          updateState = setState;
          return FileTransferWorkspace(
            local: const SizedBox.expand(),
            remote: const SizedBox.expand(),
            queue: const Text('Transfer queue body'),
            localLabel: 'Local',
            remoteLabel: 'Remote',
            queueLabel: 'Transfer file',
            queueCount: const Text('1'),
            activeJobCount: activeCount,
          );
        }),
      ),
    ));

    expect(find.text('Transfer queue body'), findsNothing);

    updateState(() => activeCount = 1);
    await tester.pump();
    expect(find.text('Transfer queue body'), findsOneWidget);
  });

  testWidgets('SessionWhiteboardOverlay isolates strokes in RepaintBoundary',
      (tester) async {
    final controller = WhiteboardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionWhiteboardOverlay(controller: controller),
      ),
    ));
    expect(
      find.descendant(
        of: find.byType(SessionWhiteboardOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );

    controller.setTool(WhiteboardTool.pen);
    controller.startStroke(const Offset(10, 10));
    controller.extendStroke(const Offset(40, 40));
    await tester.pump();

    final whiteboardPaint = find.descendant(
      of: find.byType(SessionWhiteboardOverlay),
      matching: find.byType(CustomPaint),
    ).first;
    expect(whiteboardPaint, findsOneWidget);
    expect(
      find.ancestor(of: whiteboardPaint, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });

  testWidgets(
      'AndroidSlidingNavigationBar clamps edge pointer coordinates without RangeError',
      (tester) async {
    var selected = -1;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AndroidSlidingNavigationBar(
          child: BottomNavigationBar(
            currentIndex: 0,
            onTap: (index) => selected = index,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ),
      ),
    ));

    final rect = tester.getRect(find.byType(BottomNavigationBar));
    final gesture = await tester.startGesture(
      Offset(rect.right - 1.0, rect.center.dy),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(Offset(rect.right - 0.5, rect.center.dy));
    await gesture.up();
    await tester.pump();

    expect(selected, 1);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
