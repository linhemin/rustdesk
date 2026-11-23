String? serverConfigFromQr(String code, {required String uriPrefix}) {
  if (code.startsWith('config=')) return code.substring(7);
  if (!code.startsWith(uriPrefix)) return null;
  final uri = Uri.tryParse(code);
  if (uri?.authority != 'config' || !uri!.path.startsWith('/')) return null;
  return Uri.decodeComponent(uri.path.substring(1));
}
