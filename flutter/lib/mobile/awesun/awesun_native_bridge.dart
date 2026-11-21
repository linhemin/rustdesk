import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/input_model.dart';
import '../../models/model.dart';

class AwesunNativeBridge {
  AwesunNativeBridge({
    required this.inputModel,
    required this.cursorModel,
    required this.canvasPoint,
    required this.canSendInput,
    required this.onClose,
    required this.onCommand,
    required this.onVirtualMove,
    required this.onVirtualClick,
    required this.onVirtualDrag,
    required this.onVirtualScroll,
    this.onPointerVisibility,
    this.onVideoTexture,
  });

  final InputModel inputModel;
  final CursorModel cursorModel;
  final Offset? Function(Offset) canvasPoint;
  final bool Function() canSendInput;
  final VoidCallback onClose;
  final Future<Object?> Function(String, Map<Object?, Object?>) onCommand;
  final void Function(Offset, Offset) onVirtualMove;
  final void Function(MouseButtons, Offset?) onVirtualClick;
  final void Function(bool, Offset?) onVirtualDrag;
  final void Function(int, Offset) onVirtualScroll;
  final ValueChanged<bool>? onPointerVisibility;
  final void Function(int?)? onVideoTexture;

  static const _channel = MethodChannel('awesun/session');
  static AwesunNativeBridge? _owner;
  bool _acceptEvents = false;

  Future<bool> setActive(bool active, {bool touchMode = false}) async {
    if (active) {
      _owner = this;
      _channel.setMethodCallHandler(_handleMethodCall);
    }
    if (_owner != this) return false;
    _acceptEvents = active;
    final shown = await _setNativeVisibility(active, touchMode: touchMode);
    return active && shown;
  }

  Future<bool> _setNativeVisibility(bool active,
      {bool touchMode = false}) async {
    try {
      return await _channel.invokeMethod<bool>('setActive', {
            'active': active,
            'touchMode': touchMode,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Native session controls failed: ${error.code}');
      return false;
    }
  }

  void dispose() {
    if (_owner != this) return;
    _acceptEvents = false;
    _owner = null;
    _channel.setMethodCallHandler(null);
    unawaited(_setNativeVisibility(false));
  }

  Future<String> savePhoto(Uint8List png) async =>
      await _channel.invokeMethod<String>('savePhoto', png) ?? 'saveFailed';

  Future<String> saveTexturePhoto() async =>
      await _channel.invokeMethod<String>('saveTexturePhoto') ?? 'saveFailed';

  Future<bool> configureVideoTexture(bool enabled) async =>
      await _channel
          .invokeMethod<bool>('setVideoTexture', {'enabled': enabled}) ??
      false;

  Future<void> setMouseViewport(Rect area) =>
      _channel.invokeMethod<void>('setMouseViewport', {
        'x': area.left,
        'y': area.top,
        'width': area.width,
        'height': area.height,
      });

  Future<void> updatePerformance(Map<String, Object?> status) =>
      _channel.invokeMethod<void>('setPerformanceStatus', status);

  Future<void> updatePresentation({
    required bool obscured,
    required double keyboardInset,
  }) async {
    if (_owner != this || !_acceptEvents) return;
    try {
      await _channel.invokeMethod<void>('setPresentation', {
        'obscured': obscured,
        'keyboardInset': keyboardInset,
      });
    } on PlatformException catch (error) {
      debugPrint('Native session presentation failed: ${error.code}');
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (_owner != this || !_acceptEvents) return null;
    final arguments = call.arguments;
    final args = arguments is Map ? arguments : const <Object?, Object?>{};
    if (call.method == 'close') {
      onClose();
      return null;
    }
    if (call.method == 'command' && args['id'] is String) {
      return onCommand(args['id'] as String, args);
    }
    if (call.method == 'nativeVideoTexture') {
      final id = args['id'];
      onVideoTexture?.call(id is int ? id : null);
      return null;
    }
    if (call.method == 'virtualPointerVisible') {
      onPointerVisibility?.call(args['visible'] == true);
      return null;
    }
    if (call.method == 'virtualDrag' && args['down'] == false) {
      onVirtualDrag(false, null);
      return null;
    }
    if (!canSendInput()) return null;

    final point = _point(args);
    switch (call.method) {
      case 'virtualMove':
        if (point != null) {
          final delta = _point(args, xKey: 'panX', yKey: 'panY') ?? Offset.zero;
          onVirtualMove(point, delta);
        }
      case 'virtualDrag':
        if (args['down'] == true && point != null) onVirtualDrag(true, point);
      case 'virtualClick':
        final button = switch (args['button']) {
          'left' => MouseButtons.left,
          'right' => MouseButtons.right,
          'middle' => MouseButtons.wheel,
          _ => null,
        };
        if (button != null) onVirtualClick(button, point);
      case 'tapAt':
        final point =
            canvasPoint(Offset(_toDouble(args['x']), _toDouble(args['y'])));
        final remote =
            point == null ? null : cursorModel.getRemotePosInRect(point);
        if (remote != null) {
          await inputModel.moveMouse(remote.dx, remote.dy);
        }
        if (_acceptEvents && _owner == this && canSendInput()) {
          await inputModel.tap(args['button'] == 'right'
              ? MouseButtons.right
              : MouseButtons.left);
        }
      case 'tapMiddle':
        await inputModel.tap(MouseButtons.wheel);
      case 'moveRelative':
        await inputModel.sendMobileRelativeMouseMove(
            _toDouble(args['dx']), _toDouble(args['dy']));
      case 'scroll':
        final steps = _toDouble(args['dy']).round();
        if (point != null) {
          onVirtualScroll(steps, point);
        } else {
          await inputModel.scroll(steps);
        }
      case 'key':
        final name = args['name'];
        if (name is String && name.isNotEmpty) {
          if (inputModel.keyboardInputAllowed) {
            inputModel.inputKey(name, down: args['down'] == true, press: false);
          }
        }
    }
    return null;
  }

  Offset? _point(Map<dynamic, dynamic> args,
      {String xKey = 'x', String yKey = 'y'}) {
    final x = args[xKey];
    final y = args[yKey];
    if (x is num && x.isFinite && y is num && y.isFinite) {
      return Offset(x.toDouble(), y.toDouble());
    }
    return null;
  }

  double _toDouble(dynamic value) => value is num ? value.toDouble() : 0;
}
