import 'dart:math' as math;
import 'dart:ui';

double? mobileHeightFitScale(Size viewport, Size frame) {
  if (viewport.isEmpty ||
      frame.isEmpty ||
      !viewport.isFinite ||
      !frame.isFinite) {
    return null;
  }
  return viewport.height / frame.height;
}

Size sessionVisibleViewport(Rect canvas, Rect? bottomPanel) {
  if (bottomPanel == null || !bottomPanel.overlaps(canvas)) return canvas.size;
  return Size(canvas.width, math.max(0, bottomPanel.top - canvas.top));
}

Offset clampSessionCanvas(Offset offset, Size image, Size viewport) {
  double axis(double value, double extent, double span) {
    if (extent.isFinite && span.isFinite && extent > 0 && span > 0) {
      final margin = span - extent;
      if (margin >= 0) return margin / 2;
      return value.clamp(margin, 0).toDouble();
    }
    return value;
  }

  return Offset(
    axis(offset.dx, image.width, viewport.width),
    axis(offset.dy, image.height, viewport.height),
  );
}

Offset revealSessionInput(
  Offset offset,
  Offset inputInImage,
  Size image,
  Size viewport,
) {
  final current = clampSessionCanvas(offset, image, viewport);
  final inputOnScreen = current + inputInImage;
  final margin = math.min(24.0, viewport.height / 5);
  final dx = inputOnScreen.dx < 0 || inputOnScreen.dx >= viewport.width
      ? viewport.width / 2 - inputOnScreen.dx
      : 0.0;
  final dy =
      inputOnScreen.dy < 0 || inputOnScreen.dy >= viewport.height - margin
          ? viewport.height / 2 - inputOnScreen.dy
          : 0.0;
  return clampSessionCanvas(current + Offset(dx, dy), image, viewport);
}

/// The remote frame can extend into the margin needed to bring its last pixel
/// under the tip, which sits above and to the left of the touch contact.
Offset panNativePointerCanvas(
    Offset origin, Size image, Rect viewport, Offset tip, Offset delta) {
  if (image.isEmpty || viewport.isEmpty || !image.isFinite) return origin;

  double axis(double current, double extent, double start, double end,
      double point, double movement) {
    final cursor = point.clamp(start, math.max(start, end - 1)).toDouble();
    if (movement < 0) {
      final limit = math.min(end - extent, cursor - extent + 1);
      return math.max(current + movement, math.min(current, limit));
    }
    if (movement > 0) {
      final limit = math.max(start, cursor);
      return math.min(current + movement, math.max(current, limit));
    }
    return current;
  }

  return Offset(
    axis(origin.dx, image.width, viewport.left, viewport.right, tip.dx,
        delta.dx),
    axis(origin.dy, image.height, viewport.top, viewport.bottom, tip.dy,
        delta.dy),
  );
}

Offset? clampNativePointer(Offset tip, Rect video, Rect viewport) {
  final visible = video.intersect(viewport);
  if (visible.isEmpty) return null;
  return Offset(
    tip.dx
        .clamp(visible.left, math.max(visible.left, visible.right - 1))
        .toDouble(),
    tip.dy
        .clamp(visible.top, math.max(visible.top, visible.bottom - 1))
        .toDouble(),
  );
}

double nativeKeyboardLift(double fullHeight, double visibleHeight) =>
    (visibleHeight - fullHeight).clamp(-fullHeight, 0.0).toDouble();

class PointerPanStep {
  const PointerPanStep({
    required this.cursorDelta,
    required this.canvasPanScreen,
  });

  final Offset cursorDelta;
  final Offset canvasPanScreen;
}

