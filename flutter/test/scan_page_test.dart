import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #translate => call.namedArguments[#name],
        #mainGetCommonSync => '{"url":""}',
        #getLocalFlutterOption ||
        #mainGetLocalOption ||
        #mainGetBuildinOption =>
          '',
        #isDisableAb || #isDisableAccount || #isDisableGroupPanel => false,
        _ => super.noSuchMethod(call),
      };
}

void main() {
  testWidgets('leaving the scanner preserves the caller and allows reopening',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    isTest = true;
    platformFFI.setBindingForTesting(_Binding());
    await initGlobalFFI();
    final messenger = tester.binding.defaultBinaryMessenger;
    final created = <int>[];
    final disposed = <int>[];
    MethodChannel channel(int id) =>
        MethodChannel('net.touchcapture.qr.flutterqrplus/qrview_$id');
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = call.arguments['id'] as int;
        created.add(id);
        messenger.setMockMethodCallHandler(channel(id), (_) async => null);
      } else if (call.method == 'dispose') {
        disposed.add(call.arguments as int);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final id in created) {
        messenger.setMockMethodCallHandler(channel(id), null);
      }
    });
    Future<void> cameraEvent(int id, String method, Object arguments) =>
        messenger.handlePlatformMessage(
            channel(id).name,
            const StandardMethodCodec()
                .encodeMethodCall(MethodCall(method, arguments)),
            (_) {});

    await tester.pumpWidget(MaterialApp(
      navigatorKey: globalKey,
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(
                            title: const Text('Network'),
                            actions: [ScanButton()])))),
                child: const Text('Settings'),
              ))),
    ));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    for (var entry = 0; entry < 4; entry++) {
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR'), findsOneWidget);
      final id = created.last;
      if (entry == 0) {
        await tester.pageBack();
        await cameraEvent(id, 'onPermissionSet', false);
      } else if (entry == 1) {
        await tester.binding.handlePopRoute();
      } else if (entry == 2) {
        await tester.dragFrom(const Offset(2, 300), const Offset(700, 0));
      } else {
        const code = {
          'code': 'config={"host":"example.invalid"}',
          'type': 'QR_CODE'
        };
        await cameraEvent(id, 'onRecognizeQR', code);
        await cameraEvent(id, 'onRecognizeQR', code);
      }
      await tester.pumpAndSettle();
      expect(disposed, created);
      expect(find.text('Network'), findsOneWidget);
      if (entry == 3) {
        expect(find.text('example.invalid'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
