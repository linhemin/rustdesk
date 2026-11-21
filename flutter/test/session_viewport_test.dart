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
    final shift =
        nativeKeyboardRevealOffset(before.dy, ffi.cursorModel.y, 1000, 640);
    canvas.setNativeKeyboardOffset(shift);
    expect(canvas.y + ffi.cursorModel.y, 320);
    expect(canvas.getSize(), size);
    canvas.setNativeKeyboardOffset(shift / 2);
    expect(canvas.y, before.dy + shift / 2);
    canvas.setNativeKeyboardOffset(0);
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
}
