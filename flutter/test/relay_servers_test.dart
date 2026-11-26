import 'dart:convert';

import 'package:flutter_hbb/common.dart' show ServerConfig;
import 'package:flutter_hbb/common/relay_servers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit empty relay list overrides the legacy relay', () {
    expect(relayServerText('', 'old.example'), 'old.example');
    expect(relayServerText('[]', 'old.example'), isEmpty);
    expect(relayServerText('{bad json', 'old.example'), isEmpty);
    expect(relayServerText('["a.example","b.example"]', ''),
        'a.example\nb.example');
  });

  test(
      'server sharing preserves multiple relays and independent ID-only imports',
      () {
    final saved = ServerConfig.fromOptions({
      'custom-rendezvous-server': 'id.example',
      'relay-server': 'legacy.example',
      'relay-servers': '["a.example","wss://west.example/ws/relay"]',
    });
    final exported = saved.encode();
    final share = jsonDecode(
        utf8.decode(base64Url.decode(exported.split('').reversed.join())));
    expect(share['relay'], 'a.example');
    expect(ServerConfig.decode(exported).relayServer,
        'a.example\nwss://west.example/ws/relay');
    expect(ServerConfig.decode('{"host":"new.id"}').hasRelayServers, false);
    expect(
        ServerConfig.decode('{"host":"id","relays":[]}').hasRelayServers, true);
  });

  test('accepts distinct native and websocket endpoints in input order', () {
    expect(
        parseRelayServers(
            ' Example.com  \nexample.COM:21117\n[::1]:21117\n::1\nwss://s.example/ws/relay\nwss://S.EXAMPLE:443/ws/relay\n10.0.0.2:49000'),
        [
          'Example.com',
          '[::1]:21117',
          'wss://s.example/ws/relay',
          '10.0.0.2:49000'
        ]);
    expect(parseRelayServers(' \n\n'), isEmpty);
  });

  test('preserves editable policy when a draft has an invalid address', () {
    for (final bad in [
      'bad name',
      's.example:0',
      's.example:65536',
      'http://node/path',
      's.example/path',
      '[bad::addr]',
      'wss://user@s.example/ws/relay',
      'wss://s.example/ws/relay?token=x',
      'wss://s.example/ws/relay#fragment',
      List.filled(256, 'a').join(),
      List.generate(9, (i) => 'r$i.example').join('\n')
    ]) {
      expect(() => parseRelayServers(bad), throwsFormatException, reason: bad);
    }
  });
}
