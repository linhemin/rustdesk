import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:flutter_hbb/desktop/widgets/session_quality_monitor.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart' hide isMacOS, isWindows;
import 'package:uuid/uuid.dart';

final _sessionId = UuidValue('00000000-0000-0000-0000-000000000000');

class _FakeFFI implements FFI {
  @override
  UuidValue get sessionId => _sessionId;

  @override
  late final FfiModel ffiModel = FfiModel(WeakReference(this));

  @override
  late final qualityMonitorModel = QualityMonitorModel(WeakReference(this));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Options extends Fake implements RustdeskImpl {
  _Options({this.labels = const {}});
  final Map<String, String> labels;
  bool show = true;

  @override
  Future<bool?> sessionGetToggleOption(
      {required UuidValue sessionId, required String arg, dynamic hint}) async {
    expect(arg, 'show-quality-monitor');
    return show;
  }

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      labels[name] ?? name;
}

void main() {
  testWidgets('compact quality monitor keeps the complete live transport visible',
      (tester) async {
    platformFFI.setBindingForTesting(_Options(labels: {
      'Direct Connection': '直接连接',
      'Relay Connection': '中继连接',
    }));
    final ffi = _FakeFFI();
    await ffi.qualityMonitorModel.checkShowQualityMonitor(_sessionId);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: SizedBox(width: 190, child: QualityMonitor(ffi.qualityMonitorModel)),
          ),
        ),
      ),
    ));
    for (final (direct, raw, label) in [
      (false, 'QUIC', 'QUIC / UDP'),
      (true, 'UDP', 'KCP / UDP'),
      (true, 'TCP', 'TCP'),
      (false, 'WebRTC/IPv6', 'WebRTC/IPv6 / TURN'),
      (false, 'WebSocket', 'WebSocket'),
    ]) {
      ffi.ffiModel.setConnectionType('sample', true, direct, raw);
      await tester.pump();
      final type = find.text(direct ? '直接连接' : '中继连接');
      expect(type, findsOneWidget);
      final protocol = find.text(label);
      expect(protocol, findsOneWidget);
      final panel = tester.getRect(find.byType(QualityMonitor));
      final value = tester.getRect(protocol);
      expect(panel.contains(value.center), isTrue);
      expect(value.right, lessThanOrEqualTo(panel.right));
      expect(tester.renderObject<RenderParagraph>(protocol).didExceedMaxLines, isFalse);
      expect(getConnectionText(true, direct, raw), endsWith('($label)'));
    }
    ffi.ffiModel.clear();
    await tester.pump();
    expect(find.text('WebSocket'), findsNothing);
  });
  testWidgets('quality panel opens a per-port report for the same round', (tester) async {
    platformFFI.setBindingForTesting(_Options());
    final model = _FakeFFI().qualityMonitorModel;
    await tester.pumpWidget(MaterialApp(home: Center(child: DesktopQualityMonitor(model))));
    await model.checkShowQualityMonitor(_sessionId);
    model.addUdpReport('UDP #0123456789ab');
    model.addUdpReport('UDP #0123456789ab  RX 3  ACK TX 2\n'
        'local port | RX | valid RX | TX | ACK TX | TX err\n51023 | 3 | 2 | 9 | 2 | 0'
        '\n\nlocal port → destination | TX | TX err\n51023 → 192.0.2.4:38000 | 9 | 0');
    model.addUdpReport('local UDP #0123456789ab  RX 0  ACK TX 0\n'
        'local port | RX | valid RX | TX | ACK TX | TX err\n38000 | 0 | 0 | 4 | 0 | 0'
        '\n\nlocal port → destination | TX | TX err\n38000 → 198.51.100.3:51023 | 4 | 0');
    await tester.pump();
    expect(model.udpReports.length, 1);
    await tester.tap(find.text('UDP #0123456789ab  RX 3  ACK TX 2'));
    await tester.pumpAndSettle();
    expect(find.text('51023'), findsOneWidget);
    expect(find.text('ACK TX'), findsOneWidget);
    for (final device in ['Local', 'Remote']) {
      await tester.tap(find.textContaining('$device · IP:port'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('38000 → 198.51.100.3:51023'), findsOneWidget);
    expect(find.textContaining('51023 → 192.0.2.4:38000'), findsOneWidget);
  });

  testWidgets('dragging the desktop monitor keeps transport details on screen',
      (tester) async {
    platformFFI.setBindingForTesting(_Options());
    final ffi = _FakeFFI();
    final model = ffi.qualityMonitorModel;
    await model.checkShowQualityMonitor(_sessionId);
    ffi.ffiModel.setConnectionType('sample', true, true, 'UDP');
    model.addUdpReport('UDP #0123456789ab  RX 3  ACK TX 2');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DraggableDesktopQualityMonitor(model),
      ),
    ));
    await tester.drag(find.text('Speed'), const Offset(0, 600));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(Scaffold));
    final panel = tester.getRect(find.byType(DesktopQualityMonitor));
    final transport = tester.getRect(find.text('KCP / UDP'));
    expect(panel.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(transport.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop quality panel follows the session toggle and live samples',
      (tester) async {
    final options = _Options();
    platformFFI.setBindingForTesting(options);
    final ffi = _FakeFFI();
    ffi.ffiModel.pi.currentDisplay = 0;
    final model = ffi.qualityMonitorModel;
    await tester.pumpWidget(
        MaterialApp(home: Center(child: DesktopQualityMonitor(model))));
    expect(find.text('Speed'), findsNothing);
    await model.checkShowQualityMonitor(_sessionId);
    await tester.pump();
    expect(find.text('—'), findsNWidgets(6));
    model.updateQualityStatus({
      'speed': '1.5 MB/s',
      'fps': '{"0":60}',
      'delay': '17',
      'target_bitrate': '9500',
      'codec_format': 'AV1',
      'chroma': '4:4:4',
    });
    await tester.pump();
    for (final value in [
      '1.5 MB/s',
      '60',
      '17 ms',
      '9.5 Mb/s',
      'AV1',
      '4:4:4'
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    model.updateQualityStatus({'fps': '{"0":0}', 'target_bitrate': '720'});
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('17 ms'), findsOneWidget);
    expect(find.text('720 kb/s'), findsOneWidget);
    if (isWindows || isMacOS) {
      ffi.ffiModel.setConnectionType('sample', true, false, 'Relay');
      await tester.pump();
      expect(find.text('Relay Connection'), findsOneWidget);
      expect(find.text('TCP'), findsOneWidget);
      ffi.ffiModel.setConnectionType('sample', true, false, 'WebRTC/IPv6');
      await tester.pump();
      expect(find.text('WebRTC/IPv6 / TURN'), findsOneWidget);
      ffi.ffiModel.setConnectionType('sample', true, true, 'WebRTC');
      await tester.pump();
      expect(find.text('Direct Connection'), findsOneWidget);
      expect(find.text('WebRTC'), findsOneWidget);
      expect(find.text('Relay Connection'), findsNothing);
      ffi.ffiModel.clear();
      await tester.pump();
      expect(find.text('Direct Connection'), findsNothing);
    }
    options.show = false;
    await model.checkShowQualityMonitor(_sessionId);
    await tester.pump();
    expect(find.text('Speed'), findsNothing);
  });
}
