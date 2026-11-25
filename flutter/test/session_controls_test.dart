import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/remote_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/session_canvas_drag.dart';
import 'package:flutter_hbb/mobile/widgets/session_controls.dart';
import 'package:flutter_hbb/mobile/widgets/session_keyboard.dart';
import 'package:flutter_hbb/mobile/widgets/session_touchpad.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

class _TouchPeer extends Fake implements FfiModel {
  _TouchPeer(this.touchMode);
  @override
  final bool touchMode;
  @override
  Rect get rect => const Rect.fromLTWH(0, 0, 8000, 1000);
  @override
  bool get isPeerMobile => false;
  @override
  bool get isPeerAndroid => false;
}

class _TouchCursor extends Fake implements CursorModel {
  final moves = <Offset>[];
  @override
  Future<void> updatePan(Offset delta, Offset localPosition, bool touchMode) async {
    moves.add(delta);
  }
  @override
  bool shouldBlock(double x, double y) => false;
  @override
  bool get lastIsBlocked => false;
  @override
  bool isInRemoteRect(Offset offset) => true;
  @override
  Future<bool> move(double x, double y) async {
    moves.add(Offset(x, y));
    return true;
  }
}

class _TouchInput extends Fake implements InputModel {
  final events = <(String, MouseButtons)>[];
  final wheel = <Offset>[];
  @override
  bool get keyboardPerm => true;
  @override
  bool get isViewOnly => false;
  @override
  Future<void> releaseVirtualMouseDrag() => tapUp(MouseButtons.left);
  @override
  Future<void> scrollTouchWheel(int x, int y) async =>
      wheel.add(Offset(x.toDouble(), y.toDouble()));

  @override
  bool shouldIgnoreTouchTap(Offset pos) => false;
  @override
  Future<void> tap(MouseButtons button) async => events.add(('tap', button));
  @override
  Future<void> tapDown(MouseButtons button) async =>
      events.add(('down', button));
  @override
  Future<void> tapUp(MouseButtons button) async => events.add(('up', button));
}

class _TouchSession extends Fake implements FFI {
  _TouchSession({bool touch = true}) : ffiModel = _TouchPeer(touch);
  @override
  final sessionId = const Uuid().v4obj();
  @override
  final _TouchPeer ffiModel;
  @override
  final _TouchInput inputModel = _TouchInput();
  @override
  final _TouchCursor cursorModel = _TouchCursor();
  @override
  late final canvasModel = CanvasModel(WeakReference<FFI>(this));
  @override
  final imageModel = _TouchImageModel();
}

class _TouchImageModel extends Fake implements ImageModel {
  @override
  final image = _TouchImage();
  @override
  double get minScale => 0.1;
  @override
  double get maxScale => 4;
}

class _TouchImage extends Fake implements ui.Image {}

