import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/account_server.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  String hidePasswordLogin = '';
  String? authenticatedProvider;
  Future<String?>? loginOptionsResponse;
  final localOptions = <String, String>{};
  final serverOptions = {'custom-rendezvous-server': 'id.example.com'};
  final requests = <Uri>[];
  ({Completer<void> started, Completer<String> response})? pendingPeers;

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name.replaceAll('{', '').replaceAll('}', '');

  @override
  String mainGetBuildinOption({required String key, dynamic hint}) =>
      key == kOptionHideAccountPasswordLogin ? hidePasswordLogin : '';

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      key == kOptionEnableFlutterHttpOnRust ? 'Y' : localOptions[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
      {required String key, required String value, dynamic hint}) async {
    localOptions[key] = value;
  }

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      serverOptions[key] ?? '';

  @override
  bool mainIsOptionFixed({required String key, dynamic hint}) => false;

  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    serverOptions[key] = value;
  }

  @override
  Future<void> mainClearAb({dynamic hint}) async {}

  @override
  Future<void> mainClearGroup({dynamic hint}) async {}

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) => '';

  @override
  bool isDisableAb({dynamic hint}) => false;

  @override
  bool isDisableAccount({dynamic hint}) => false;

  @override
  bool isDisableGroupPanel({dynamic hint}) => false;

  @override
  Future<String> mainGetApiServer({dynamic hint}) async =>
      'https://example.com';

  @override
  Future<void> mainHttpRequest(
      {required String url,
      required String method,
      String? body,
      required String header,
      dynamic hint}) async {
    requests.add(Uri.parse(url));
    if (Uri.parse(url).path == '/api/login') {
      final request = jsonDecode(body!);
      expect(request['id'], '123456789');
      expect(request['uuid'], 'test-device-uuid');
    }
  }

  @override
  Future<String?> mainGetHttpStatus({required String url, dynamic hint}) async {
    final uri = Uri.parse(url);
    final Object body;
    switch (uri.path) {
      case '/api/login-options':
        if (loginOptionsResponse != null) return await loginOptionsResponse;
        body = ['oidc/azure'];
      case '/api/login':
        body = {
          'type': 'access_token',
          'access_token': 'test-token',
          'user': {'name': 'alice', 'display_name': 'Alice'},
        };
      case '/api/peers':
        final pending = pendingPeers;
        if (pending != null) {
          pendingPeers = null;
          pending.started.complete();
          return await pending.response.future;
        }
        final firstPage = uri.queryParameters['current'] == '1';
        body = {
          'total': 101,
          'data': firstPage
              ? [
                  {'id': '111111111', 'user_name': 'alice'},
                  {'id': '222222222', 'user_name': 'bob', 'info': {'username': 'alice'}},
                  {'id': '333333333'},
                ]
              : [
                  {'id': '444444444', 'user_name': 'alice'},
                ],
        };
      default:
        throw StateError('Unexpected account request: ${uri.path}');
    }
    return jsonEncode({'body': jsonEncode(body), 'headers': {}, 'status_code': 200});
  }

  @override
  Future<void> mainAccountAuth(
      {required String op, required bool rememberMe, dynamic hint}) async {
    authenticatedProvider = op;
  }

  @override
  Future<void> mainAccountAuthCancel({dynamic hint}) async {}

  @override
  Future<String> mainAccountAuthResult({dynamic hint}) async => '';

  @override
  String mainGetLoginDeviceInfo({dynamic hint}) => '{}';
}

