import 'dart:ui';

import 'package:flutter_hbb/mobile/session_viewport.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _RemoteDisplay extends Fake implements FfiModel {
  @override
  Rect get rect => const Rect.fromLTWH(0, 0, 800, 1000);
}

class _RemoteCursor extends Fake implements CursorModel {
  @override
  double get x => 250;
  @override
  double get y => 820;
}

class _Session extends Fake implements FFI {
  @override
  final sessionId = const Uuid().v4obj();
  @override
  final ffiModel = _RemoteDisplay();
  @override
  final cursorModel = _RemoteCursor();
}

void main() {
  test('portrait sessions fill height without stretching the remote frame', () {
    final scale =
        mobileHeightFitScale(const Size(393, 780), const Size(1920, 1080))!;
    expect(1080 * scale, closeTo(780, 0.001));
    expect(1920 * scale, greaterThan(393));
    expect(mobileHeightFitScale(Size.zero, const Size(1920, 1080)), isNull);
  });

  test('only actual bottom-panel overlap is subtracted from resized canvas',
      () {
    const canvas = Rect.fromLTWH(10, 44, 390, 416);
    const panel = Rect.fromLTRB(16, 312, 384, 451);
    expect(sessionVisibleViewport(canvas, panel), const Size(390, 268));
    expect(
      sessionVisibleViewport(canvas, const Rect.fromLTWH(0, 480, 390, 90)),
      canvas.size,
    );
  });

  test('panning stops at the edges and a fitted image remains centered', () {
    expect(
      clampSessionCanvas(
          const Offset(500, -600), const Size(800, 900), const Size(390, 620)),
      const Offset(0, -280),
    );
    expect(
      clampSessionCanvas(
          const Offset(-500, 600), const Size(260, 220), const Size(390, 620)),
      const Offset(65, 200),
    );
  });

  test('native mouse pans a wide desktop to either edge under the tip', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 600);
    const image = Size(1000, 600);
    const rightTip = Offset(292, 514);
    final end = panNativePointerCanvas(const Offset(-300, 0), image, viewport,
        rightTip, const Offset(-2000, -1000));
    expect(end, const Offset(-707, -85));
    expect(
      clampNativePointer(rightTip, end & image, viewport),
      rightTip,
    );
    expect(clampNativePointer(const Offset(399, 599), end & image, viewport),
        rightTip);

    // Height-fit multiplication can round slightly below the available height.
    expect(
      panNativePointerCanvas(Offset.zero, const Size(1000, 599.9999999999999),
          viewport, rightTip, const Offset(0, -20)).dy,
      -20,
    );

    const leftTip = Offset(-60, 12);
    final start = panNativePointerCanvas(
        end, image, viewport, leftTip, const Offset(2000, 0));
    expect(start, const Offset(0, -85));
    expect(clampNativePointer(leftTip, start & image, viewport),
        const Offset(0, 12));
  });

  test('holding the mouse hub reaches the last pixel of a letterboxed desktop',
      () {
    const viewport = Rect.fromLTWH(0, 0, 844, 390);
    const image = Size(692, 390);
    const tip = Offset(674, 244);
    var origin = const Offset(76, 0);
    for (var tick = 0; tick < 10; tick++) {
      origin = panNativePointerCanvas(
          origin, image, viewport, tip, const Offset(-20, 0));
    }
    expect(tip.dx - origin.dx, image.width - 1);
    expect(origin.dy, 0);
    expect(panNativePointerCanvas(origin, image, viewport, tip, Offset.zero),
        origin);
  });

  test('native keyboard translation restores a panned canvas without a refit',
      () {
    final ffi = _Session();
    final canvas = CanvasModel(WeakReference<FFI>(ffi));
    const size = Size(400, 1000);
    canvas.updateMobileSessionViewport(size, keyboardOpen: false);
    canvas.update(-140, 0, 1);
    canvas.panNativeVirtualMouse(
        const Offset(0, -50), Offset.zero & size, const Offset(292, 900));
    final before = Offset(canvas.x, canvas.y);
    expect(before.dy, -50);
    final shift = nativeKeyboardLift(size.height, 640);
    expect(shift, -360);
    canvas.setNativeKeyboardOffset(shift);
    expect(canvas.y, before.dy - 360);
    expect(canvas.getSize(), size);
    canvas.setNativeKeyboardOffset(shift / 2);
    expect(canvas.y, before.dy + shift / 2);
    canvas.setNativeKeyboardOffset(nativeKeyboardLift(size.height, size.height));
    expect(Offset(canvas.x, canvas.y), before);
    expect(canvas.scale, 1);
    canvas.dispose();
  });

  test('opening the keyboard reveals the remote cursor and closing restores',
      () {
    final ffi = _Session();
    final canvas = CanvasModel(WeakReference<FFI>(ffi));
    canvas.updateMobileSessionViewport(const Size(400, 500),
        keyboardOpen: false);
    canvas.update(-100, -400, 1);
    canvas.updateMobileSessionViewport(const Size(400, 190),
        keyboardOpen: true);
    expect(ffi.cursorModel.y + canvas.y, 95);
    expect(canvas.getSize(), const Size(400, 190));
    expect(canvas.getAdjustY(), 0);

    canvas.updateMobileSessionViewport(const Size(400, 500),
        keyboardOpen: false);
    expect(Offset(canvas.x, canvas.y), const Offset(-100, -400));
    expect(canvas.scale, 1);
    canvas.dispose();
  });

  test('pointer pan keeps viewport steady inside free zone and pans smoothly at edges',
      () {
    const display = Rect.fromLTWH(0, 0, 1920, 1080);
    const visible = Rect.fromLTWH(200, 100, 400, 600);

    // Moving across the center of the viewport must NOT jitter or pan the screen.
    final mid = computePointerPanStep(
      cursor: const Offset(390, 390),
      remoteDelta: const Offset(40, 30),
      visible: visible,
      display: display,
      scale: 1.0,
      allowCanvasPan: true,
    );
    expect(mid.cursorDelta, const Offset(40, 30));
    expect(mid.canvasPanScreen, Offset.zero);

    // Moving outward into the right edge margin smoothly pans the viewport left.
    final edge = computePointerPanStep(
      cursor: const Offset(550, 390),
      remoteDelta: const Offset(40, 0),
      visible: visible,
      display: display,
      scale: 1.0,
      allowCanvasPan: true,
    );
    expect(edge.cursorDelta, const Offset(40, 0));
    expect(edge.canvasPanScreen.dx, lessThan(0));
    expect(edge.canvasPanScreen.dy, 0);

    // Locked canvas never pans and keeps cursor inside visible bounds.
    final locked = computePointerPanStep(
      cursor: const Offset(580, 390),
      remoteDelta: const Offset(50, 0),
      visible: visible,
      display: display,
      scale: 1.0,
      allowCanvasPan: false,
    );
    expect(locked.canvasPanScreen, Offset.zero);
    expect(locked.cursorDelta.dx, 20);

    // When only 5px of hidden desktop remains, canvas finishes panning 5px and
    // cursor still travels the full remaining distance to the outer edge.
    const nearEnd = Rect.fromLTWH(1515, 100, 400, 600);
    final finish = computePointerPanStep(
      cursor: const Offset(1890, 390),
      remoteDelta: const Offset(25, 0),
      visible: nearEnd,
      display: display,
      scale: 1.0,
      allowCanvasPan: true,
    );
    expect(finish.canvasPanScreen.dx, closeTo(-5, 0.001));
    expect(finish.cursorDelta.dx, 25);
  });

  test('Awesun edge pan velocity stays zero inside viewport and ramps smoothly past edges',
      () {
    const minC = Offset(100, 80);
    const maxC = Offset(320, 720);

    // Inside bounds or within deadzone -> zero velocity.
    expect(
      computeAwesunEdgePanVelocity(
        requestedCenter: const Offset(200, 400),
        minCenter: minC,
        maxCenter: maxC,
      ),
      Offset.zero,
    );
    expect(
      computeAwesunEdgePanVelocity(
        requestedCenter: const Offset(323, 400),
        minCenter: minC,
        maxCenter: maxC,
      ),
      Offset.zero,
    );

    // Gentle push vs strong push ramps smoothly in negative canvas direction.
    final gentle = computeAwesunEdgePanVelocity(
      requestedCenter: const Offset(335, 400),
      minCenter: minC,
      maxCenter: maxC,
    );
    final firm = computeAwesunEdgePanVelocity(
      requestedCenter: const Offset(400, 400),
      minCenter: minC,
      maxCenter: maxC,
    );
    expect(gentle.dx, lessThan(0));
    expect(firm.dx, lessThan(gentle.dx));
    expect(firm.dx, closeTo(-520, 0.01));

    // Left push pans canvas positive.
    final leftPush = computeAwesunEdgePanVelocity(
      requestedCenter: const Offset(60, 400),
      minCenter: minC,
      maxCenter: maxC,
    );
    expect(leftPush.dx, greaterThan(0));
  });
}
