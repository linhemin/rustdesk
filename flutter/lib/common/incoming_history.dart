import 'dart:convert';

import '../models/platform_model.dart';

const String kIncomingHistoryKey = 'local-incoming-history-v1';
const String kIncomingDndUntilKey = 'local-incoming-dnd-until-v1';
const int kMaxIncomingHistoryEntries = 50;

class IncomingVisitorRecord {
  const IncomingVisitorRecord({
    required this.peerId,
    required this.peerName,
    required this.sessionType,
    required this.timestampIso,
    this.note = '',
  });

  final String peerId;
  final String peerName;
  final String sessionType;
  final String timestampIso;
  final String note;

  Map<String, dynamic> toJson() => {
        'peer_id': peerId,
        'peer_name': peerName,
        'session_type': sessionType,
        'timestamp': timestampIso,
        if (note.isNotEmpty) 'note': note,
      };

  static IncomingVisitorRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final peerId = (raw['peer_id'] ?? '').toString().trim();
    if (peerId.isEmpty) return null;
    return IncomingVisitorRecord(
      peerId: peerId,
      peerName: (raw['peer_name'] ?? '').toString().trim(),
      sessionType: (raw['session_type'] ?? 'remote').toString().trim(),
      timestampIso: (raw['timestamp'] ?? '').toString().trim(),
      note: (raw['note'] ?? '').toString().trim(),
    );
  }
}

List<IncomingVisitorRecord> parseIncomingHistory(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (IncomingVisitorRecord.fromJson(item) case final rec?) rec,
    ];
  } catch (_) {
    return const [];
  }
}

List<IncomingVisitorRecord> loadIncomingHistory() {
  try {
    return parseIncomingHistory(
        bind.getLocalFlutterOption(k: kIncomingHistoryKey));
  } catch (_) {
    return const [];
  }
}

Future<void> recordIncomingVisitor({
  required String peerId,
  required String peerName,
  required String sessionType,
  String note = '',
  DateTime? now,
}) async {
  final cleanId = peerId.trim();
  if (cleanId.isEmpty) return;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  final existing = loadIncomingHistory();
  final updated = <IncomingVisitorRecord>[
    IncomingVisitorRecord(
      peerId: cleanId,
      peerName: peerName.trim(),
      sessionType: sessionType.trim().isEmpty ? 'remote' : sessionType.trim(),
      timestampIso: ts,
      note: note.trim(),
    ),
    ...existing,
  ];
  final trimmed = updated.length > kMaxIncomingHistoryEntries
      ? updated.sublist(0, kMaxIncomingHistoryEntries)
      : updated;
  try {
    await bind.setLocalFlutterOption(
      k: kIncomingHistoryKey,
      v: jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  } catch (_) {}
}

Future<void> clearIncomingHistory() async {
  try {
    await bind.setLocalFlutterOption(k: kIncomingHistoryKey, v: '');
  } catch (_) {}
}

DateTime? loadIncomingDndUntil() {
  try {
    final raw = bind.getLocalFlutterOption(k: kIncomingDndUntilKey).trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  } catch (_) {
    return null;
  }
}

Future<void> saveIncomingDndUntil(DateTime? until) async {
  try {
    await bind.setLocalFlutterOption(
      k: kIncomingDndUntilKey,
      v: until == null ? '' : until.toUtc().toIso8601String(),
    );
  } catch (_) {}
}
