import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/widgets/session_controls.dart';
import 'package:flutter_hbb/mobile/widgets/session_keyboard.dart';
import 'package:flutter_hbb/mobile/widgets/session_touchpad.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  setUpAll(() {
    isTest = true;
    platformFFI.setBindingForTesting(_Binding());
  });

  testWidgets(
      'touch mode keeps its own virtual mouse toggle and session actions',
      (tester) async {
    final modes = <SessionInputMode>[];
    final actions = <SessionAction>[];
    var keyboard = 0;
    var virtualMouse = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        floatingActionButton: StatefulBuilder(builder: (context, setState) {
          final mode = modes.isEmpty ? SessionInputMode.touch : modes.last;
          return SessionControlsDock(
            mode: mode,
            showInputModes: true,
            onMode: (mode) => setState(() => modes.add(mode)),
            virtualMouseEnabled: virtualMouse,
            onToggleVirtualMouse: mode == SessionInputMode.touch
                ? () => setState(() => virtualMouse = !virtualMouse)
                : null,
            onGestureSettings: () {},
            onKeyboard: () => keyboard++,
            actions: SessionAction.values,
            onAction: actions.add,
          );
        }),
      ),
    ));

    await tester.tap(find.byTooltip('Show virtual mouse'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Touchscreen mode'), findsOneWidget);
    expect(find.byTooltip('Hide virtual mouse'), findsOneWidget);
    await tester.tap(find.byTooltip('Touchscreen mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pointer mode'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide virtual mouse'), findsNothing);
    await tester.tap(find.byTooltip('Pointer mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Touchscreen mode'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide virtual mouse'), findsOneWidget);
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display Settings'));
    await tester.pumpAndSettle();

    expect(modes, [SessionInputMode.pointer, SessionInputMode.touch]);
    expect(actions, [SessionAction.display]);
    expect(keyboard, 1);
  });

  testWidgets('a narrow keyboard keeps modifiers and mouse buttons accessible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final modifiers = <SessionModifier>{};
    final keys = <String>[];
    final mouse = <MouseButtons>[];
    var compact = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: StatefulBuilder(builder: (context, setState) {
            return SessionKeyboard(
              compact: compact,
              enabled: true,
              isMac: false,
              showMouseButtons: true,
              modifiers: modifiers,
              onModifier: (key) => setState(() => modifiers.add(key)),
              onKey: keys.add,
              onMouse: mouse.add,
              onShortcut: (_, key) => keys.add(key),
              onTextInput: () => setState(() => compact = !compact),
              onClose: () {},
            );
          }),
        ),
      ),
    ));

    await tester.tap(find.text('Ctrl'));
    await tester.tap(find.byTooltip('Right button'));
    await tester.tap(find.text('P'));
    await tester.tap(find.text('F1–F12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F12'));
    await tester.tap(find.byTooltip('Local keyboard'));
    await tester.pumpAndSettle();

    expect(modifiers, {SessionModifier.ctrl});
    expect(mouse, [MouseButtons.right]);
    expect(keys, ['VK_P', 'VK_F12']);
    expect(find.byTooltip('Input keyboard'), findsOneWidget);
    expect(find.text('F12'), findsNothing);
    await tester.tap(find.byTooltip('Shortcuts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ctrl+V'));
    await tester.pumpAndSettle();
    expect(keys.last, 'VK_V');
    await tester.binding.setSurfaceSize(const Size(640, 120));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Input keyboard').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'touchpad separates click, right-click, collapse and drag release',
      (tester) async {
    final buttons = <String>[];
    final moves = <Offset>[];
    final scroll = <int>[];
    final zoom = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionTouchpad(
          scale: 1,
          onMove: moves.add,
          onLeftClick: () => buttons.add('left'),
          onRightClick: () => buttons.add('right'),
          onMiddleClick: () => buttons.add('middle'),
          onDragStart: () => buttons.add('down'),
          onDragEnd: () => buttons.add('up'),
          onScroll: scroll.add,
          onZoom: zoom.add,
        ),
      ),
    ));
    final area = find.byKey(const ValueKey('session-touchpad-area'));
    await tester.tap(area);
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    await tester.longPress(area);
    await tester.pumpAndSettle();
    expect(buttons, ['left', 'right']);

    await tester.tap(area);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(area);
    await tester.pumpAndSettle();
    expect(area, findsNothing);
    expect(buttons, ['left', 'right']);
    await tester.tap(find.byTooltip('Virtual mouse'));
    await tester.pumpAndSettle();

    final left = find.byTooltip('Left button');
    await tester.tap(left);
    await tester.tap(find.byTooltip('Right button'));
    await tester.tap(find.byTooltip('Middle mouse button'));
    expect(buttons, ['left', 'right', 'left', 'right', 'middle']);
    buttons.clear();
    final drag = await tester.startGesture(tester.getCenter(left));
    await drag.moveBy(const Offset(45, 0));
    await drag.moveBy(const Offset(18, 0));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(buttons, ['down', 'up']);
    expect(moves, isNotEmpty);
    expect(scroll, isEmpty);
    expect(zoom, isEmpty);

    final center = tester.getCenter(area);
    var first = await tester.startGesture(center - const Offset(27, 14));
    var second = await tester.startGesture(center + const Offset(27, -14));
    for (var i = 0; i < 11; i++) {
      await first.moveBy(const Offset(0, 5));
      await second.moveBy(const Offset(0, 5));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(scroll, isNotEmpty);
    expect(zoom, isEmpty);

    scroll.clear();
    first = await tester.startGesture(center - const Offset(14, 0));
    second = await tester.startGesture(center + const Offset(14, 0));
    for (var i = 0; i < 3; i++) {
      await first.moveBy(const Offset(-8, 0));
      await second.moveBy(const Offset(8, 0));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(zoom.any((ratio) => ratio > 1), isTrue);
    expect(scroll, isEmpty);
    expect(buttons, ['down', 'up']);

    final grip = await tester.startGesture(tester.getCenter(left));
    await grip.moveBy(const Offset(35, -10));
    await grip.up();
    await tester.pumpAndSettle();
    expect(buttons, ['down', 'up', 'down', 'up']);

    final wheel = find.byKey(const ValueKey('session-touchpad-wheel'));
    final moveCount = moves.length;
    final zoomCount = zoom.length;
    await tester.drag(wheel, const Offset(0, 43));
    await tester.pumpAndSettle();
    expect(scroll, isNotEmpty);
    expect(scroll.every((step) => step > 0), isTrue);
    expect(scroll.reduce((a, b) => a + b), 3);
    scroll.clear();
    await tester.drag(wheel, const Offset(0, -43));
    await tester.pumpAndSettle();
    expect(scroll, isNotEmpty);
    expect(scroll.every((step) => step < 0), isTrue);
    expect(scroll.reduce((a, b) => a + b), -3);
    expect(moves.length, moveCount);
    expect(zoom.length, zoomCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'scroll ring captures only the rim and leaves remote touch active',
      (tester) async {
    final scroll = <int>[];
    var remoteTouches = 0;
    var middleClicks = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => remoteTouches++,
            ),
            SessionTouchpad(
              scale: 1,
              onMove: (_) {},
              onLeftClick: () {},
              onRightClick: () {},
              onMiddleClick: () => middleClicks++,
              onDragStart: () {},
              onDragEnd: () {},
              onScroll: scroll.add,
              onZoom: (_) {},
            ),
          ],
        ),
      ),
    ));

    final pad = tester.getCenter(
        find.byKey(const ValueKey('session-touchpad-area')));
    final move = await tester.startGesture(pad);
    await move.moveBy(const Offset(24, 0));
    await tester.tapAt(const Offset(300, 100));
    expect(remoteTouches, 1);
    await move.up();
    await tester.tap(find.byTooltip('Middle mouse button'));
    expect(middleClicks, 1);
    await tester.tap(find.byKey(const ValueKey('session-touchpad-wheel')));
    await tester.pumpAndSettle();
    final ring = find.byKey(const ValueKey('session-touchpad-scroll-ring'));
    final bounds = tester.getRect(ring);
    await tester.tapAt(bounds.topLeft + const Offset(5, 5));
    expect(remoteTouches, 2);

    final drag = await tester.startGesture(bounds.center + const Offset(52, 0));
    await drag.moveTo(bounds.center + const Offset(37, 37));
    await tester.tapAt(bounds.center);
    expect(remoteTouches, 3);
    await drag.moveTo(bounds.center + const Offset(0, 52));
    await drag.up();
    await tester.pumpAndSettle();
    expect(scroll, isNotEmpty);
    expect(scroll.every((step) => step < 0), isTrue);
    expect(remoteTouches, 3);
    expect(ring, findsNothing);

    scroll.clear();
    await tester.tap(find.byKey(const ValueKey('session-touchpad-wheel')));
    await tester.pumpAndSettle();
    final reverse =
        await tester.startGesture(bounds.center + const Offset(-52, 1));
    await reverse.moveTo(bounds.center + const Offset(-52, -1));
    expect(scroll, isEmpty);
    await reverse.moveTo(bounds.center + const Offset(-37, 37));
    await reverse.cancel();
    await tester.pumpAndSettle();
    expect(scroll, isNotEmpty);
    expect(scroll.every((step) => step > 0), isTrue);
    expect(ring, findsNothing);
  });
}
