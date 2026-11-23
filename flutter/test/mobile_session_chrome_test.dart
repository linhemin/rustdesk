import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Also runs from the backend-free ui_preview package.
// ignore: avoid_relative_lib_imports
import '../lib/mobile/widgets/session_quality_monitor.dart';

void main() {
  testWidgets('mobile quality card moves and stays within the viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MobileSessionQualityMonitor(
          connection: '直接连接 · TCP',
          direct: true,
          metrics: [
            ('速度', '1.08 MB/s'),
            ('FPS', '60'),
            ('延迟', '9 ms'),
            ('码率', '8.2 Mb/s'),
            ('编解码', 'AV1'),
            ('色度采样', '4:2:0')
          ],
        ),
      ),
    ));
    final card = find.byType(BackdropFilter);
    final initial = tester.getRect(card);
    await tester.drag(find.text('直接连接 · TCP'), const Offset(80, 100));
    await tester.pump();
    expect(tester.getRect(card).left, greaterThan(initial.left));
    expect(tester.getRect(card).top, greaterThan(initial.top));
    final drag =
        await tester.startGesture(tester.getCenter(find.text('直接连接 · TCP')));
    await drag.moveBy(const Offset(30, 30));
    await tester.pump();
    final beforeBurst = tester.getRect(card);
    await drag.moveBy(const Offset(10, 5));
    await drag.moveBy(const Offset(10, 5));
    await drag.up();
    await tester.pump();
    expect(tester.getRect(card).left, closeTo(beforeBurst.left + 20, 0.1));
    expect(tester.getRect(card).top, closeTo(beforeBurst.top + 10, 0.1));
    await tester.drag(find.text('直接连接 · TCP'), const Offset(1000, 1000));
    await tester.pump();
    final viewport = tester.getRect(find.byType(Scaffold));
    expect(tester.getRect(card).right, lessThanOrEqualTo(viewport.right - 12));
    expect(
        tester.getRect(card).bottom, lessThanOrEqualTo(viewport.bottom - 12));
    await tester.drag(find.text('直接连接 · TCP'), const Offset(-40, -40));
    await tester.pump();
    expect(tester.getRect(card).right, lessThan(viewport.right - 12));
    expect(tester.getRect(card).bottom, lessThan(viewport.bottom - 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quality diagnostics remain tappable at larger text scale',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MobileSessionQualityMonitor(
            connection: '中继连接 · WebRTC/IPv6 / TURN',
            direct: false,
            metrics: const [
              ('延迟', '17 ms'),
              ('码率', '9.5 Mb/s'),
              ('色度采样', '4:4:4')
            ],
            diagnostics: TextButton(
                onPressed: () => opened = true,
                child: const Text('UDP report')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('UDP report'));
    await tester.pump();
    expect(opened, isTrue);
    expect(find.text('色度采样'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
