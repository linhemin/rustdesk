import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/awesun/awesun_flutter_overlay.dart';
import 'package:flutter_hbb/mobile/widgets/session_action_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'AwesunFlutterOverlay defaults remote cursor off, exposes toggle & minimize, and edge-pans when unlocked',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool? remoteCursorToggled;
    var minimized = false;
    final panEvents = <Offset>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AwesunFlutterOverlay(
          touchMode: false,
          canInput: true,
          canSwitchMode: true,
          displayLocked: false,
          soundOn: true,
          qualityVisible: false,
          displayCount: 1,
          showRemoteCursor: false,
          canShowRemoteCursor: true,
          onToggleRemoteCursor: (v) => remoteCursorToggled = v,
          onMinimize: () => minimized = true,
          onPanCanvas: (_, pan) => panEvents.add(pan),
          onMovePointer: (_) {},
          onLeftClick: (_) {},
          onRightClick: (_) {},
          onMiddleClick: (_) {},
          onLeftDragStart: (_) {},
          onLeftDragEnd: () {},
          onScroll: (_, __) {},
          onToggleLock: () {},
          onSelectTouchMode: (_) {},
          onOpenSystemKeyboard: () {},
          onOpenVirtualKeyboard: () {},
          onOpenDisplaySettings: () {},
          onToggleQuality: () {},
          onOpenChat: () {},
          onOpenMore: () {},
          onDisconnect: () {},
        ),
      ),
    ));
    await tester.pump();

    // Drag hub well past the right viewport edge to trigger proportional edge pan.
    final layout = AwesunControlGeometry.layoutFor(null, const Size(400, 800));
    final drag = await tester.startGesture(layout.center);
    await drag.moveBy(const Offset(260, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.up();
    await tester.pump();
    expect(panEvents, isNotEmpty);
    expect(panEvents.first.dx, lessThan(0));

    // Open Actions sheet and verify remote cursor switch + Minimize button.
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Minimize'), findsOneWidget);
    expect(find.text('Show remote cursor'), findsOneWidget);
    expect(find.text('Lock canvas'), findsOneWidget);

    await tester.tap(find.text('Show remote cursor'));
    await tester.pump();
    expect(remoteCursorToggled, isTrue);

    await tester.tap(find.text('Minimize'));
    await tester.pumpAndSettle();
    expect(minimized, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'MobileSessionMoreSheet groups actions and collapses diagnostics by default',
      (tester) async {
    var tapped = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => MobileSessionMoreSheet(
                translateLabel: (k) => k,
                items: [
                  MobileSessionActionItem(
                    title: 'Refresh',
                    category: classifyMobileSessionAction(
                      actionId: 'refresh',
                      rawTitle: 'Refresh',
                    ),
                    onPressed: () => tapped = 'refresh',
                  ),
                  MobileSessionActionItem(
                    title: 'Ctrl+Alt+Del',
                    category: classifyMobileSessionAction(
                      actionId: 'send_ctrl_alt_del',
                      rawTitle: 'Ctrl+Alt+Del',
                    ),
                    onPressed: () => tapped = 'cad',
                  ),
                  MobileSessionActionItem(
                    title: 'Restart Remote Device',
                    category: classifyMobileSessionAction(
                      actionId: 'restart_remote',
                      rawTitle: 'Restart Remote Device',
                    ),
                    danger: true,
                    onPressed: () => tapped = 'restart',
                  ),
                  MobileSessionActionItem(
                    title: 'Copy P2P diagnostics',
                    category: classifyMobileSessionAction(
                      rawTitle: 'Copy P2P diagnostics',
                    ),
                    onPressed: () => tapped = 'diag',
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Display'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Del'), findsOneWidget);
    expect(find.text('Restart Remote Device'), findsOneWidget);
    // Diagnostics item must stay hidden until expanded.
    expect(find.text('Copy P2P diagnostics'), findsNothing);

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Copy P2P diagnostics'), findsOneWidget);

    await tester.tap(find.text('Copy P2P diagnostics'));
    await tester.pumpAndSettle();
    expect(tapped, 'diag');
    expect(tester.takeException(), isNull);
  });
}
