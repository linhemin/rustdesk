import 'package:flutter_hbb/desktop/incoming_connection_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'public invitation explicitly routes to the public server without a password',
      () {
    expect(incomingConnectionLink(uriPrefix: 'rustdesk://', id: 'MyDesk_1'),
        'rustdesk://MyDesk_1@public');
  });

  test('self-hosted invitation retains its server and public key', () {
    for (final server in [
      'hbbs.example.invalid:21116',
      '[2001:db8::1]:21116'
    ]) {
      final uri = Uri.parse(incomingConnectionLink(
        uriPrefix: 'customdesk://',
        id: 'MyDesk_1',
        server: server,
        key: 'a+public/key=',
      ));
      expect(uri.authority, 'MyDesk_1@$server');
      expect(uri.queryParameters, {'key': 'a+public/key='});
    }
  });
}
