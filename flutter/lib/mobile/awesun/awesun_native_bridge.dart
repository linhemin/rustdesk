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
    required this.onVirtualPosition,
    required this.onVirtualClick,
    required this.onVirtualDrag,
  });

  final InputModel inputModel;
  final CursorModel cursorModel;
  final Offset? Function(Offset) canvasPoint;
  final bool Function() canSendInput;
  final VoidCallback onClose;
  final Future<Object?> Function(String, Map<Object?, Object?>) onCommand;
  final void Function(Offset) onVirtualMove;
  final void Function(Offset) onVirtualPosition;
  final void Function(MouseButtons) onVirtualClick;
  final void Function(bool) onVirtualDrag;

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

  Future<bool> _setNativeVisibility(bool active, {bool touchMode = false}) async {
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
    if (call.method == 'virtualDrag' && args['down'] == false) {
      onVirtualDrag(false);
      return null;
    }
    if (!canSendInput()) return null;

    switch (call.method) {
      case 'virtualPosition':
        final point = canvasPoint(Offset(_toDouble(args['x']), _toDouble(args['y'])));
        if (point != null) onVirtualPosition(point);
      case 'virtualMove':
        onVirtualMove(Offset(_toDouble(args['dx']), _toDouble(args['dy'])));
      case 'virtualDrag':
        if (args['down'] == true) onVirtualDrag(true);
      case 'virtualClick':
        final button = switch (args['button']) {
          'right' => MouseButtons.right,
          'middle' => MouseButtons.wheel,
          _ => MouseButtons.left,
        };
        onVirtualClick(button);
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
        await inputModel.scroll(_toDouble(args['dy']).round());
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

  double _toDouble(dynamic value) => value is num ? value.toDouble() : 0;
}
