import 'dart:io';

import 'package:flutter_hbb/mobile/ios_p2p_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
