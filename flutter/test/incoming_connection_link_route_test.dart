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
    expect(
      urlLinkToCmdArgs(Uri.parse(incomingConnectionLink(
          uriPrefix: 'customdesk://',
          id: 'MyDesk_1',
          server: 'hbbs.example.invalid:21116',
          key: 'a+public/key='))),
      ['--connect', 'MyDesk_1@hbbs.example.invalid:21116?key=a+public/key='],
    );
  });
}
