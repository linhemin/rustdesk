import 'package:flutter_hbb/mobile/server_config_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuration QR formats return the same draft payload', () {
    const config = '{"host":"id.example","relay":"relay.example"}';
    expect(
        serverConfigFromQr('config=$config', uriPrefix: 'rustdesk://'), config);
    expect(
        serverConfigFromQr('rustdesk://config/${Uri.encodeComponent(config)}',
            uriPrefix: 'rustdesk://'),
        config);
    expect(
        serverConfigFromQr('custom://config/${Uri.encodeComponent(config)}',
            uriPrefix: 'custom://'),
        config);
  });

  test('other links are not treated as configuration imports', () {
    for (final code in [
      'rustdesk://password/example',
      'rustdesk://connect/example',
      'other://config/example',
      'rustdesk://config',
      'not a configuration',
    ]) {
      expect(serverConfigFromQr(code, uriPrefix: 'rustdesk://'), isNull);
    }
  });
}
