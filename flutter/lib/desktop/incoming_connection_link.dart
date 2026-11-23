String incomingConnectionLink({
  required String uriPrefix,
  required String id,
  String server = '',
  String key = '',
}) {
  final target = '$id@${server.isEmpty ? 'public' : server}';
  return Uri.parse('${uriPrefix}connect')
      .replace(
          path: '/$target', queryParameters: key.isEmpty ? null : {'key': key})
      .toString();
}
