String incomingConnectionLink({
  required String uriPrefix,
  required String id,
  String server = '',
  String key = '',
}) {
  // The client requires an explicit rendezvous port with bracketed IPv6.
  final address = server.split(':').length > 2 && !server.startsWith('[')
      ? '[$server]:21116'
      : server;
  final target = '$id@${address.isEmpty ? 'public' : address}';
  return Uri.parse('$uriPrefix$target')
      .replace(queryParameters: key.isEmpty ? null : {'key': key})
      .toString();
}