void main() {
  final binding = _Binding();

  setUpAll(() async {
    isTest = true;
    platformFFI.setBindingForTesting(binding);
    await initGlobalFFI();
  });

  Future<void> openLogin(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: globalKey,
      home: const Scaffold(),
    ));
    loginDialog();
    addTearDown(gFFI.dialogManager.dismissAll);
    await tester.pumpAndSettle();
  }

  for (final option in ['', 'N', 'Y']) {
    testWidgets('account password visibility with option "$option"',
        (tester) async {
      binding.hidePasswordLogin = option;
      binding.authenticatedProvider = null;
      await openLogin(tester);
      final hidden = option == 'Y';
      expect(find.byType(TextField), hidden ? findsNothing : findsNWidgets(2));
      expect(find.widgetWithText(ElevatedButton, 'Login'),
          hidden ? findsNothing : findsOneWidget);
      expect(find.text('or'), hidden ? findsNothing : findsOneWidget);
      expect(find.text('Continue with Microsoft'), findsOneWidget);
      final dialog =
          tester.widget<CustomAlertDialog>(find.byType(CustomAlertDialog));
      expect(dialog.onSubmit, hidden ? isNull : isNotNull);
      await tester.tap(find.text('Continue with Microsoft'));
      await tester.pump();
      expect(binding.authenticatedProvider, 'azure');
      gFFI.dialogManager.dismissAll();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('OIDC-only login shows loading before an empty provider response',
      (tester) async {
    binding.hidePasswordLogin = 'Y';
    final response = Completer<String?>();
    binding.loginOptionsResponse = response.future;
    addTearDown(() async {
      binding.loginOptionsResponse = null;
      gFFI.dialogManager.dismissAll();
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: globalKey,
      home: const Scaffold(),
    ));
    loginDialog();
    final unavailable = find.text('username-login-disabled-oidc-unavailable');

    // Render the first frame before the zero-delay fetch timer runs.
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(unavailable, findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(unavailable, findsNothing);

    response.complete(
        jsonEncode({'body': '[]', 'headers': {}, 'status_code': 200}));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(unavailable, findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  Future<void> signIn() async {
    final user = gFFI.userModel;
    final attempt = await user.beginLogin();
    final response = await user.login(
      LoginRequest(username: 'alice', id: '123456789', uuid: 'test-device-uuid'),
      attempt,
    );
    await user.completeLogin(response, attempt);
  }

  test('login selects owned devices and filters every page by account', () async {
    final user = gFFI.userModel;
    binding.requests.clear();
    final devices = user.ownedDevices.peers;
    addTearDown(() => user.reset(resetOther: true));
    await signIn();

    expect(gFFI.peerTabModel.currentTab, PeerTabIndex.owned.index);
    expect(binding.localOptions[accountServerOption],
        encodeAccountServer(await readAccountServer()));
    gFFI.peerTabModel.setCurrentTab(PeerTabIndex.fav.index);
    await user.validateStoredAccount();
    expect(gFFI.peerTabModel.currentTab, PeerTabIndex.owned.index);
    await user.refreshOwnedDevices();
    expect(devices.peers.map((peer) => peer.id), ['111111111', '444444444']);
    expect(binding.requests.where((uri) => uri.path == '/api/peers').length, 2);
  });

  test('changing ID server invalidates an old login and its token on the same API', () async {
    final user = gFFI.userModel;
    addTearDown(() async {
      binding.serverOptions['custom-rendezvous-server'] = 'id.example.com';
      await user.reset(resetOther: true);
    });
    await signIn();
    final pending = await user.beginLogin();
    final stale = LoginResponse(type: HttpType.kAuthResTypeToken,
        access_token: 'test-token', user: UserPayload.fromJson({'name': 'alice'}));
    final staleHeaders = getHttpHeaders();
    expect(
      await setServerConfig(null, null, ServerConfig(idServer: 'other.example.com')
        ..hasRelayServers = false),
      isTrue,
    );

    final requestCount = binding.requests.length;
    await expectLater(user.completeLogin(stale, pending), throwsA(isA<RequestException>()));
    await expectLater(
      http.get(Uri.parse('https://example.com/api/peers'), headers: staleHeaders),
      throwsA(isA<RequestException>()),
    );
    expect(binding.requests, hasLength(requestCount));
    expect(user.isLogin, isFalse);
    expect(gFFI.peerTabModel.currentTab, PeerTabIndex.recent.index);
    expect(binding.localOptions['access_token'], isEmpty);
  });

  test('a late device response stays with its original ID server', () async {
    final user = gFFI.userModel;
    final started = Completer<void>();
    final response = Completer<String>();
    addTearDown(() async {
      binding.pendingPeers = null;
      if (!response.isCompleted) response.complete('{}');
      binding.serverOptions['custom-rendezvous-server'] = 'id.example.com';
      await user.reset(resetOther: true);
    });
    await signIn();
    binding.requests.clear();
    binding.pendingPeers = (started: started, response: response);
    final uri = Uri.parse('https://example.com/api/peers?current=1');
    final stale = expectLater(http.get(uri, headers: getHttpHeaders()),
        throwsA(isA<RequestException>()));
    await started.future;

    await user.changeAccountServer(() async {
      binding.serverOptions['custom-rendezvous-server'] = 'other.example.com';
    });
    await signIn();
    final fresh = http.get(uri, headers: getHttpHeaders());
    await Future<void>.delayed(Duration.zero);
    expect(binding.requests.where((request) => request == uri), hasLength(1));
    response.complete(jsonEncode({
      'body': '{"data":[],"total":0}', 'headers': {}, 'status_code': 200,
    }));

    await stale;
    expect(jsonDecode((await fresh).body)['total'], 101);
  });
}
