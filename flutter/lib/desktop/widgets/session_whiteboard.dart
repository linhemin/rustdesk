import 'dart:async';

import 'package:flutter/material.dart';

import '../../common.dart';

enum WhiteboardTool { off, pen, laser }

class WhiteboardStroke {
  WhiteboardStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  final List<Offset> points;
  final Color color;
  final double width;
}

class WhiteboardController extends ChangeNotifier {
  WhiteboardTool _tool = WhiteboardTool.off;
  Color _color = const Color(0xFFFF4D4F);
  double _strokeWidth = 3.0;
  final List<WhiteboardStroke> _strokes = [];
  Offset? _laserPoint;
  Timer? _laserFadeTimer;

  WhiteboardTool get tool => _tool;
  bool get active => _tool != WhiteboardTool.off;
  Color get color => _color;
  double get strokeWidth => _strokeWidth;
  List<WhiteboardStroke> get strokes => List.unmodifiable(_strokes);
  Offset? get laserPoint => _laserPoint;

  void setTool(WhiteboardTool next) {
    if (_tool == next) return;
    _tool = next;
    if (_tool != WhiteboardTool.laser) {
      _laserPoint = null;
      _laserFadeTimer?.cancel();
    }
    notifyListeners();
  }

  void toggle() {
    setTool(active ? WhiteboardTool.off : WhiteboardTool.pen);
  }

  void setColor(Color next) {
    if (_color == next) return;
    _color = next;
    notifyListeners();
  }

  void setStrokeWidth(double next) {
    if (_strokeWidth == next) return;
    _strokeWidth = next;
    notifyListeners();
  }

  void startStroke(Offset point) {
    if (_tool == WhiteboardTool.laser) {
      updateLaser(point);
      return;
    }
    if (_tool != WhiteboardTool.pen) return;
    _strokes.add(WhiteboardStroke(
      points: [point],
      color: _color,
      width: _strokeWidth,
    ));
    notifyListeners();
  }

  void extendStroke(Offset point) {
    if (_tool == WhiteboardTool.laser) {
      updateLaser(point);
      return;
    }
    if (_tool != WhiteboardTool.pen || _strokes.isEmpty) return;
    _strokes.last.points.add(point);
    notifyListeners();
  }

  void updateLaser(Offset point) {
    _laserPoint = point;
    _laserFadeTimer?.cancel();
    _laserFadeTimer = Timer(const Duration(milliseconds: 900), () {
      _laserPoint = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    _laserFadeTimer?.cancel();
    _laserFadeTimer = null;
    if (_strokes.isEmpty && _laserPoint == null) return;
    _strokes.clear();
    _laserPoint = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _laserFadeTimer?.cancel();
    super.dispose();
  }
}

/// Interactive desktop whiteboard & laser pointer overlay layered over a remote session.
class SessionWhiteboardOverlay extends StatelessWidget {
  const SessionWhiteboardOverlay({super.key, required this.controller});

  final WhiteboardController controller;

  static const List<Color> _palette = [
    Color(0xFFFF4D4F),
    Color(0xFFFAAD14),
    Color(0xFF52C41A),
    Color(0xFF1677FF),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.active && controller.strokes.isEmpty) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !controller.active,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => controller.startStroke(d.localPosition),
                  onPanUpdate: (d) => controller.extendStroke(d.localPosition),
                  onTapDown: (d) {
                    if (controller.tool == WhiteboardTool.laser) {
                      controller.updateLaser(d.localPosition);
                    }
                  },
                  child: CustomPaint(
                    painter: _WhiteboardPainter(
                      strokes: controller.strokes,
                      laserPoint: controller.laserPoint,
                      laserColor: controller.color,
                    ),
                  ),
                ),
              ),
            ),
            if (controller.active)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: const Color(0xE614171D),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToolChip(
                            icon: Icons.edit_rounded,
                            selected: controller.tool == WhiteboardTool.pen,
                            tooltip: 'Pen',
                            onTap: () => controller.setTool(WhiteboardTool.pen),
                          ),
                          _ToolChip(
                            icon: Icons.flare_rounded,
                            selected: controller.tool == WhiteboardTool.laser,
                            tooltip: 'Laser',
                            onTap: () =>
                                controller.setTool(WhiteboardTool.laser),
                          ),
                          const SizedBox(width: 6),
                          for (final c in _palette)
                            GestureDetector(
                              onTap: () => controller.setColor(c),
                              child: Container(
                                width: 18,
                                height: 18,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: controller.color == c
                                        ? Colors.white
                                        : Colors.white30,
                                    width: controller.color == c ? 2.5 : 1,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: translate('Clear'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_sweep_outlined,
                                color: Colors.white70, size: 18),
                            onPressed: controller.clear,
                          ),
                          IconButton(
                            tooltip: translate('Close'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 18),
                            onPressed: () =>
                                controller.setTool(WhiteboardTool.off),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
    );
  }
}

class _WhiteboardPainter extends CustomPainter {
  const _WhiteboardPainter({
    required this.strokes,
    required this.laserPoint,
    required this.laserColor,
  });

  final List<WhiteboardStroke> strokes;
  final Offset? laserPoint;
  final Color laserColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width * 0.6,
            paint..style = PaintingStyle.fill);
      } else {
        final path = Path()
          ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    final laser = laserPoint;
    if (laser != null) {
      canvas.drawCircle(
        laser,
        14,
        Paint()..color = laserColor.withOpacity(0.28),
      );
      canvas.drawCircle(
        laser,
        6,
        Paint()..color = laserColor,
      );
      canvas.drawCircle(
        laser,
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_WhiteboardPainter oldDelegate) => true;
}
