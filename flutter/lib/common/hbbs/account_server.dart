import 'dart:convert';

import '../../common.dart' show isWeb;
import '../../models/platform_model.dart';

const accountServerOption = 'account-server-scope';

typedef AccountServer = ({String idServer, String key, String apiServer});
typedef AccountLoginAttempt = ({AccountServer server, int generation});

Future<AccountServer> readAccountServer() async {
  final apiServer = await bind.mainGetApiServer();
  return (
    idServer: isWeb
        ? ''
        : bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim(),
    key: isWeb ? '' : bind.mainGetOptionSync(key: 'key').trim(),
    apiServer: apiServer.trim(),
  );
}

String encodeAccountServer(AccountServer server) =>
    jsonEncode([server.idServer, server.key, server.apiServer]);

bool isStoredAccountServer(AccountServer server) =>
    isWeb ||
    (server.apiServer.isNotEmpty &&
        bind.mainGetLocalOption(key: accountServerOption) ==
            encodeAccountServer(server));
