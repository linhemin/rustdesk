import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:http/http.dart' as http;
import '../common/hbbs/account_server.dart';
import '../common/hbbs/hbbs.dart' show RequestException;
import '../models/platform_model.dart';
import 'package:flutter_hbb/common.dart';
export 'package:http/http.dart' show Response;

enum HttpMethod { get, post, put, delete }

class HttpService {
  static final _pendingRustRequests = <String, Future<void>>{};

  Future<http.Response> sendRequest(
    Uri url,
    HttpMethod method, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    headers ??= {'Content-Type': 'application/json'};

    // Use Rust HTTP implementation for non-web platforms for consistency.
    var useFlutterHttp = (isWeb || kIsWeb);
    if (!useFlutterHttp) {
      final enableFlutterHttpOnRust =
          mainGetLocalBoolOptionSync(kOptionEnableFlutterHttpOnRust);
      // Use flutter http if:
      // Not `enableFlutterHttpOnRust` and no proxy is set
      useFlutterHttp =
          !(enableFlutterHttpOnRust || await bind.mainGetProxyStatus());
    }

    final authorization = headers['Authorization'];
    final accountServer = await _checkAccountRequest(url, authorization);
    Future<void> checkAccountServer() async {
      if (accountServer != null &&
          accountServer != await _checkAccountRequest(url, authorization)) {
        throw RequestException(0, 'Invalid server configuration');
      }
    }

    final http.Response response;
    if (useFlutterHttp) {
      response = await _pollFlutterHttp(url, method, headers: headers, body: body);
    } else {
      final key = url.toString();
      // The native response slot is keyed by URL, even across account changes.
      final previous = _pendingRustRequests[key];
      final finished = Completer<void>();
      _pendingRustRequests[key] = finished.future;
      try {
        if (previous != null) {
          await previous;
          await checkAccountServer();
        }
        await bind.mainHttpRequest(
            url: key, method: method.name, body: body, header: jsonEncode(headers));
        response = _parseHttpResponse(await _pollForResponse(key));
      } finally {
        finished.complete();
        if (_pendingRustRequests[key] == finished.future) {
          _pendingRustRequests.remove(key);
        }
      }
    }
    await checkAccountServer();
    return response;
  }

  Future<AccountServer?> _checkAccountRequest(
      Uri target, String? authorization) async {
    if (isWeb || authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final server = await readAccountServer();
    final token = bind.mainGetLocalOption(key: 'access_token');
    final base = Uri.tryParse(server.apiServer);
    if (!isStoredAccountServer(server) ||
        token.isEmpty ||
        authorization != 'Bearer $token' ||
        base == null ||
        base.scheme != target.scheme ||
        base.host != target.host ||
        base.port != target.port ||
        !target.path.startsWith('${base.path}/api/')) {
      throw RequestException(0, 'Invalid server configuration');
    }
    return server;
  }

  // Bounds only the pure-Dart branch below, which the OS would otherwise
  // let hang forever (e.g. a black-holed TLS handshake), see #15700.
  // The Rust branch has its own 12s-per-attempt timeouts and must be
  // awaited to completion: a Dart-side timeout there would race the
  // URL-keyed ASYNC_HTTP_STATUS entry of the abandoned request.
  static const _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _pollFlutterHttp(
    Uri url,
    HttpMethod method, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final client = http.Client();
    try {
      var response = http.Response('', 400);

      switch (method) {
        case HttpMethod.get:
          response =
              await client.get(url, headers: headers).timeout(_requestTimeout);
          break;
        case HttpMethod.post:
          response = await client
              .post(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        case HttpMethod.put:
          response = await client
              .put(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        case HttpMethod.delete:
          response = await client
              .delete(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        default:
          throw Exception('Unsupported HTTP method');
      }

      return response;
    } finally {
      client.close();
    }
  }

  Future<String> _pollForResponse(String url) async {
    String? responseJson = " ";
    while (responseJson == " ") {
      responseJson = await bind.mainGetHttpStatus(url: url);
      if (responseJson == null) {
        throw Exception('The HTTP request failed');
      }
      if (responseJson == " ") {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return responseJson!;
  }

  http.Response _parseHttpResponse(String responseJson) {
    try {
      var parsedJson = jsonDecode(responseJson);
      String body = parsedJson['body'];
      Map<String, String> headers = {};
      for (var key in parsedJson['headers'].keys) {
        headers[key] = parsedJson['headers'][key];
      }
      int statusCode = parsedJson['status_code'];
      return http.Response(body, statusCode, headers: headers);
    } catch (e) {
      print('Failed to parse response\n$responseJson\nError:\n$e');
      throw Exception('Failed to parse response.\n$responseJson');
    }
  }
}

Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
  return await HttpService().sendRequest(url, HttpMethod.get, headers: headers);
}

Future<http.Response> post(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.post, body: body, headers: headers);
}

Future<http.Response> put(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.put, body: body, headers: headers);
}

Future<http.Response> delete(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.delete, body: body, headers: headers);
}
