import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/platform_model.dart';

const String kIncomingHistoryKey = 'local-incoming-history-v1';
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

Future<void> _historyOperation = Future.value();

Future<T> _withIncomingHistory<T>(Future<T> Function(File file) action) {
  final next = _historyOperation.then((_) async {
    final support = await getApplicationSupportDirectory();
    final file = File(path.join(support.path, 'incoming-history.json'));
    final lock = await File(path.join(support.path, 'incoming-history.lock'))
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await action(file);
    } finally {
      await lock.close();
    }
  });
  _historyOperation = next.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  return next;
}

Future<List<IncomingVisitorRecord>> _readIncomingHistory(File file) async {
  if (await file.exists()) {
    return parseIncomingHistory(await file.readAsString());
  }
  return parseIncomingHistory(bind.getLocalFlutterOption(k: kIncomingHistoryKey));
}

Future<void> _writeIncomingHistory(
  File file,
  Iterable<IncomingVisitorRecord> records,
) async {
  final pending = File(file.path + '.tmp');
  await pending.writeAsString(
    jsonEncode(records.map((record) => record.toJson()).toList()),
    flush: true,
  );
  await pending.rename(file.path);
}

Future<List<IncomingVisitorRecord>> loadIncomingHistory() async {
  try {
    return await _withIncomingHistory(_readIncomingHistory);
  } catch (error) {
    debugPrint('Failed to load incoming history: $error');
    return const [];
  }
}

Future<void> recordIncomingVisitor({
  required String peerId,
  required String peerName,
  required String sessionType,
}) async {
  if (peerId.trim().isEmpty) return;
  final record = IncomingVisitorRecord(
    peerId: peerId.trim(),
    peerName: peerName,
    sessionType: sessionType,
    timestampIso: DateTime.now().toUtc().toIso8601String(),
  );
  try {
    await _withIncomingHistory((file) async {
      final existing = await _readIncomingHistory(file);
      await _writeIncomingHistory(
        file,
        [record, ...existing].take(kMaxIncomingHistoryEntries),
      );
    });
  } catch (error) {
    debugPrint('Failed to record incoming connection: $error');
  }
}

Future<bool> clearIncomingHistory() async {
  try {
    await _withIncomingHistory((file) => _writeIncomingHistory(file, const []));
    if (bind.getLocalFlutterOption(k: kIncomingHistoryKey).isNotEmpty) {
      await bind.setLocalFlutterOption(k: kIncomingHistoryKey, v: '');
    }
    return true;
  } catch (error) {
    debugPrint('Failed to clear incoming history: $error');
    return false;
  }
}
