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
