import 'dart:io';

import 'package:flutter_hbb/mobile/image_ready_samples.dart';

import 'package:flutter_hbb/mobile/ios_p2p_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image-ready samples expire on idle and cannot cross a session boundary', () {
    final rows = ImageReadySamples();
    final start = DateTime.utc(2026, 11, 20);
    for (int i = 0; i <= 50; i++) {
      rows.add(start.add(Duration(milliseconds: i * 20)), 4400);
    }
    final end = start.add(const Duration(seconds: 1));
    expect(rows.format(start, end), ' imageReadyFps=50 rgbaToImageMeanMs=4');
    expect(rows.format(start, end.add(const Duration(seconds: 4))), '');
    expect(rows.format(end.add(const Duration(milliseconds: 1)), end), '');
    rows.reset();
    expect(rows.format(start, end), '');
  });
  test('copy includes only current, typed media samples', () {
    final now = DateTime.utc(2026, 1, 1);
    final start = now.subtract(const Duration(seconds: 20));
    expect(formatIosMediaSample(opened: start, now: now, videoAt: now,
      delayAt: now, fps: '58', codec: 'H265', chroma: '4:2:0', delay: '48',
      target: '7000', direct: true),
      'media path=direct codec=H265 chroma=4:2:0 displayFps=[58] rttMs=48 targetKbps=7000');
    expect(formatIosMediaSample(opened: start, now: now, videoAt: start,
      delayAt: now, fps: '60', codec: 'H265', delay: 'secret', direct: false, transport: 'QUIC'), 'media path=relay transport=QUIC');
  });
  late Directory documents;
  late File report;
  const header = 'RustDesk P2P diagnostics\nformat=udp-paths-v3';
  final opened = DateTime.parse('2026-11-20T02:00:00.123456Z');
  const current = '2026-11-20T02:00:00.123Z version=1.5.3 build=79\n'
      'result=in-progress\nsyncPunch=started localWakes=2\n';
  const older = '2026-11-20T01:59:59.000Z version=1.5.3 build=79\n'
      'result=cancelled\n';

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('rustdesk-p2p-');
    report = File('${documents.path}/RustDesk-P2P-diagnostics.txt');
  });
  tearDown(() => documents.delete(recursive: true));

  test('copies only this session, including a current in-progress attempt',
      () async {
    await report.writeAsString('$header\n\n$older\n$current');
    expect(
        await readIosP2pDiagnostics(documents, opened), '$header\n\n$current');
  });

  test('early taps and previous builds or sessions never copy stale data',
      () async {
    expect(await readIosP2pDiagnostics(documents, opened), isNull);
    for (final contents in [
      '$header\n',
      '$header\n\n$older',
      'RustDesk P2P diagnostics\nformat=udp-sync-v2\n\n$current',
      'RustDesk P2P diagnostics\n\n$current',
    ]) {
      await report.writeAsString(contents);
      expect(await readIosP2pDiagnostics(documents, opened), isNull);
    }
  });

  test('rejects oversized reports', () async {
    await report.writeAsBytes(List.filled(48 * 1024 + 1, 32));
    await expectLater(
        readIosP2pDiagnostics(documents, opened), throwsFormatException);
  });
}
