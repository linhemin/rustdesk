import 'package:flutter_hbb/desktop/incoming_connection_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public invitation opens a connection without sharing a password', () {
    expect(incomingConnectionLink(uriPrefix: 'rustdesk://', id: '123456789'),
        'rustdesk://123456789');
  });

  test('self-hosted invitation retains its server and public key', () {
    final uri = Uri.parse(incomingConnectionLink(
      uriPrefix: 'customdesk://',
      id: 'my_desk-1',
      server: 'hbbs.example.invalid:21116',
      key: 'a+public/key=',
    ));
    expect(uri.authority, 'my_desk-1@hbbs.example.invalid:21116');
    expect(uri.queryParameters, {'key': 'a+public/key='});
  });
}