void main() {
  testWidgets('video bitrate list selects an absolute rate in kbps',
      (tester) async {
    int? selectedKbps;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BitrateLimitDropdown(
          kbps: 8000,
          onChanged: (value) => selectedKbps = value,
        ),
      ),
    ));
    await tester.tap(find.text('8 Mbps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 Mbps').hitTestable());
    await tester.pumpAndSettle();
    expect(selectedKbps, 10000);
  });

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
    var centered = 0;
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
            onCenterCursor: () => centered++,
            actions: SessionAction.values,
            onAction: actions.add,
          );
        }),
      ),
    ));

    expect(find.byTooltip('Show virtual mouse'), findsNothing);
    await tester.tap(find.byTooltip('Show Toolbar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show virtual mouse'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Touchscreen mode'), findsOneWidget);
    expect(find.byTooltip('Hide virtual mouse'), findsOneWidget);
    await tester.tap(find.byTooltip('Center cursor'));
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
    expect(centered, 1);
    await tester.tap(find.byTooltip('Collapse toolbar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Keyboard'), findsNothing);
    expect(find.byTooltip('Show Toolbar'), findsOneWidget);
  });

  testWidgets(
      'touching a remote desktop with a long press sends only right click',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    final session = _TouchSession();
    const target = ValueKey('desktop-screen');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RawTouchGestureDetectorRegion(
          ffi: session,
          child: const ColoredBox(
            key: target,
            color: Colors.black,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ));

    await tester.longPress(find.byKey(target));
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.events, [('tap', MouseButtons.right)]);
    await tester.tap(find.byKey(target));
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.events, [
      ('tap', MouseButtons.right),
      ('down', MouseButtons.left),
      ('up', MouseButtons.left),
    ]);
  });

  testWidgets('iPhone stationary long press leaves the context menu open',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    final session = _TouchSession();
    const target = ValueKey('iphone-session-canvas');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RawTouchGestureDetectorRegion(
          ffi: session,
          awesunCanvas: true,
          child: const ColoredBox(
            key: target,
            color: Colors.black,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ));

    await tester.longPress(find.byKey(target));
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.events, [
      ('tap', MouseButtons.right),
    ]);
    final finger = await tester.startGesture(const Offset(100, 100));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await finger.moveTo(const Offset(100, 140));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.cursorModel.moves.last, const Offset(100, 140));
    expect(session.inputModel.events, [
      ('tap', MouseButtons.right),
      ('tap', MouseButtons.right),
      ('tap', MouseButtons.left),
    ]);
  });

  testWidgets(
      'iPhone scrolls an app at fit and separates two-finger scroll from pinch',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    final session = _TouchSession();
    final canvas = session.canvasModel;
    canvas.updateMobileSessionViewport(const Size(800, 600),
        keyboardOpen: false);
    canvas.update(0, 250, 0.1);
    await tester.pumpWidget(MaterialApp(
        home: RawTouchGestureDetectorRegion(
      ffi: session,
      awesunCanvas: true,
      child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
    )));
    final finger = await tester.startGesture(const Offset(200, 280));
    await finger.moveBy(const Offset(0, -42));
    await finger.moveBy(const Offset(0, -28));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.wheel.fold(Offset.zero, (a, b) => a + b),
        const Offset(0, -5));
    expect(session.cursorModel.moves, [const Offset(200, 280)]);
    expect(canvas.y, 250);

    canvas.update(-300, 0, 1);
    session.inputModel.wheel.clear();
    final first = await tester.startGesture(const Offset(200, 200));
    final second = await tester.startGesture(const Offset(300, 200));
    for (var i = 0; i < 3; i++) {
      await first.moveBy(const Offset(14, 0));
      await second.moveBy(const Offset(14, 0));
    }
    await first.up();
    await second.moveBy(const Offset(40, 0));
    await second.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.wheel.fold(Offset.zero, (a, b) => a + b),
        const Offset(3, 0));
    expect(canvas.x, -300);
    expect(canvas.scale, 1);
    expect(session.inputModel.events, isEmpty);
    session.inputModel.wheel.clear();
    final left = await tester.startGesture(const Offset(200, 200));
    final right = await tester.startGesture(const Offset(300, 200));
    for (var i = 0; i < 3; i++) {
      await left.moveBy(const Offset(-10, 0));
      await right.moveBy(const Offset(10, 0));
    }
    await left.up();
    await right.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(canvas.scale, closeTo(1.6, 0.001));
    expect(session.inputModel.wheel, isEmpty);
    canvas.setLocked(true);
    final lockedOffset = Offset(canvas.x, canvas.y);
    final drag = await tester.startGesture(const Offset(200, 200));
    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(Offset(canvas.x, canvas.y), lockedOffset);
    expect(session.inputModel.events,
        [('down', MouseButtons.left), ('up', MouseButtons.left)]);
  });

  testWidgets(
      'iPhone double tap clicks twice and tap-then-drag holds the object',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    for (final touch in [true, false]) {
      final session = _TouchSession(touch: touch);
      await tester.pumpWidget(MaterialApp(
          home: RawTouchGestureDetectorRegion(
        ffi: session,
        awesunCanvas: true,
        child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
      )));
      const origin = Offset(200, 200);
      await tester.tapAt(origin);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(origin);
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.inputModel.events,
          [('tap', MouseButtons.left), ('tap', MouseButtons.left)]);
      session.inputModel.events.clear();
      session.cursorModel.moves.clear();
      await tester.tapAt(origin);
      await tester.pump(const Duration(milliseconds: 80));
      final drag = await tester.startGesture(origin);
      await drag.moveBy(const Offset(40, 0));
      await drag.moveBy(const Offset(30, 0));
      await drag.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.inputModel.events,
          [('down', MouseButtons.left), ('up', MouseButtons.left)]);
      expect(session.cursorModel.moves.last,
          touch ? const Offset(270, 200) : const Offset(30, 0));
      session.inputModel.events.clear();
      final held = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 240));
      await held.moveBy(const Offset(40, 0),
          timeStamp: const Duration(milliseconds: 240));
      await held.moveBy(const Offset(30, 0),
          timeStamp: const Duration(milliseconds: 250));
      await held.cancel();
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.inputModel.events,
          [('down', MouseButtons.left), ('up', MouseButtons.left)]);
      expect(session.cursorModel.moves.last,
          touch ? const Offset(270, 200) : const Offset(30, 0));

      session.inputModel.events.clear();
      final a = await tester.startGesture(origin);
      final b = await tester.startGesture(origin + const Offset(80, 0));
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.inputModel.events, [('tap', MouseButtons.right)]);
    }
  });

  testWidgets(
      'a direct canvas drag follows the finger and coasts at its release speed',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    final session = _TouchSession();
    final canvas = session.canvasModel;
    canvas.updateMobileSessionViewport(const Size(800, 600), keyboardOpen: false);
    final drag = SessionCanvasDrag(tester, canvas.panDirectTouch);
    await tester.pumpWidget(MaterialApp(home: RawTouchGestureDetectorRegion(
      ffi: session,
      awesunCanvas: true,
      canvasDrag: drag,
      child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
    )));

    Future<double> glide(double step, {bool pause = false, bool atEdge = false}) async {
      final start = atEdge ? -340.0 : -4000.0;
      canvas.update(start, 0, 1);
      final finger = await tester.startGesture(const Offset(30, 100));
      for (var sample = 1; sample <= 4; sample++) {
        await finger.moveBy(Offset(step, 0),
            timeStamp: Duration(milliseconds: 8 * sample));
      }
      expect(canvas.x - start, closeTo(4 * step, 0.1));
      await finger.up(timeStamp: Duration(milliseconds: pause ? 110 : 32));
      final release = canvas.x;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final distance = canvas.x - release;
      if (atEdge) {
        expect(canvas.x, 0);
        await tester.pump(const Duration(milliseconds: 120));
        expect(canvas.x, 0);
      } else if (!pause) {
        await tester.pump(const Duration(milliseconds: 32));
        expect(canvas.x - release - distance, inExclusiveRange(0, distance));
      }
      final brake = await tester.startGesture(const Offset(200, 200));
      final stopped = canvas.x;
      await tester.pump(const Duration(milliseconds: 80));
      expect(canvas.x, stopped);
      await brake.cancel();
      await tester.pump(const Duration(milliseconds: 350));
      return distance;
    }

    final slow = await glide(80);
    final fast = await glide(160);
    expect(fast / slow, closeTo(2, 0.05));
    expect(await glide(80, pause: true), 0);
    await glide(80, atEdge: true);
    expect(session.cursorModel.moves, isEmpty);
    expect(session.inputModel.events, isEmpty);
    canvas.dispose();
  });

  testWidgets('iPhone pointer clicks at the existing cursor without jumping',
      (tester) async {
    final originalMobile = isMobile;
    isMobile = true;
    addTearDown(() => isMobile = originalMobile);
    final session = _TouchSession(touch: false);
    final canvasMoves = <Offset>[];
    const target = ValueKey('iphone-pointer-canvas');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RawTouchGestureDetectorRegion(
          ffi: session,
          awesunCanvas: true,
          canvasDrag: SessionCanvasDrag(tester, (delta) {
            canvasMoves.add(delta);
            return true;
          }),
          child: const ColoredBox(
              key: target, color: Colors.black, child: SizedBox.expand()),
        ),
      ),
    ));
    await tester.tap(find.byKey(target));
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.inputModel.events, [('tap', MouseButtons.left)]);
    expect(session.cursorModel.moves, isEmpty);
    final finger = await tester.startGesture(const Offset(100, 100));
    for (var sample = 1; sample <= 4; sample++) {
      await finger.moveBy(const Offset(30, 0),
          timeStamp: Duration(milliseconds: sample * 10));
    }
    await finger.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.cursorModel.moves, isNotEmpty);
    expect(canvasMoves, isEmpty);
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
    final ball = find.byKey(const ValueKey('session-cursor-ball'));
    await tester.longPress(ball);
    await tester.pumpAndSettle();
    expect(buttons, ['left', 'right', 'right']);
    expect(area, findsNothing);
    final before = tester.getCenter(ball);
    await tester.drag(ball, const Offset(-35, -20));
    await tester.pumpAndSettle();
    expect(tester.getCenter(ball), isNot(before));
    expect(moves, isNotEmpty);
    moves.clear();
    await tester.tap(find.byTooltip('Virtual mouse'));
    await tester.pumpAndSettle();

    final left = find.byTooltip('Left button');
    await tester.tap(left);
    await tester.tap(find.byTooltip('Right button'));
    await tester.tap(find.byTooltip('Middle mouse button'));
    expect(buttons, ['left', 'right', 'right', 'left', 'right', 'middle']);
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

    final pad =
        tester.getCenter(find.byKey(const ValueKey('session-touchpad-area')));
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
