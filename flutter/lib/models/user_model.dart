import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/hbbs/account_server.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'owned_devices_model.dart';
import 'platform_model.dart';

bool refreshingUser = false;

class UserModel {
  final ownedDevices = OwnedDevicesModel();
  int _accountGeneration = 0;
  bool _changingServer = false;
  Future<void> _accountWrites = Future.value();
  final RxString userName = ''.obs;
  final RxString displayName = ''.obs;
  final RxString avatar = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  // True when networkError carries a server-reported error rather than a
  // connectivity failure; netWorkErrorWidget hides the network tip then.
  final RxBool networkErrorFromServer = false.obs;
  bool get isLogin => userName.isNotEmpty;
  String get displayNameOrUserName =>
      displayName.value.trim().isEmpty ? userName.value : displayName.value;
  String get accountLabelWithHandle {
    final username = userName.value.trim();
    if (username.isEmpty) {
      return '';
    }
    final preferred = displayName.value.trim();
    if (preferred.isEmpty || preferred == username) {
      return username;
    }
    return '$preferred (@$username)';
  }

  WeakReference<FFI> parent;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  Future<AccountLoginAttempt> beginLogin() async => (
        generation: _accountGeneration,
        server: await readAccountServer(),
      );

  Future<void> requireCurrentServer(AccountLoginAttempt attempt) async {
    final current = await readAccountServer();
    if (_changingServer ||
        attempt.generation != _accountGeneration ||
        attempt.server != current ||
        current.apiServer.isEmpty) {
      throw RequestException(0, 'Invalid server configuration');
    }
  }

  Future<void> validateStoredAccount() async {
    if (isWeb) return;
    if (bind.mainGetLocalOption(key: 'access_token').isEmpty) {
      parent.target?.peerTabModel.showGuestDevices();
      return;
    }
    if (!isStoredAccountServer(await readAccountServer())) {
      await reset(resetOther: true);
    } else if (!bind.isDisableAccount()) {
      parent.target?.peerTabModel.showOwnedDevices();
    }
  }

  Future<void> changeAccountServer(Future<void> Function() save) async {
    if (_changingServer) throw RequestException(0, 'Waiting');
    _changingServer = true;
    try {
      await bind.mainAccountAuthCancel();
      await reset(resetOther: true);
      await save();
    } finally {
      _changingServer = false;
    }
  }

  Future<void> _writeAccount(Future<void> Function() write) {
    final operation = _accountWrites.then((_) => write());
    _accountWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> refreshOwnedDevices({bool force = false}) async {
    if (!isLogin || isWeb) return;
    final token = bind.mainGetLocalOption(key: 'access_token');
    final generation = _accountGeneration;
    final server = await readAccountServer();
    if (_changingServer || generation != _accountGeneration) return;
    if (token.isEmpty) return;
    if (!isStoredAccountServer(server)) {
      await reset(resetOther: true);
      return;
    }
    try {
      await ownedDevices.pull(
        apiServer: server.apiServer,
        token: token,
        username: userName.value,
        force: force,
      );
    } on RequestException {
      if (generation == _accountGeneration) await reset(resetOther: true);
    }
  }

  void refreshCurrentUser() async {
    if (bind.isDisableAccount() || _changingServer || refreshingUser) return;
    final generation = _accountGeneration;
    networkError.value = '';
    networkErrorFromServer.value = false;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await updateOtherModels();
      return;
    }
    final server = await readAccountServer();
    if (generation != _accountGeneration || refreshingUser) return;
    if (!isStoredAccountServer(server)) {
      await reset(resetOther: true);
      return;
    }
    final wasLoggedIn = isLogin;
    _updateLocalUserInfo();
    if (!wasLoggedIn && isLogin) parent.target?.peerTabModel.showOwnedDevices();
    final url = server.apiServer;
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (generation != _accountGeneration || refreshingUser) return;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        if (generation == _accountGeneration) networkError.value = e.toString();
        rethrow;
      }
      if (generation != _accountGeneration) return;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        await reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(decode_http_response(response));
      final error = data['error'];
      if (error != null) {
        // The only failure known to come from the server itself, so the
        // check-your-network tip does not apply. Flag before the message is
        // set in the catch below so rebuilds read a consistent pair.
        networkErrorFromServer.value = true;
        throw error;
      }

