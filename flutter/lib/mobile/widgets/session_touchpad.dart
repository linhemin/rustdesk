import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, GestureDragUpdateCallback;
import 'package:flutter/material.dart';

import '../../common.dart';
import 'session_controls.dart';

enum _PadGesture { pending, move, scroll, zoom }

class SessionTouchpad extends StatefulWidget {
  const SessionTouchpad({
    super.key,
    required this.scale,
    required this.onMove,
    required this.onLeftClick,
    required this.onRightClick,
    required this.onMiddleClick,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onScroll,
    required this.onZoom,
  });

  final double scale;
  final ValueChanged<Offset> onMove;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;
  final VoidCallback onMiddleClick;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<int> onScroll;
  final ValueChanged<double> onZoom;

  @override
  State<SessionTouchpad> createState() => _SessionTouchpadState();
}

class _SessionTouchpadState extends State<SessionTouchpad>
    with WidgetsBindingObserver {
  static const _scrollStep = 14.0;
  Offset? _position;
  bool _compact = false;
  bool _showWheel = false;
  bool _leftDragging = false;
  _PadGesture _gesture = _PadGesture.pending;
  double _scroll = 0;
  double _wheelScroll = 0;
  double _scale = 1;
  Timer? _feedbackTimer;
  IconData? _feedback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedbackTimer?.cancel();
    if (_leftDragging) widget.onDragEnd();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _finishGesture();
      _finishLeftDrag();
      _closeWheel();
    }
  }

  void _finishGesture() {
    _gesture = _PadGesture.pending;
    _scroll = 0;
    _scale = 1;
  }

  void _startLeftDrag() {
    if (_leftDragging) return;
    setState(() => _leftDragging = true);
    widget.onDragStart();
  }

  void _finishLeftDrag() {
    if (!_leftDragging) return;
    setState(() => _leftDragging = false);
    widget.onDragEnd();
  }

  void _updateGesture(ScaleUpdateDetails details) {
    if (details.pointerCount > 2) {
      _finishGesture();
      return;
    }
    if (details.pointerCount == 1) {
      if (_gesture == _PadGesture.pending) {
        _gesture = _PadGesture.move;
      }
      if (_gesture == _PadGesture.move) {
        widget.onMove(details.focalPointDelta);
      }
      return;
    }
    if (_leftDragging) return;
    if (_gesture == _PadGesture.move) _gesture = _PadGesture.pending;
    if (_gesture == _PadGesture.pending) {
      _scroll += details.focalPointDelta.dy;
      if ((details.scale - 1).abs() > .06) {
        _gesture = _PadGesture.zoom;
        _scroll = 0;
      } else if (_scroll.abs() >= _scrollStep) {
        _gesture = _PadGesture.scroll;
        // The delta that selected scrolling is already in the accumulator.
        _scroll -= details.focalPointDelta.dy;
      }
    }
    if (_gesture == _PadGesture.scroll) {
      _scroll += details.focalPointDelta.dy;
      final steps = (_scroll / _scrollStep).truncate();
      if (steps != 0) {
        _scroll -= steps * _scrollStep;
        widget.onScroll(steps);
      }
    } else if (_gesture == _PadGesture.zoom && details.scale > 0) {
      widget.onZoom(details.scale / _scale);
      _scale = details.scale;
    }
  }

  void _click(VoidCallback action, IconData icon) {
    action();
    _feedbackTimer?.cancel();
    setState(() => _feedback = icon);
    _feedbackTimer = Timer(const Duration(milliseconds: 210), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _setCompact(bool value) {
    _finishGesture();
    _finishLeftDrag();
    setState(() => _compact = value);
  }

  void _closeWheel() {
    if (_showWheel) setState(() => _showWheel = false);
  }

  Widget _wheel() => Tooltip(
        message: translate('Mouse Wheel'),
        child: GestureDetector(
          key: const ValueKey('session-touchpad-wheel'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () {
            _finishGesture();
            _finishLeftDrag();
            setState(() => _showWheel = true);
          },
          onVerticalDragStart: (_) => _wheelScroll = 0,
          onVerticalDragUpdate: (details) {
            _wheelScroll += details.delta.dy;
            final steps = (_wheelScroll / _scrollStep).truncate();
            if (steps == 0) return;
            _wheelScroll -= steps * _scrollStep;
            widget.onScroll(steps);
          },
          child: const SizedBox.square(
            dimension: 44,
            child: SessionControlsSurface(
              child:
                  Icon(Icons.unfold_more, size: 20, color: sessionControlInk),
            ),
          ),
        ),
      );

  Widget _wheelMode(double width) => Stack(
        alignment: Alignment.topCenter,
        children: [
          _SessionScrollRing(
              diameter: width,
              onScroll: widget.onScroll,
              onFinish: _closeWheel),
          Positioned(
            bottom: 0,
            child: SessionControlsSurface(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: translate('Middle mouse button'),
                    onPressed: widget.onMiddleClick,
                    color: sessionControlInk,
                    icon: const Icon(Icons.mouse_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: translate('Close'),
                    onPressed: _closeWheel,
                    color: sessionControlInk,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final scale = widget.scale.isFinite
              ? widget.scale.clamp(.8, 1.35).toDouble()
              : 1.0;
          final available = constraints.biggest;
          final diameter = math.min(
              math.min(172 * scale, available.width), available.height - 48);
          final compact = _compact || diameter < 132;
          final width = compact ? 48.0 : diameter;
          final height = compact ? 48.0 : diameter + 48;
          if (available.width < width || available.height < height) {
            return const SizedBox.shrink();
          }
          final halfWidth = width / 2;
          final halfHeight = height / 2;
          Offset withinBounds(Offset offset) => Offset(
                offset.dx
                    .clamp(halfWidth, available.width - halfWidth)
                    .toDouble(),
                offset.dy
                    .clamp(halfHeight, available.height - halfHeight)
                    .toDouble(),
              );
          final position = withinBounds(_position ??
              Offset(available.width - halfWidth - 12, available.height * .67));
          void moveHandle(DragUpdateDetails details) => setState(() {
                _position = withinBounds(
                    withinBounds(_position ?? position) + details.delta);
              });

          return Stack(
            children: [
              Positioned(
                left: position.dx - halfWidth,
                top: position.dy - halfHeight,
                width: width,
                height: height,
                child: compact
                    ? SessionControlsSurface(
                        child: GestureDetector(
                          onPanUpdate: moveHandle,
                          child: IconButton(
                            tooltip: translate('Virtual mouse'),
                            onPressed: () => _setCompact(false),
                            color: sessionControlAccent,
                            icon: const Icon(Icons.mouse_outlined),
                          ),
                        ),
                      )
                    : _showWheel
                        ? _wheelMode(width)
                        : _mouseControls(moveHandle),
              ),
            ],
          );
        },
      );

  Widget _mouseControls(GestureDragUpdateCallback moveHandle) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: moveHandle,
                child: const SizedBox.square(
                  dimension: 44,
                  child: SessionControlsSurface(
                    child: Icon(Icons.drag_indicator,
                        size: 18, color: sessionControlInk),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SessionControlsSurface(
                child: IconButton(
                  tooltip: translate('Minimize'),
                  color: sessionControlInk,
                  onPressed: () => _setCompact(true),
                  icon: const Icon(Icons.remove, size: 18),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _mouseButton('L', 'Left button', widget.onLeftClick,
                  draggable: true),
              const SizedBox(width: 4),
              Expanded(child: _pointerSurface()),
              const SizedBox(width: 4),
              _mouseButton('R', 'Right button', widget.onRightClick),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _mouseButton('M', 'Middle mouse button', widget.onMiddleClick),
              const SizedBox(width: 4),
              _wheel(),
            ],
          ),
        ],
      );

  Widget _mouseButton(String label, String description, VoidCallback onClick,
          {bool draggable = false}) =>
      Tooltip(
        message: translate(description),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => _click(onClick, Icons.ads_click),
          onPanStart: draggable ? (_) => _startLeftDrag() : null,
          onPanUpdate: draggable ? (event) => widget.onMove(event.delta) : null,
          onPanEnd: draggable ? (_) => _finishLeftDrag() : null,
          onPanCancel: draggable ? _finishLeftDrag : null,
          child: SizedBox(
            width: 40,
            height: 52,
            child: SessionControlsSurface(
              child: Center(
                child: Text(label,
                    style: TextStyle(
                      color: draggable && _leftDragging
                          ? sessionControlAccent
                          : sessionControlInk,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ),
        ),
      );

  Widget _pointerSurface() => Listener(
        onPointerCancel: (_) => _finishGesture(),
        child: GestureDetector(
          key: const ValueKey('session-touchpad-area'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => _click(widget.onLeftClick, Icons.ads_click),
          onLongPress: () => _click(widget.onRightClick, Icons.more_horiz),
          onDoubleTap: () => _setCompact(true),
          onScaleStart: (_) => _finishGesture(),
          onScaleUpdate: _updateGesture,
          onScaleEnd: (_) => _finishGesture(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 76,
            decoration: BoxDecoration(
              color: _feedback == null
                  ? const Color(0xD9293946)
                  : const Color(0xFF385A50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _leftDragging || _feedback != null
                    ? sessionControlAccent
                    : const Color(0x4D93A9B8),
              ),
            ),
            child: Icon(
              _feedback ?? Icons.control_camera_outlined,
              color: sessionControlAccent,
              size: 26,
            ),
          ),
        ),
      );
}

class _SessionScrollRing extends StatefulWidget {
  const _SessionScrollRing(
      {required this.diameter, required this.onScroll, required this.onFinish});

  final double diameter;
  final ValueChanged<int> onScroll;
  final VoidCallback onFinish;

  @override
  State<_SessionScrollRing> createState() => _SessionScrollRingState();
}

class _SessionScrollRingState extends State<_SessionScrollRing> {
  static const _stepAngle = math.pi / 9;
  int? _pointer;
  double? _angle;
  double _pending = 0;

  double get _outer => widget.diameter / 2;
  double get _inner => _outer * .58;
  Offset _vector(PointerEvent event) =>
      event.localPosition - Offset(_outer, _outer);

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _pending = 0;
    final vector = _vector(event);
    setState(() => _angle = math.atan2(vector.dy, vector.dx));
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    final vector = _vector(event);
    if (vector.distance < _inner / 2) {
      setState(() => _angle = null);
      return;
    }
    final angle = math.atan2(vector.dy, vector.dx);
    final previous = _angle ?? angle;
    final delta = angle - previous;
    final wrapped = (delta + math.pi) % (2 * math.pi) - math.pi;
    _pending -= wrapped;
    final steps = (_pending / _stepAngle).truncate();
    if (steps != 0) {
      _pending -= steps * _stepAngle;
      widget.onScroll(steps);
    }
    setState(() => _angle = angle);
  }

  void _finish(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) => Listener(
        key: const ValueKey('session-touchpad-scroll-ring'),
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _finish,
        onPointerCancel: _finish,
        child: CustomPaint(
          size: Size.square(widget.diameter),
          painter: _ScrollRingPainter(_outer, _inner, _angle),
        ),
      );
}

class _ScrollRingPainter extends CustomPainter {
  const _ScrollRingPainter(this.outer, this.inner, this.angle);

  final double outer;
  final double inner;
  final double? angle;

  Offset get _center => Offset(outer, outer);

  @override
  bool hitTest(Offset position) {
    final radius = (position - _center).distance;
    return radius >= inner && radius <= outer;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = _center;
    final radius = (outer + inner) / 2;
    final track = Paint()
      ..color = const Color(0xBA253744)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outer - inner;
    canvas.drawCircle(center, radius, track);
    final tick = Paint()
      ..color = const Color(0x99D2E5E8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final theta = i * math.pi / 6;
      final direction = Offset(math.cos(theta), math.sin(theta));
      canvas.drawLine(center + direction * (radius - 3),
          center + direction * (radius + 3), tick);
    }
    final position = angle;
    if (position != null) {
      canvas.drawCircle(
          center + Offset(math.cos(position), math.sin(position)) * radius,
          5,
          Paint()..color = sessionControlAccent);
    }
  }

  @override
  bool shouldRepaint(covariant _ScrollRingPainter oldDelegate) =>
      outer != oldDelegate.outer ||
      inner != oldDelegate.inner ||
      angle != oldDelegate.angle;
}
