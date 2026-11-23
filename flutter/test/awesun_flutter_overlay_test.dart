import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/awesun/awesun_flutter_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AwesunControlGeometry hit-tests radial mouse regions and scroll ring',
      () {
    expect(
      AwesunControlGeometry.hitRegion(Offset.zero, wheelOpen: false),
      AwesunMouseRegion.hub,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        const Offset(-AwesunControlGeometry.arcRadius, 0),
        wheelOpen: false,
      ),
      AwesunMouseRegion.left,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        const Offset(AwesunControlGeometry.arcRadius, 0),
        wheelOpen: false,
      ),
      AwesunMouseRegion.right,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        const Offset(0, -AwesunControlGeometry.wheelOffset),
        wheelOpen: false,
      ),
      AwesunMouseRegion.wheelTop,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        const Offset(0, AwesunControlGeometry.wheelOffset),
        wheelOpen: false,
      ),
      AwesunMouseRegion.wheelBottom,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        AwesunControlGeometry.closeOffset,
        wheelOpen: false,
      ),
      AwesunMouseRegion.close,
    );
    expect(
      AwesunControlGeometry.hitRegion(
        const Offset(AwesunControlGeometry.ringRadius, 0),
        wheelOpen: true,
      ),
      AwesunMouseRegion.ring,
    );
    expect(
      AwesunControlGeometry.hitRegion(Offset.zero, wheelOpen: true),
      isNull,
    );

    final layout =
        AwesunControlGeometry.layoutFor(null, const Size(400, 800));
    expect(layout.pointer.dx, lessThan(layout.center.dx));
    expect(layout.pointer.dy, lessThan(layout.center.dy));
  });

  testWidgets(
      'AwesunFlutterOverlay dispatches radial clicks, scroll ring, collapse, and actions sheet',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AwesunFlutterOverlay(
          touchMode: false,
          canInput: true,
          canSwitchMode: true,
          displayLocked: false,
          soundOn: true,
          qualityVisible: false,
          displayCount: 2,
          onMovePointer: (_) => events.add('move'),
          onLeftClick: (_) => events.add('left'),
          onRightClick: (_) => events.add('right'),
          onMiddleClick: (_) => events.add('middle'),
          onLeftDragStart: (_) => events.add('dragStart'),
          onLeftDragEnd: () => events.add('dragEnd'),
          onScroll: (steps, _) => events.add('scroll:$steps'),
          onToggleLock: () => events.add('lock'),
          onSelectTouchMode: (t) => events.add('touch:$t'),
          onOpenSystemKeyboard: () => events.add('sysKbd'),
          onOpenVirtualKeyboard: () => events.add('virtKbd'),
          onOpenDisplaySettings: () => events.add('display'),
          onToggleQuality: () => events.add('quality'),
          onOpenChat: () => events.add('chat'),
          onOpenMore: () => events.add('more'),
          onDisconnect: () => events.add('disconnect'),
        ),
      ),
    ));
    await tester.pump();

    final layout = AwesunControlGeometry.layoutFor(null, const Size(400, 800));

    // Tap hub -> left click
    await tester.tapAt(layout.center);
    await tester.pump();
    expect(events, contains('left'));

    // Tap right arc -> right click
    await tester.tapAt(
        layout.center + const Offset(AwesunControlGeometry.arcRadius, 0));
    await tester.pump();
    expect(events, contains('right'));

    // Tap bottom middle button -> middle click
    await tester.tapAt(
        layout.center + const Offset(0, AwesunControlGeometry.wheelOffset));
    await tester.pump();
    expect(events, contains('middle'));

    // Tap top wheel button -> opens scroll ring; tap close -> exits scroll ring
    await tester.tapAt(
        layout.center + const Offset(0, -AwesunControlGeometry.wheelOffset));
    await tester.pump();
    await tester.tapAt(layout.center + AwesunControlGeometry.closeOffset);
    await tester.pump();

    // Tap Actions glass orb -> opens sheet & triggers Disconnect
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Mouse mode'), findsOneWidget);
    expect(find.text('Touch mode'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(events, contains('disconnect'));
    expect(tester.takeException(), isNull);
  });
}
