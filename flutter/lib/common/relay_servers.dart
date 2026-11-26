import 'dart:convert';

const relayServersOption = 'relay-servers';

/// Old installations have one relay address. An explicit empty list takes precedence.
String relayServerText(String stored, String legacy) {
  try {
    final value = stored.isEmpty
        ? [if (legacy.trim().isNotEmpty) legacy]
        : jsonDecode(stored);
    if (value is List &&
        value.length <= 8 &&
        value.every((item) =>
            item is String &&
            item.trim().isNotEmpty &&
            !item.contains(RegExp(r'[\r\n]')))) {
      return parseRelayServers(value.join('\n')).join('\n');
    }
  } on FormatException {
    // A malformed explicit list never enables a legacy endpoint.
  }
  return '';
}

List<String> parseRelayServers(String text) {
  final result = <String>[];
  final seen = <String>{};
  for (final input in const LineSplitter().convert(text)) {
    final entry = input.trim();
    if (entry.isEmpty) continue;
    final key = _endpointKey(entry);
    if (key == null) {
      throw FormatException('Invalid relay server address', entry);
    }
    if (seen.add(key)) result.add(entry);
    if (result.length > 8) {
      throw const FormatException('Enter up to eight relay servers');
    }
  }
  return result;
}

String? _endpointKey(String entry) {
  if (entry.length > 255 ||
      entry.codeUnits.any((c) => c > 127) ||
      RegExp(r'[\s\\?#@\x00-\x1f\x7f]').hasMatch(entry)) return null;
  final web = entry.startsWith('ws://') || entry.startsWith('wss://');
  final authority =
      web ? entry.substring(entry.indexOf('://') + 3).split('/').first : entry;
  if (authority.isEmpty || (!web && authority.contains('/'))) return null;
  if (!web &&
      !authority.startsWith('[') &&
      ':'.allMatches(authority).length > 1) {
    try {
      return 'tcp/${Uri.parseIPv6Address(authority).join('.')}/21117';
    } on FormatException {
      return null;
    }
  }
  final match = RegExp(r'^(\[[^\]]+\]|[A-Za-z0-9.-]+)(?::([0-9]+))?$')
      .firstMatch(authority);
  if (match == null) return null;
  var host = match[1]!;
  final port = match[2] == null
      ? (web ? (entry.startsWith('wss:') ? 443 : 80) : 21117)
      : int.tryParse(match[2]!);
  if (port == null || port < 1 || port > 65535) return null;
  try {
    if (host.startsWith('[')) {
      host = Uri.parseIPv6Address(host.substring(1, host.length - 1)).join('.');
    } else if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      final address = Uri.parseIPv4Address(host).join('.');
      if (address != host) return null;
    } else {
      host = host.toLowerCase();
      if (host.endsWith('.')) host = host.substring(0, host.length - 1);
      if (host.length > 253 ||
          host.split('.').any((s) =>
              !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(s))) {
        return null;
      }
    }
    if (!web) {
      if (!authority.startsWith('[') && '$host:$port'.length > 255) return null;
      return 'tcp/$host/$port';
    }
    final uri = Uri.parse(entry);
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) return null;
    if (uri.toString().length > 255) return null;
    return '${uri.scheme}/$host/$port/${uri.path.isEmpty ? "/" : uri.path}';
  } on FormatException {
    return null;
  }
}
