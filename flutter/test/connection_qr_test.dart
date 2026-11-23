import 'package:flutter_hbb/mobile/pages/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home QR preserves connection links and custom client prefixes', () {
    for (final prefix in ['rustdesk://', 'customdesk://']) {
      for (final target in [
        '123456789?password=secret&relay=true',
        'connect/123456789',
        'file-transfer/123456789',
        'connection/new/123456789',
      ]) {
        final code = '$prefix$target';
        expect(connectionQrUri(code, prefix).toString(), code);
      }
    }
  });

  test('home QR rejects provisioning commands before URI dispatch', () {
    for (final code in [
      'rustdesk://config/encoded',
      'rustdesk://password/new-password',
      'config=encoded',
      'https://example.com/123456789',
      'rustdesk://[invalid',
    ]) {
      expect(connectionQrUri(code, 'rustdesk://'), isNull);
    }
  });
}
