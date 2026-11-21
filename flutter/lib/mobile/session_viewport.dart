import 'dart:math' as math;
import 'dart:ui';

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
