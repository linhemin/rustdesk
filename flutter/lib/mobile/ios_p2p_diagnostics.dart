import 'dart:convert';
import 'dart:io';

// The native iOS writer replaces the complete UTF-8 report atomically. It can
// contain earlier sessions from the same app run, including after reconnects.
Future<String?> readIosP2pDiagnostics(
    Directory documents, DateTime sessionOpened) async {
  const header = 'RustDesk P2P diagnostics\nformat=udp-reads-v1';
  const limit = 48 * 1024;
  final file = File('${documents.path}/RustDesk-P2P-diagnostics.txt');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) return null;

  final handle = await file.open();
  final List<int> bytes;
  try {
    bytes = await handle.read(limit + 1);
  } finally {
    await handle.close();
  }
  if (bytes.length > limit) throw const FormatException('Report too large');

  final sections = utf8.decode(bytes).split('\n\n');
  if (sections.first != header) return null;
  final records = <String>[];
  for (final section in sections.skip(1)) {
    final space = section.indexOf(' ');
    if (space < 1) continue;
    final time = DateTime.tryParse(section.substring(0, space));
    // Native sample timestamps are UTC with millisecond precision.
    if (time != null &&
        time.isUtc &&
        time.millisecondsSinceEpoch >= sessionOpened.millisecondsSinceEpoch) {
      records.add(section.trimRight());
    }
  }
  return records.isEmpty ? null : '$header\n\n${records.join('\n\n')}\n';
}
