import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../common.dart' show decode_http_response;
import '../common/hbbs/hbbs.dart';
import '../utils/http_service.dart' as http;
import 'peer_model.dart';
import 'platform_model.dart';

class OwnedDevicesModel {
  static const _loadEvent = 'load_owned_devices';
  final loading = false.obs;
  final loadError = ''.obs;
  final _devices = <Peer>[].obs;
  int _generation = 0;
  bool _loaded = false;

  late final peers = Peers(
    name: 'owned devices',
    getInitPeers: () => _devices,
    loadEvent: _loadEvent,
  );

  void reset() {
    _generation++;
    _loaded = false;
    _devices.clear();
    loading.value = false;
    loadError.value = '';
    platformFFI.tryHandle({'name': _loadEvent});
  }

  Future<void> pull({
    required String apiServer,
    required String token,
    required String username,
    required bool force,
  }) async {
    if (loading.value || (_loaded && !force)) return;
    final generation = ++_generation;
    loading.value = true;
    loadError.value = '';
    try {
      final devices = <String, Peer>{};
      final endpoint = Uri.parse('$apiServer/api/peers');
      const pageSize = 100;
      var total = 0;
      for (var page = 1;; page++) {
        final uri = endpoint.replace(queryParameters: {
          'current': '$page',
          'pageSize': '$pageSize',
          'accessible': '',
          'status': '1',
        });
        final response = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
        if (generation != _generation) return;
        if (response.statusCode != 200) {
          throw RequestException(
              response.statusCode, 'HTTP ${response.statusCode}');
        }
        final body = jsonDecode(decode_http_response(response));
        if (body is! Map<String, dynamic>) {
          throw RequestException(0, 'Invalid response');
        }
        if (body['error'] != null) {
          throw RequestException(0, body['error'].toString());
        }
        final data = body['data'];
        if (data == null && body['total'] == 0) break;
        if (data is! List) throw RequestException(0, 'Invalid response');
        final entries = data;
        for (final entry in entries.whereType<Map<String, dynamic>>()) {
          if (entry['user_name'] != username) continue;
          final peer = PeerPayload.toPeer(PeerPayload.fromJson(entry));
          if (peer.id.isNotEmpty) devices[peer.id] = peer;
        }
        if (page == 1 && body['total'] is int) total = body['total'];
        if (page * pageSize >= total || entries.isEmpty) break;
      }
      _devices.assignAll(devices.values);
      _loaded = true;
      await platformFFI.tryHandle({'name': _loadEvent});
    } catch (error) {
      if (generation != _generation) return;
      if (error is RequestException && error.statusCode == 401) rethrow;
      debugPrint('Failed to load owned devices: $error');
      loadError.value = error is RequestException ? error.cause : 'Failed';
    } finally {
      if (generation == _generation) loading.value = false;
    }
  }
}
