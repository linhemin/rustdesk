import 'dart:async';
import 'dart:io';

typedef TcpProbeConnector = Future<Duration> Function(
  String host,
  int port,
  Duration timeout,
);

class EndpointProbeResult {
  const EndpointProbeResult({
    required this.address,
    required this.reachable,
    this.latencyMs,
    this.error,
  });

  final String address;
  final bool reachable;
  final int? latencyMs;
  final String? error;
}

/// Parses `host[:port]` (including bracketed IPv6 `[::1]:21117`) into host/port.
(String host, int port)? parseHostPort(String raw, {required int defaultPort}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('[')) {
    final end = trimmed.indexOf(']');
    if (end <= 1) return null;
    final host = trimmed.substring(1, end);
    final rest = trimmed.substring(end + 1);
    if (rest.isEmpty) return (host, defaultPort);
    if (!rest.startsWith(':')) return null;
    final port = int.tryParse(rest.substring(1));
    if (port == null || port < 1 || port > 65535) return null;
    return (host, port);
  }
  final firstColon = trimmed.indexOf(':');
  final lastColon = trimmed.lastIndexOf(':');
  if (firstColon != -1 && firstColon == lastColon) {
    final host = trimmed.substring(0, lastColon).trim();
    final port = int.tryParse(trimmed.substring(lastColon + 1).trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    return (host, port);
  }
  return (trimmed, defaultPort);
}

Future<Duration> _defaultTcpConnector(
  String host,
  int port,
  Duration timeout,
) async {
  final sw = Stopwatch()..start();
  final socket = await Socket.connect(host, port, timeout: timeout);
  sw.stop();
  socket.destroy();
  return sw.elapsed;
}

Future<EndpointProbeResult> probeTcpEndpoint(
  String address, {
  required int defaultPort,
  Duration timeout = const Duration(seconds: 4),
  TcpProbeConnector? connector,
}) async {
  final parsed = parseHostPort(address, defaultPort: defaultPort);
  if (parsed == null) {
    return EndpointProbeResult(
      address: address,
      reachable: false,
      error: 'Invalid address',
    );
  }
  final connectFn = connector ?? _defaultTcpConnector;
  try {
    final elapsed = await connectFn(parsed.$1, parsed.$2, timeout);
    return EndpointProbeResult(
      address: address,
      reachable: true,
      latencyMs: elapsed.inMilliseconds < 1 ? 1 : elapsed.inMilliseconds,
    );
  } on TimeoutException {
    return EndpointProbeResult(
      address: address,
      reachable: false,
      error: 'Timeout',
    );
  } on SocketException catch (e) {
    return EndpointProbeResult(
      address: address,
      reachable: false,
      error: e.message.isNotEmpty ? e.message : 'Unreachable',
    );
  } catch (e) {
    return EndpointProbeResult(
      address: address,
      reachable: false,
      error: e.toString(),
    );
  }
}

class NetworkDiagnosticCheck {
  const NetworkDiagnosticCheck({
    required this.title,
    required this.detail,
    required this.ok,
    this.warning = false,
  });

  final String title;
  final String detail;
  final bool ok;
  final bool warning;
}

Future<List<NetworkDiagnosticCheck>> runNetworkDiagnostics({
  required String idServer,
  required List<String> relayServers,
  bool directOnly = false,
  TcpProbeConnector? connector,
}) async {
  final checks = <NetworkDiagnosticCheck>[];
  final cleanId = idServer.trim();
  if (cleanId.isEmpty) {
    checks.add(const NetworkDiagnosticCheck(
      title: 'ID Server',
      detail: 'Public server (default)',
      ok: true,
      warning: true,
    ));
  } else {
    final res = await probeTcpEndpoint(
      cleanId,
      defaultPort: 21116,
      connector: connector,
    );
    checks.add(NetworkDiagnosticCheck(
      title: 'ID Server · $cleanId',
      detail: res.reachable
          ? 'OK · ${res.latencyMs} ms'
          : (res.error ?? 'Unreachable'),
      ok: res.reachable,
    ));
  }

  if (relayServers.isEmpty) {
    checks.add(NetworkDiagnosticCheck(
      title: 'Relay Server',
      detail: directOnly ? 'Direct connections only' : 'Auto / ID server relay',
      ok: true,
      warning: directOnly,
    ));
  } else {
    final results = await Future.wait([
      for (final relay in relayServers)
        probeTcpEndpoint(relay, defaultPort: 21117, connector: connector),
    ]);
    for (final res in results) {
      checks.add(NetworkDiagnosticCheck(
        title: 'Relay · ${res.address}',
        detail: res.reachable
            ? 'OK · ${res.latencyMs} ms'
            : (res.error ?? 'Unreachable'),
        ok: res.reachable,
      ));
    }
  }
  return checks;
}
