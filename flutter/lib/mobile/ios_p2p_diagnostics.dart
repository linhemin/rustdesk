import 'dart:convert';
import 'dart:io';

// The native iOS writer replaces the complete UTF-8 report atomically. It can
// contain earlier sessions from the same app run, including after reconnects.
Future<String?> readIosP2pDiagnostics(
    Directory documents, DateTime sessionOpened) async {
  const header = 'RustDesk P2P diagnostics\nformat=udp-paths-v3';
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

/// Only copy a local, recent quality sample from the currently open mobile session.
String formatIosMediaSample({
  required DateTime opened, required DateTime now, DateTime? videoAt, DateTime? delayAt,
  String? codec, String? chroma, String? fps, String? delay, String? target, bool? direct,
}) {
  bool fresh(DateTime? t) => t != null && !t.isBefore(opened) && !now.isBefore(t) &&
      now.difference(t) <= const Duration(seconds: 5);
  final fields = <String>['media', 'path=${direct == null ? "unknown" : (direct ? "direct" : "relay")}'];
  if (fresh(videoAt)) {
    if (codec != null && RegExp(r'^(H\.?26[45]|VP[89]|AV1|YUV|RGB)$', caseSensitive: false).hasMatch(codec)) {
      fields.add('codec=$codec');
    }
    if (chroma == '4:2:0' || chroma == '4:4:4') fields.add('chroma=$chroma');
    if (fps != null && RegExp(r'^\d{1,3}( \d{1,3}){0,7}$').hasMatch(fps)) fields.add('displayFps=[$fps]');
  }
  if (fresh(delayAt)) {
    final rtt = int.tryParse(delay ?? '');
    final kbps = int.tryParse(target ?? '');
    if (rtt != null && rtt >= 0) fields.add('rttMs=$rtt');
    if (kbps != null && kbps >= 0) fields.add('targetKbps=$kbps');
  }
  return fields.join(' ');
}
