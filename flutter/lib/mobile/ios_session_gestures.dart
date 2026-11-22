import 'package:flutter/gestures.dart';
import 'package:flutter_hbb/consts.dart';

/// Distinguishes translating two fingertips from changing their separation.
/// The remaining finger cannot start a new drag until both have lifted.
class IosSessionScaleGestureRecognizer extends ScaleGestureRecognizer {
  IosSessionScaleGestureRecognizer()
      : super(supportedDevices: kTouchBasedDeviceKinds) {
    onUpdate = _update;
  }

  void Function(Offset origin, DragUpdateDetails update, bool held)?
      onSingleDrag;
  void Function(Offset origin, Offset delta)? onScroll;
  void Function(double factor, Offset previousFocus, Offset translation)?
      onPinch;
  GestureDragUpdateCallback? onThreeFingerDrag;
  void Function(bool chord)? onContactDown;

  final _positions = <int, Offset>{};
  final _moved = <int>{};
  int _maximumContacts = 0;
  int _pairSamples = 0;
  Duration _downTime = Duration.zero;
  bool? _held;
  Offset _origin = Offset.zero;
  Offset _previousCenter = Offset.zero;
  double _initialSpan = 0;
  double _previousSpan = 0;
  bool? _pinching;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _positions[event.pointer] = event.localPosition;
      if (_positions.length > _maximumContacts) {
        _maximumContacts = _positions.length;
        if (_maximumContacts == 1) {
          _origin = _previousCenter = event.localPosition;
          _downTime = event.timeStamp;
          _held = null;
        } else if (_maximumContacts == 2) {
          final a = _positions.values.first;
          final b = _positions.values.last;
          _origin = _previousCenter = (a + b) / 2;
          _initialSpan = _previousSpan = (a - b).distance;
          _pinching = null;
          _moved.clear();
          _pairSamples = 0;
        }
      }
      onContactDown?.call(_maximumContacts > 1);
    } else if (event is PointerMoveEvent) {
      _positions[event.pointer] = event.localPosition;
      if (_maximumContacts == 1 &&
          (event.localPosition - _origin).distance > kTouchSlop / 2) {
        _held ??=
            event.timeStamp - _downTime >= const Duration(milliseconds: 200);
      }
      if (_positions.length == 2 && event.delta != Offset.zero) {
        _moved.add(event.pointer);
        _pairSamples++;
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _positions.remove(event.pointer);
      if (_positions.isEmpty) _maximumContacts = 0;
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _positions.clear();
    _maximumContacts = 0;
  }

  void _update(ScaleUpdateDetails details) {
    if (_positions.length != _maximumContacts) return;
    if (_maximumContacts != 2) {
      final update = DragUpdateDetails(
        globalPosition: details.focalPoint,
        localPosition: details.localFocalPoint,
        delta: _maximumContacts == 1
            ? details.localFocalPoint - _previousCenter
            : details.focalPointDelta,
      );
      _previousCenter = details.localFocalPoint;
      if (_maximumContacts == 1) {
        onSingleDrag?.call(_origin, update, _held == true);
      }
      if (_maximumContacts == 3) onThreeFingerDrag?.call(update);
      return;
    }

    final a = _positions.values.first;
    final b = _positions.values.last;
    final center = (a + b) / 2;
    final span = (a - b).distance;
    if (_pinching == null) {
      // UIKit reports fingers separately. Allow the partner's sample to arrive
      // before interpreting a parallel swipe as a pinch with a fixed anchor.
      if (_moved.length < 2 && _pairSamples < 3) return;
      final separation = (span - _initialSpan).abs();
      final travel = (center - _origin).distance;
      if (separation < kTouchSlop && travel < kTouchSlop) return;
      _pinching = separation > travel;
    }
    if (_pinching!) {
      if (_previousSpan > 0 && span > 0) {
        onPinch?.call(
            span / _previousSpan, _previousCenter, center - _previousCenter);
      }
    } else {
      onScroll?.call(_origin, center - _previousCenter);
    }
    _previousCenter = center;
    _previousSpan = span;
  }
}
