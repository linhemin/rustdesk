import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Tracks a direct finger drag independently of the scale recognizer's capped
/// fling velocity. Only an accepted, single-finger canvas pan can coast.
class SessionCanvasDrag {
  SessionCanvasDrag(this.vsync, this.panBy);

  final TickerProvider vsync;
  final bool Function(Offset) panBy;
  final _contacts = <int>{};
  VelocityTracker? _velocity;
  Offset? _lastPosition;
  Duration _lastMove = Duration.zero;
  bool _dragged = false;
  Ticker? _coast;

  void interrupt() {
    _coast?.dispose();
    _coast = null;
    _velocity = null;
    _lastPosition = null;
    _dragged = false;
  }

  void detach() {
    interrupt();
    _contacts.clear();
  }

  void down(PointerDownEvent event) {
    interrupt();
    _contacts.add(event.pointer);
    if (_contacts.length != 1 || event.kind != PointerDeviceKind.touch) return;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _lastPosition = event.localPosition;
  }

  void move(PointerMoveEvent event) {
    if (!event.synthesized) {
      _velocity?.addPosition(event.timeStamp, event.localPosition);
      _lastMove = event.timeStamp;
    }
  }

  void drag(DragUpdateDetails event) {
    final last = _lastPosition;
    if (last != null) _lastPosition = event.localPosition;
    final delta = last == null ? event.delta : event.localPosition - last;
    if (delta != Offset.zero) _dragged = panBy(delta);
  }

  void cancel(PointerCancelEvent event) {
    _contacts.remove(event.pointer);
    interrupt();
  }

  void up(PointerUpEvent event) {
    _contacts.remove(event.pointer);
    final tracker = _velocity;
    final dragged = _dragged;
    interrupt();
    if (!dragged ||
        tracker == null ||
        _contacts.isNotEmpty ||
        event.timeStamp - _lastMove > const Duration(milliseconds: 40)) return;
    final velocity = tracker.getVelocity().pixelsPerSecond;
    final speed = velocity.distance;
    if (!speed.isFinite || speed < kMinFlingVelocity) return;

    final direction = velocity / speed;
    final friction = FrictionSimulation(0.008, 0, speed,
        tolerance: const Tolerance(velocity: 5));
    var previous = 0.0;
    _coast = vsync.createTicker((elapsed) {
      final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final position = friction.x(seconds);
      final delta = position - previous;
      previous = position;
      if ((delta > 0 && !panBy(direction * delta)) ||
          friction.isDone(seconds)) {
        interrupt();
      }
    })
      ..start();
  }
}
