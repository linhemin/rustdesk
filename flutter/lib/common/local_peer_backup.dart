import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/platform_model.dart';

const kLocalPeerBackupFormat = 'rustdesk-local-peers-v1';
const kWebDavSyncOptionKey = 'local-peer-webdav-sync';
const kLocalSyncTimestampKey = 'local-peer-last-sync';

class LocalPeerBackupEntry {
  const LocalPeerBackupEntry({
    required this.id,
    this.alias = '',
    this.hostname = '',
    this.username = '',
    this.platform = '',
    this.favorite = false,
  });

  final String id;
  final String alias;
  final String hostname;
  final String username;
  final String platform;
  final bool favorite;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (alias.isNotEmpty) 'alias': alias,
        if (hostname.isNotEmpty) 'hostname': hostname,
        if (username.isNotEmpty) 'username': username,
        if (platform.isNotEmpty) 'platform': platform,
        if (favorite) 'favorite': true,
      };

  factory LocalPeerBackupEntry.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] ?? '').toString().replaceAll(' ', '').trim();
    return LocalPeerBackupEntry(
      id: rawId,
      alias: (json['alias'] ?? '').toString().trim(),
      hostname: (json['hostname'] ?? '').toString().trim(),
      username: (json['username'] ?? '').toString().trim(),
      platform: (json['platform'] ?? '').toString().trim(),
      favorite: json['favorite'] == true,
    );
  }
}

class LocalPeerBackupBundle {
  const LocalPeerBackupBundle({
    required this.version,
    required this.exportedAt,
    required this.peers,
  });

  final int version;
  final String exportedAt;
  final List<LocalPeerBackupEntry> peers;

  String encode() {
    final payload = <String, dynamic>{
      'format': kLocalPeerBackupFormat,
      'version': version,
      'exported_at': exportedAt,
      'peers': [for (final peer in peers) peer.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static LocalPeerBackupBundle decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Backup content is empty');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup JSON');
    }
    if (decoded['format'] != kLocalPeerBackupFormat) {
      throw const FormatException('Unsupported backup format');
    }
    final rawPeers = decoded['peers'];
    if (rawPeers is! List) {
      throw const FormatException('Missing peers list');
    }
    final seen = <String>{};
    final entries = <LocalPeerBackupEntry>[];
    for (final item in rawPeers) {
      if (item is! Map) continue;
      final entry =
          LocalPeerBackupEntry.fromJson(Map<String, dynamic>.from(item));
      if (entry.id.isEmpty || !seen.add(entry.id)) continue;
      entries.add(entry);
    }
    return LocalPeerBackupBundle(
      version: decoded['version'] is int ? decoded['version'] as int : 1,
      exportedAt: (decoded['exported_at'] ?? '').toString(),
      peers: entries,
    );
  }
}

/// Builds a deduplicated backup bundle from raw recent peers JSON and favorites.
/// Passwords and hashes are intentionally omitted for safety.
LocalPeerBackupBundle buildLocalPeerBackup({
  required String recentPeersJson,
  required List<String> favorites,
  DateTime? now,
}) {
  final favSet = favorites
      .map((id) => id.replaceAll(' ', '').trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final entriesById = <String, LocalPeerBackupEntry>{};

  if (recentPeersJson.trim().isNotEmpty) {
    final decoded = jsonDecode(recentPeersJson);
    if (decoded is List) {
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? '').toString().replaceAll(' ', '').trim();
        if (id.isEmpty) continue;
        entriesById[id] = LocalPeerBackupEntry(
          id: id,
          alias: (raw['alias'] ?? '').toString().trim(),
          hostname: (raw['hostname'] ?? '').toString().trim(),
          username: (raw['username'] ?? '').toString().trim(),
          platform: (raw['platform'] ?? '').toString().trim(),
          favorite: favSet.contains(id),
        );
      }
    }
  }

  for (final id in favSet) {
    entriesById.putIfAbsent(
      id,
      () => LocalPeerBackupEntry(id: id, favorite: true),
    );
  }

  final sorted = entriesById.values.toList()
    ..sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.id.compareTo(b.id);
    });

  return LocalPeerBackupBundle(
    version: 1,
    exportedAt: (now ?? DateTime.now().toUtc()).toIso8601String(),
    peers: sorted,
  );
}

/// Merges imported favorite IDs with existing favorites while preserving order.
List<String> mergeFavoriteIds(
  List<String> existing,
  List<LocalPeerBackupEntry> imported,
) {
  final merged = <String>[];
  final seen = <String>{};
  for (final id in existing) {
    final clean = id.replaceAll(' ', '').trim();
    if (clean.isNotEmpty && seen.add(clean)) {
      merged.add(clean);
    }
  }
  for (final peer in imported) {
    if (peer.favorite && seen.add(peer.id)) {
      merged.add(peer.id);
    }
  }
  return merged;
}

Future<int> exportLocalPeersToClipboard() async {
  final rawPeers = await bind.mainLoadRecentPeersForAb(filter: '');
  final favs = await bind.mainGetFav();
  final bundle = buildLocalPeerBackup(
    recentPeersJson: rawPeers,
    favorites: favs,
  );
  await Clipboard.setData(ClipboardData(text: bundle.encode()));
  return bundle.peers.length;
}