/// Computes smooth pointer movement and edge-follow canvas panning.
///
/// The viewport stays completely still while the pointer moves inside the
/// central free zone. Panning only engages when the pointer moves outward into
/// an edge margin where additional remote content exists and panning is
/// unlocked. Any residual cursor movement past the canvas boundary continues
/// smoothly to the outermost display pixel.
PointerPanStep computePointerPanStep({
  required Offset cursor,
  required Offset remoteDelta,
  required Rect visible,
  required Rect display,
  required double scale,
  required bool allowCanvasPan,
}) {
  if (!scale.isFinite || scale <= 0 || display.isEmpty || visible.isEmpty) {
    return const PointerPanStep(
      cursorDelta: Offset.zero,
      canvasPanScreen: Offset.zero,
    );
  }

  (double, double) solveAxis({
    required double pos,
    required double delta,
    required double visMin,
    required double visMax,
    required double dispMin,
    required double dispMax,
  }) {
    if (!delta.isFinite || delta == 0) return (0.0, 0.0);

    if (!allowCanvasPan) {
      final minAllowed = math.max(dispMin, visMin);
      final maxAllowed = math.min(dispMax, visMax);
      if (minAllowed > maxAllowed) {
        final next = (pos + delta).clamp(dispMin, dispMax).toDouble();
        return (next - pos, 0.0);
      }
      final next = (pos + delta).clamp(minAllowed, maxAllowed).toDouble();
      return (next - pos, 0.0);
    }

    final next = (pos + delta).clamp(dispMin, dispMax).toDouble();
    final actualDelta = next - pos;
    if (actualDelta == 0) return (0.0, 0.0);

    final screenSpan = (visMax - visMin) * scale;
    final screenMargin =
        math.min(screenSpan * 0.25, (screenSpan * 0.14).clamp(24.0, 56.0));
    final edgeMargin = screenMargin / scale;

    double canvasPanScreen = 0.0;
    if (actualDelta > 0) {
      final remainingHidden = math.max(0.0, dispMax - visMax);
      if (remainingHidden > 0.5) {
        final trigger = visMax - edgeMargin;
        if (next > trigger) {
          final overshoot = next - math.max(pos, trigger);
          if (overshoot > 0) {
            final panRemote = math.min(overshoot, remainingHidden);
            canvasPanScreen = -panRemote * scale;
          }
        }
      }
    } else {
      final remainingHidden = math.max(0.0, visMin - dispMin);
      if (remainingHidden > 0.5) {
        final trigger = visMin + edgeMargin;
        if (next < trigger) {
          final overshoot = math.min(pos, trigger) - next;
          if (overshoot > 0) {
            final panRemote = math.min(overshoot, remainingHidden);
            canvasPanScreen = panRemote * scale;
          }
        }
      }
    }
    return (actualDelta, canvasPanScreen);
  }

  final (dx, panX) = solveAxis(
    pos: cursor.dx,
    delta: remoteDelta.dx,
    visMin: visible.left,
    visMax: visible.right,
    dispMin: display.left,
    dispMax: display.right,
  );
  final (dy, panY) = solveAxis(
    pos: cursor.dy,
    delta: remoteDelta.dy,
    visMin: visible.top,
    visMax: visible.bottom,
    dispMin: display.top,
    dispMax: display.bottom,
  );
  return PointerPanStep(
    cursorDelta: Offset(dx, dy),
    canvasPanScreen: Offset(panX, panY),
  );
}

/// Computes proportional canvas edge-panning velocity (in logical px/s) when
/// pushing the virtual mouse past its clamped viewport bounds.
Offset computeAwesunEdgePanVelocity({
  required Offset requestedCenter,
  required Offset minCenter,
  required Offset maxCenter,
  double deadzone = 4.0,
  double rampDistance = 76.0,
  double minSpeed = 60.0,
  double maxSpeed = 520.0,
}) {
  double axis(double requested, double lower, double upper) {
    final double push;
    final double sign;
    if (requested < lower) {
      push = lower - requested;
      sign = 1.0;
    } else if (requested > upper) {
      push = requested - upper;
      sign = -1.0;
    } else {
      return 0.0;
    }
    if (push <= deadzone) return 0.0;
    final t = ((push - deadzone) / rampDistance).clamp(0.0, 1.0).toDouble();
    final speed = minSpeed + (maxSpeed - minSpeed) * t * t;
    return sign * speed;
  }

  return Offset(
    axis(requestedCenter.dx, minCenter.dx, maxCenter.dx),
    axis(requestedCenter.dy, minCenter.dy, maxCenter.dy),
  );
}