      final user = UserPayload.fromJson(data);
      await _writeAccount(() async {
        if (generation != _accountGeneration) return;
        await _parseAndUpdateUser(user, generation);
        if (!wasLoggedIn && isLogin) parent.target?.peerTabModel.showOwnedDevices();
      });
    } catch (e) {
      if (generation != _accountGeneration) return;
      debugPrint('Failed to refreshCurrentUser: $e');
      // Surface failures in the address book / group tabs, which offer a
      // retry. Anything not flagged above -- transport errors, non-JSON or
      // unexpected-schema bodies (e.g. a filter's block page) -- keeps the
      // check-your-network tip.
      if (networkError.value.isEmpty) {
        networkError.value = e.toString();
      }
    } finally {
      refreshingUser = false;
      if (generation == _accountGeneration) await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = (userInfo['name'] ?? '').toString();
      displayName.value = (userInfo['display_name'] ?? '').toString();
      avatar.value = (userInfo['avatar'] ?? '').toString();
    }
  }

  Future<void> reset({bool resetOther = false}) async {
    _accountGeneration++;
    userName.value = '';
    displayName.value = '';
    avatar.value = '';
    isAdmin.value = false;
    ownedDevices.reset();
    parent.target?.peerTabModel.showGuestDevices();
    await _writeAccount(() async {
      await bind.mainSetLocalOption(key: 'access_token', value: '');
      if (!isWeb) await bind.mainSetLocalOption(key: accountServerOption, value: '');
      await bind.mainSetLocalOption(key: 'user_info', value: '');
      if (resetOther) {
        await parent.target?.abModel.reset();
        await parent.target?.groupModel.reset();
      }
    });
  }

  Future<void> _parseAndUpdateUser(UserPayload user, int generation) async {
    await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (generation != _accountGeneration) return;
    _publishUser(user);
  }

  void _publishUser(UserPayload user) {
    userName.value = user.name;
    displayName.value = user.displayName;
    avatar.value = user.avatar;
    isAdmin.value = user.isAdmin;
    if (isWeb) {
      // ugly here, tmp solution
      bind.mainSetLocalOption(key: 'verifier', value: user.verifier ?? '');
    }
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await Future.wait([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull(),
      gFFI.userModel.refreshOwnedDevices(force: true),
    ]);
  }

  Future<void> logOut({String? apiServer}) async {
    final generation = _accountGeneration;
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      if (generation == _accountGeneration) await reset(resetOther: true);
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(
      LoginRequest loginRequest, AccountLoginAttempt attempt) async {
    await requireCurrentServer(attempt);
    final url = attempt.server.apiServer;
    final resp = await http.post(Uri.parse('$url/api/login'),
        body: jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(resp));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    await requireCurrentServer(attempt);
    return LoginResponse.fromJson(body);
  }

  Future<void> completeLogin(
      LoginResponse response, AccountLoginAttempt attempt) {
    return _writeAccount(() async {
      await requireCurrentServer(attempt);
      final token = response.access_token;
      final user = response.user;
      if (response.type != HttpType.kAuthResTypeToken ||
          token == null ||
          token.isEmpty) {
        throw RequestException(0, 'Invalid response');
      }
      ownedDevices.reset();
      if (bind.mainGetLocalOption(key: 'access_token').isNotEmpty) {
        await bind.mainSetLocalOption(key: 'access_token', value: '');
      }
      if (!isWeb) {
        await bind.mainSetLocalOption(
            key: accountServerOption,
            value: encodeAccountServer(attempt.server));
      }
      await bind.mainSetLocalOption(
          key: 'user_info', value: user == null ? '' : jsonEncode(user));
      await bind.mainSetLocalOption(key: 'access_token', value: token);
      if (attempt.generation != _accountGeneration) {
        throw RequestException(0, 'Invalid server configuration');
      }
      parent.target?.peerTabModel.showOwnedDevices();
      if (user != null) {
        _publishUser(user);
      } else {
        refreshCurrentUser();
      }
    });
  }

  /// Throws on network failures, non-success responses, and invalid response
  /// data. Returns an empty list when no API server is configured or a
  /// successful response contains no third-party login options.
  static Future<List<dynamic>> queryOidcLoginOptions({String? apiServer}) async {
    final url = apiServer ?? await bind.mainGetApiServer();
    if (url.trim().isEmpty) return [];
    final resp = await http.get(Uri.parse('$url/api/login-options'));
    const successStatusCodeStart = 200;
    const successStatusCodeEnd = 300;
    if (resp.statusCode < successStatusCodeStart ||
        resp.statusCode >= successStatusCodeEnd) {
      throw RequestException(
          resp.statusCode, resp.reasonPhrase ?? 'Request failed');
    }
    final List<String> ops = [];
    for (final item in jsonDecode(resp.body)) {
      ops.add(item as String);
    }
    for (final item in ops) {
      if (item.startsWith('common-oidc/')) {
        return jsonDecode(item.substring('common-oidc/'.length));
      }
    }
    return ops
        .where((item) => item.startsWith('oidc/'))
        .map((item) => {'name': item.substring('oidc/'.length)})
        .toList();
  }
}
