String incomingConnectionLink({
  required String uriPrefix,
  required String id,
  String server = '',
  String key = '',
}) {
  // URI authorities require brackets around bare IPv6 addresses.
  final address = Uri.tryParse('//[$server]') == null ? server : '[$server]';
  final target = '$id@${address.isEmpty ? 'public' : address}';
  return Uri.parse('$uriPrefix$target')
      .replace(queryParameters: key.isEmpty ? null : {'key': key})
      .toString();
}
