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
