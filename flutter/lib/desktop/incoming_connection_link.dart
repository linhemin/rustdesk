String incomingConnectionLink({
  required String uriPrefix,
  required String id,
  String server = '',
  String key = '',
}) {
  final target = server.isEmpty ? id : '$id@$server';
  return Uri.parse('$uriPrefix$target')
      .replace(queryParameters: key.isEmpty ? null : {'key': key})
      .toString();
}
