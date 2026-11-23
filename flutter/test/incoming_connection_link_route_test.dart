import 'package:flutter_hbb/common.dart' show urlLinkToCmdArgs;
import 'package:flutter_hbb/desktop/incoming_connection_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invitations dispatch case-sensitive IDs as connections on their server',
      () {
    for (final id in ['MyDesk_1', 'terminal', 'config', 'password']) {
      expect(
        urlLinkToCmdArgs(Uri.parse(
            incomingConnectionLink(uriPrefix: 'rustdesk://', id: id))),
        ['--connect', '$id@public'],
      );
    }
    for (final server in {
      'hbbs.example.invalid:21116': 'hbbs.example.invalid:21116',
      '[2001:db8::1]:21116': '[2001:db8::1]:21116',
      '2001:db8::1': '[2001:db8::1]',
    }.entries) {
      expect(
        urlLinkToCmdArgs(Uri.parse(incomingConnectionLink(
            uriPrefix: 'customdesk://',
            id: 'MyDesk_1',
            server: server.key,
            key: 'a+public/key='))),
        ['--connect', 'MyDesk_1@${server.value}?key=a+public/key='],
      );
    }
  });
}
