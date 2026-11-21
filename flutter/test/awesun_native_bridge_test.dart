import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/mobile/awesun/awesun_native_bridge.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cursor extends Fake implements CursorModel {
  final seen = <Offset>[];

  @override
  Offset? getRemotePosInRect(Offset offset) {
    seen.add(offset);
    return const Offset(120, 240);
  }
}

class _Input extends Fake implements InputModel {
  final events = <Object>[];

  @override
  Future<void> moveMouse(double x, double y) async {
    events.add(Offset(x, y));
  }

  @override
  Future<void> tap(MouseButtons button) async {
    events.add(button);
  }

  @override
  Future<void> sendMobileRelativeMouseMove(double dx, double dy) async {
    events.add(('relative', Offset(dx, dy)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('awesun/session');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> send(MethodCall call) async {
    final result = Completer<Object?>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(call),
      (reply) {
        result.complete(reply == null ? null : codec.decodeEnvelope(reply));
      },
    );
    return result.future;
  }

  test('native clicks use canvas-local coordinates and existing input',
      () async {
    final shown = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      shown.add((call.arguments as Map)['active'] as bool);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final cursor = _Cursor();
    final input = _Input();
    var allowed = true;
    final virtual = <Object>[];
    final commands = <String>[];
    final bridge = AwesunNativeBridge(
      inputModel: input,
      cursorModel: cursor,
      canvasPoint: (point) => point - const Offset(6, 18),
      canSendInput: () => allowed,
      onClose: () {},
      onCommand: (id, args) async {
        commands.add(id);
        return ['Copy P2P diagnostics', 'Refresh'];
      },
      onVirtualMove: (delta) => virtual.add(delta),
      onVirtualClick: (button, point) => virtual.add((button, point)),
      onVirtualDrag: (down, point) => virtual.add((down, point)),
      onVirtualScroll: (steps, point) => virtual.add((steps, point)),
      onPointerVisibility: (visible) => virtual.add(visible),
    );
    addTearDown(bridge.dispose);

    expect(await bridge.setActive(true), isTrue);
    const right = MethodCall('tapAt', {'x': 16, 'y': 38, 'button': 'right'});
    await send(right);
    await send(const MethodCall('moveRelative', {'dx': 2, 'dy': -3}));
    expect(cursor.seen, [const Offset(10, 20)]);
    expect(input.events, [
      const Offset(120, 240),
      MouseButtons.right,
      ('relative', const Offset(2, -3)),
    ]);

    const point = Offset(73, 91);
    await send(const MethodCall('virtualPointerVisible', {'visible': true}));
    await send(const MethodCall('virtualDrag', {'down': true, 'x': 73, 'y': 91}));
    await send(const MethodCall('virtualMove', {'x': 75, 'y': 93}));
    await send(const MethodCall('virtualDrag', {'down': false}));
    await send(const MethodCall('virtualClick', {'button': 'left', 'x': 73, 'y': 91}));
    await send(const MethodCall('virtualClick', {'button': 'right', 'x': 73, 'y': 91}));
    await send(const MethodCall('scroll', {'dy': -2, 'x': 73, 'y': 91}));
    await send(const MethodCall('virtualClick', {'button': 'invalid'}));
    allowed = false;
    await send(const MethodCall('virtualDrag', {'down': false}));
    await send(const MethodCall('virtualClick', {'button': 'middle'}));
    await send(right);
    expect(virtual, [
      true,
      (true, point),
      const Offset(75, 93),
      (false, null),
      (MouseButtons.left, point),
      (MouseButtons.right, point),
      (-2, point),
      (false, null),
    ]);
    expect(input.events, hasLength(3));
    expect(await send(const MethodCall('command', {'id': 'menu'})),
        ['Copy P2P diagnostics', 'Refresh']);
    expect(commands, ['menu']);
    expect(await bridge.setActive(false), isFalse);
    await send(right);
    expect(input.events, hasLength(3));
    expect(shown, [true, false]);
  });
}
