import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/pages/remote_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// iOS uses the channel implementation; desktop widget tests register a desktop plugin.
// ignore: implementation_imports
import 'package:wakelock_plus_platform_interface/src/method_channel_wakelock_plus.dart';

class _Options extends Fake implements RustdeskImpl {
  var value = '';

  @override
  String mainGetLocalOption({required String key, dynamic hint}) {
    expect(key, kOptionKeepAwakeDuringOutgoingSessions);
    return value;
  }
}

// Decode ToggleMessage using the protocol registered by the iOS plugin.
class _IosWakelockCodec extends StandardMessageCodec {
  const _IosWakelockCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) => type == 129
      ? (readValue(buffer) as List).single as bool
      : super.readValueOfType(type, buffer);
}

void main() {
  testWidgets('iOS sessions hold the native idle timer only while requested',
      (tester) async {
    final options = _Options();
    isTest = true;
    platformFFI.setBindingForTesting(options);
    final previousPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = MethodChannelWakelockPlus();
    addTearDown(() => wakelockPlusPlatformInstance = previousPlatform);
    const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.WakelockPlusApi.toggle', _IosWakelockCodec());
    final toggles = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
        channel, (message) async {
      toggles.add((message as List).single as bool);
      return [null];
    });
    final first = UniqueKey();
    final second = UniqueKey();
    updateIosSessionWakelock(first, AppLifecycleState.resumed);
    updateIosSessionWakelock(first, AppLifecycleState.inactive);
    updateIosSessionWakelock(first, AppLifecycleState.paused);
    updateIosSessionWakelock(first, AppLifecycleState.resumed);
    updateIosSessionWakelock(second, AppLifecycleState.resumed);
    WakelockManager.disable(first);
    await tester.pump();
    expect(toggles, [true, false, true]);
    WakelockManager.disable(second);
    options.value = 'N';
    updateIosSessionWakelock(first, AppLifecycleState.resumed);
    await tester.pump();
    expect(toggles, [true, false, true, false]);
  });
}