Future<int> importLocalPeersFromClipboard() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text ?? '';
  return importLocalPeersFromJson(text);
}

Future<int> importLocalPeersFromJson(String raw) async {
  final bundle = LocalPeerBackupBundle.decode(raw);
  final existingFavs = await bind.mainGetFav();
  final mergedFavs = mergeFavoriteIds(existingFavs, bundle.peers);
  await bind.mainStoreFav(favs: mergedFavs);
  for (final peer in bundle.peers) {
    if (peer.alias.isNotEmpty) {
      await bind.mainSetPeerAlias(id: peer.id, alias: peer.alias);
    }
  }
  await bind.mainLoadFavPeers();
  await bind.mainLoadRecentPeers();
  await bind.setLocalFlutterOption(
    k: kLocalSyncTimestampKey,
    v: DateTime.now().toUtc().toIso8601String(),
  );
  return bundle.peers.length;
}

Future<int?> exportLocalPeersToFile() async {
  final rawPeers = await bind.mainLoadRecentPeersForAb(filter: '');
  final favs = await bind.mainGetFav();
  final bundle = buildLocalPeerBackup(
    recentPeersJson: rawPeers,
    favorites: favs,
  );
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export',
    fileName: 'rustdesk-peers-backup.json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (path == null || path.isEmpty) return null;
  await File(path).writeAsString(bundle.encode());
  await bind.setLocalFlutterOption(
    k: kLocalSyncTimestampKey,
    v: DateTime.now().toUtc().toIso8601String(),
  );
  return bundle.peers.length;
}

Future<int?> importLocalPeersFromFile() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.first;
  final String content;
  if (file.bytes != null) {
    content = utf8.decode(file.bytes!);
  } else if (file.path != null && file.path!.isNotEmpty) {
    content = await File(file.path!).readAsString();
  } else {
    throw const FormatException('Empty file');
  }
  return importLocalPeersFromJson(content);
}

class WebDavSyncConfig {
  const WebDavSyncConfig({
    this.endpoint = '',
    this.username = '',
    this.password = '',
  });

  final String endpoint;
  final String username;
  final String password;

  bool get isValid {
    final uri = Uri.tryParse(endpoint.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Uri get targetUri {
    final clean = endpoint.trim();
    if (clean.endsWith('.json')) return Uri.parse(clean);
    final base = clean.endsWith('/') ? clean : '$clean/';
    return Uri.parse('${base}rustdesk-peers-backup.json');
  }

  Map<String, String> authHeaders() {
    if (username.isEmpty && password.isEmpty) return const {};
    final encoded = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $encoded'};
  }

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint.trim(),
        'username': username.trim(),
        'password': password,
      };

  static WebDavSyncConfig load() {
    try {
      final raw = bind.getLocalFlutterOption(k: kWebDavSyncOptionKey);
      if (raw.trim().isEmpty) return const WebDavSyncConfig();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const WebDavSyncConfig();
      return WebDavSyncConfig(
        endpoint: (decoded['endpoint'] ?? '').toString(),
        username: (decoded['username'] ?? '').toString(),
        password: (decoded['password'] ?? '').toString(),
      );
    } catch (_) {
      return const WebDavSyncConfig();
    }
  }

  Future<void> save() => bind.setLocalFlutterOption(
        k: kWebDavSyncOptionKey,
        v: jsonEncode(toJson()),
      );
}

Future<int> pushLocalPeersToWebDav(
  WebDavSyncConfig config, {
  http.Client? client,
}) async {
  if (!config.isValid) throw const FormatException('Invalid WebDAV URL');
  final rawPeers = await bind.mainLoadRecentPeersForAb(filter: '');
  final favs = await bind.mainGetFav();
  final bundle = buildLocalPeerBackup(
    recentPeersJson: rawPeers,
    favorites: favs,
  );
  final owned = client == null;
  final httpClient = client ?? http.Client();
  try {
    final res = await httpClient
        .put(
          config.targetUri,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            ...config.authHeaders(),
          },
          body: bundle.encode(),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('WebDAV HTTP ${res.statusCode}');
    }
    await bind.setLocalFlutterOption(
      k: kLocalSyncTimestampKey,
      v: DateTime.now().toUtc().toIso8601String(),
    );
    return bundle.peers.length;
  } finally {
    if (owned) httpClient.close();
  }
}

Future<int> pullLocalPeersFromWebDav(
  WebDavSyncConfig config, {
  http.Client? client,
}) async {
  if (!config.isValid) throw const FormatException('Invalid WebDAV URL');
  final owned = client == null;
  final httpClient = client ?? http.Client();
  try {
    final res = await httpClient
        .get(config.targetUri, headers: config.authHeaders())
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('WebDAV HTTP ${res.statusCode}');
    }
    return importLocalPeersFromJson(utf8.decode(res.bodyBytes));
  } finally {
    if (owned) httpClient.close();
  }
}
