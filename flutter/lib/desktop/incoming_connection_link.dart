String incomingConnectionLink({
  required String uriPrefix,
  required String id,
  String server = '',
  String key = '',
  String windowsLicense = '',
}) {
  // Windows executable metadata can override the saved server configuration.
  final embeddedServer = RegExp(r'^Host: (.+)$', multiLine: true)
      .firstMatch(windowsLicense)
      ?.group(1);
  final embeddedKey = RegExp(r'^Key: (.+)$', multiLine: true)
      .firstMatch(windowsLicense)
      ?.group(1);
  server = embeddedServer ?? server;
  key = embeddedServer == null ? key : embeddedKey ?? key;
  // The client requires an explicit rendezvous port with bracketed IPv6.
  final address = server.split(':').length > 2 && !server.startsWith('[')
      ? '[$server]:21116'
      : server;
  final target = '$id@${address.isEmpty ? 'public' : address}';
  return Uri.parse('$uriPrefix$target')
      .replace(queryParameters: key.isEmpty ? null : {'key': key})
      .toString();
}
