import 'dart:convert';

const relayServersOption = 'relay-servers';

class RelayEndpoint {
  const RelayEndpoint(this.address, [this.publicKey = '']);

  final String address;
  final String publicKey;

  Object toJson() =>
      publicKey.isEmpty ? address : {'address': address, 'key': publicKey};
}

bool isEd25519PublicKey(String value) =>
    RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value) &&
    base64Encode(base64Decode(value)) == value;

// A text draft also accepts the address-only format used by the previous editor.
String relayDraft(Iterable<RelayEndpoint> entries) =>
    entries.any((e) => e.publicKey.isNotEmpty)
        ? jsonEncode(entries.toList())
        : entries.map((e) => e.address).join('\n');

List<RelayEndpoint> relayEntriesFromJson(dynamic value) {
  if (value is! List || value.length > 8) {
    throw const FormatException('Enter up to eight relay servers');
  }
  final rows = <RelayEndpoint>[];
  for (final row in value) {
    if (row is String) {
      rows.add(RelayEndpoint(row));
    } else if (row is Map &&
        row['address'] is String &&
        row.keys.every((k) => k == 'address' || k == 'key')) {
      if (row.containsKey('key') && row['key'] is! String) {
        throw const FormatException(
            'Enter a 32-byte Ed25519 public key in standard Base64');
      }
      rows.add(RelayEndpoint(row['address'], row['key'] ?? ''));
    } else {
      throw const FormatException('Invalid relay server address');
    }
  }
  return _checkedRelayEntries(rows);
}

String relayServerText(String stored, String legacy) {
  try {
    final value = stored.isEmpty
        ? [if (legacy.trim().isNotEmpty) legacy]
        : jsonDecode(stored);
    return relayDraft(relayEntriesFromJson(value));
  } on FormatException {
    // An explicitly invalid list must never fall back to another identity.
    return '';
  }
}

List<RelayEndpoint> parseRelayServers(String text) {
  // A bracketed IPv6 address is also valid in the previous multiline format.
  final data = text.trim();
  if (data.startsWith('[{') || data.startsWith('["') || data == '[]') {
    return relayEntriesFromJson(jsonDecode(data));
  }
  return _checkedRelayEntries(const LineSplitter()
      .convert(text)
      .where((s) => s.trim().isNotEmpty)
      .map((s) => RelayEndpoint(s)));
}

List<RelayEndpoint> _checkedRelayEntries(Iterable<RelayEndpoint> rows) {
  final result = <String, RelayEndpoint>{};
  for (final row in rows) {
    final entry = row.address.trim();
    if (entry.isEmpty || row.address.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid relay server address');
    }
    final endpoint = relayEndpointKey(entry);
    if (endpoint == null) {
      throw const FormatException('Invalid relay server address');
    }
    final pin = row.publicKey.trim();
    if (row.publicKey.contains(RegExp(r'[\r\n]')) ||
        (pin.isNotEmpty && !isEd25519PublicKey(pin))) {
      throw const FormatException(
          'Enter a 32-byte Ed25519 public key in standard Base64');
    }
    final previous = result[endpoint];
    if (previous != null && previous.publicKey != pin) {
      throw const FormatException(
          'Conflicting public keys for the same relay server');
    }
    result.putIfAbsent(endpoint, () => RelayEndpoint(entry, pin));
    if (result.length > 8) {
      throw const FormatException('Enter up to eight relay servers');
    }
  }
  return result.values.toList();
}

String? relayEndpointKey(String entry) {
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
      if (host == 'relay-id.invalid' || host.endsWith('.relay-id.invalid')) {
        return null;
      }
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
