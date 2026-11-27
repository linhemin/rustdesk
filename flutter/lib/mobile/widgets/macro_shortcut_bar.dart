import 'dart:convert';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

const String kMobileMacroPinnedKey = 'mobile-macro-pinned-v1';

class MobileMacroShortcut {
  const MobileMacroShortcut({
    required this.id,
    required this.label,
    required this.keys,
  });

  final String id;
  final String label;
  final List<String> keys;
}

const List<MobileMacroShortcut> kAllMobileMacros = [
  MobileMacroShortcut(id: 'copy', label: 'Ctrl+C', keys: ['Control', 'c']),
  MobileMacroShortcut(id: 'paste', label: 'Ctrl+V', keys: ['Control', 'v']),
  MobileMacroShortcut(id: 'undo', label: 'Ctrl+Z', keys: ['Control', 'z']),
  MobileMacroShortcut(id: 'alt_tab', label: 'Alt+Tab', keys: ['Alt', 'Tab']),
  MobileMacroShortcut(id: 'win_d', label: 'Win+D', keys: ['Meta', 'd']),
  MobileMacroShortcut(
      id: 'cmd_space', label: 'Cmd+Space', keys: ['Meta', 'Space']),
  MobileMacroShortcut(
      id: 'task_mgr',
      label: 'TaskMgr',
      keys: ['Control', 'Shift', 'Escape']),
  MobileMacroShortcut(id: 'lock', label: 'Win+L', keys: ['Meta', 'l']),
];

const List<String> kDefaultPinnedMacroIds = [
  'copy',
  'paste',
  'undo',
  'alt_tab',
  'win_d',
  'task_mgr',
];

List<String> loadPinnedMobileMacroIds() {
  final raw = bind.getLocalFlutterOption(k: kMobileMacroPinnedKey).trim();
  if (raw.isEmpty) return List<String>.from(kDefaultPinnedMacroIds);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      final valid = kAllMobileMacros.map((e) => e.id).toSet();
      final ids = decoded
          .whereType<String>()
          .where(valid.contains)
          .toList(growable: false);
      if (ids.isNotEmpty) return ids;
    }
  } catch (_) {}
  return List<String>.from(kDefaultPinnedMacroIds);
}

Future<void> savePinnedMobileMacroIds(List<String> ids) async {
  await bind.setLocalFlutterOption(
    k: kMobileMacroPinnedKey,
    v: jsonEncode(ids),
  );
}

List<MobileMacroShortcut> resolvePinnedMobileMacros(List<String> ids) {
  final byId = {for (final m in kAllMobileMacros) m.id: m};
  return [
    for (final id in ids)
      if (byId[id] case final macro?) macro,
  ];
}

/// Compact dark-glass pinned shortcut macro strip for mobile remote sessions.
class MobileMacroBar extends StatefulWidget {
  const MobileMacroBar({
    super.key,
    required this.onTrigger,
    this.initialPinnedIds,
  });

  final void Function(MobileMacroShortcut macro) onTrigger;
  final List<String>? initialPinnedIds;

  @override
  State<MobileMacroBar> createState() => _MobileMacroBarState();
}

class _MobileMacroBarState extends State<MobileMacroBar> {
  late List<String> _pinnedIds;

  @override
  void initState() {
    super.initState();
    _pinnedIds = widget.initialPinnedIds != null
        ? List<String>.from(widget.initialPinnedIds!)
        : loadPinnedMobileMacroIds();
  }

  Future<void> _customize() async {
    final selected = Set<String>.from(_pinnedIds);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(translate('Keyboard shortcuts')),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in kAllMobileMacros)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.label),
                      value: selected.contains(m.id),
                      onChanged: (v) {
                        setLocal(() {
                          if (v == true) {
                            selected.add(m.id);
                          } else if (selected.length > 1) {
                            selected.remove(m.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(translate('OK')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final ordered = [
      for (final m in kAllMobileMacros)
        if (selected.contains(m.id)) m.id,
    ];
    setState(() => _pinnedIds = ordered);
    await savePinnedMobileMacroIds(ordered);
  }

  @override
  Widget build(BuildContext context) {
    final macros = resolvePinnedMobileMacros(_pinnedIds);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final macro in macros)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(
                  macro.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: const Color(0xCC1E222B),
                side: const BorderSide(color: Color(0x33FFFFFF)),
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onTrigger(macro),
              ),
            ),
          IconButton(
            tooltip: translate('Settings'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune_rounded,
                size: 17, color: Colors.white70),
            onPressed: _customize,
          ),
        ],
      ),
    );
  }
}
