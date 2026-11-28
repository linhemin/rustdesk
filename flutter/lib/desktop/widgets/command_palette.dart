import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart' hide Dialog;
import '../../common/widgets/workspace.dart';
import '../../models/peer_model.dart';

class DesktopCommandItem {
  const DesktopCommandItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onRun,
    this.keywords = const [],
    this.badge,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onRun;
  final List<String> keywords;
  final String? badge;
}

List<DesktopCommandItem> filterDesktopCommands(
  List<DesktopCommandItem> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  return items.where((item) {
    final hay = [
      item.title,
      item.subtitle,
      item.id,
      if (item.badge != null) item.badge!,
      ...item.keywords,
    ].join(' ').toLowerCase();
    return tokens.every(hay.contains);
  }).toList();
}

/// Shows the desktop `Cmd/Ctrl + K` quick command & device palette.
Future<void> showDesktopCommandPalette(
  BuildContext context, {
  required List<DesktopCommandItem> items,
  void Function(String peerId)? onConnectRawId,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _DesktopCommandPaletteDialog(
      items: items,
      onConnectRawId: onConnectRawId,
    ),
  );
}

List<DesktopCommandItem> buildPeerCommandItems({
  required List<Peer> peers,
  required void Function(Peer peer, {bool isFileTransfer, bool isTerminal})
      onConnectPeer,
}) {
  final result = <DesktopCommandItem>[];
  for (final peer in peers) {
    final title = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.hostname.isNotEmpty ? peer.hostname : peer.id);
    final sub = [
      peer.id,
      if (peer.hostname.isNotEmpty && peer.hostname != title) peer.hostname,
      if (peer.platform.isNotEmpty) peer.platform,
    ].join(' · ');
    result.add(DesktopCommandItem(
      id: 'connect:${peer.id}',
      title: title,
      subtitle: sub,
      icon: Icons.desktop_windows_outlined,
      badge: translate('Connect'),
      keywords: [
        peer.id,
        peer.alias,
        peer.hostname,
        peer.username,
        'remote',
        '远程',
        '桌面',
      ],
      onRun: () => onConnectPeer(peer),
    ));
    result.add(DesktopCommandItem(
      id: 'file:${peer.id}',
      title: '$title · ${translate('Transfer file')}',
      subtitle: sub,
      icon: Icons.folder_open_outlined,
      badge: translate('Transfer file'),
      keywords: [
        peer.id,
        peer.alias,
        peer.hostname,
        'file',
        'transfer',
        '文件',
        '传输',
      ],
      onRun: () => onConnectPeer(peer, isFileTransfer: true),
    ));
    result.add(DesktopCommandItem(
      id: 'term:${peer.id}',
      title: '$title · ${translate('Terminal')}',
      subtitle: sub,
      icon: Icons.terminal_rounded,
      badge: translate('Terminal'),
      keywords: [
        peer.id,
        peer.alias,
        peer.hostname,
        'terminal',
        'ssh',
        '终端',
      ],
      onRun: () => onConnectPeer(peer, isTerminal: true),
    ));
  }
  return result;
}

class _DesktopCommandPaletteDialog extends StatefulWidget {
  const _DesktopCommandPaletteDialog({
    required this.items,
    this.onConnectRawId,
  });

  final List<DesktopCommandItem> items;
  final void Function(String peerId)? onConnectRawId;

  @override
  State<_DesktopCommandPaletteDialog> createState() =>
      _DesktopCommandPaletteDialogState();
}

class _DesktopCommandPaletteDialogState
    extends State<_DesktopCommandPaletteDialog> {
  static const double _kItemExtent = 56.0;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  int _selected = 0;
  String _cachedQuery = '';
  late List<DesktopCommandItem> _cachedList = _computeFiltered();

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<DesktopCommandItem> _computeFiltered() {
    final matches = filterDesktopCommands(widget.items, _ctrl.text);
    final raw = _ctrl.text.trim();
    if (matches.isEmpty && raw.isNotEmpty && widget.onConnectRawId != null) {
      return [
        DesktopCommandItem(
          id: 'raw:$raw',
          title: '${translate('Connect')} $raw',
          subtitle: translate('Remote ID'),
          icon: Icons.arrow_forward_rounded,
          onRun: () => widget.onConnectRawId!(raw.replaceAll(' ', '')),
        ),
      ];
    }
    return matches;
  }

  List<DesktopCommandItem> _filtered() {
    if (_cachedQuery != _ctrl.text) {
      _cachedQuery = _ctrl.text;
      _cachedList = _computeFiltered();
    }
    return _cachedList;
  }

  void _ensureSelectedVisible() {
    if (!_scrollCtrl.hasClients) return;
    final top = _selected * _kItemExtent;
    final bottom = top + _kItemExtent;
    final offset = _scrollCtrl.offset;
    final viewport = _scrollCtrl.position.viewportDimension;
    if (top < offset) {
      _scrollCtrl.jumpTo(top);
    } else if (bottom > offset + viewport) {
      _scrollCtrl.jumpTo(bottom - viewport);
    }
  }

  void _runSelected(List<DesktopCommandItem> list) {
    if (list.isEmpty) return;
    final idx = _selected.clamp(0, list.length - 1);
    final item = list[idx];
    Navigator.of(context).pop();
    item.onRun();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered();
    if (_selected >= list.length && list.isNotEmpty) {
      _selected = list.length - 1;
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (list.isNotEmpty) {
                setState(() => _selected = (_selected + 1) % list.length);
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _ensureSelectedVisible());
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (list.isNotEmpty) {
                setState(() =>
                    _selected = (_selected - 1 + list.length) % list.length);
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _ensureSelectedVisible());
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _runSelected(list);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {
                    _selected = 0;
                    _cachedQuery = _ctrl.text;
                    _cachedList = _computeFiltered();
                  }),
                  onSubmitted: (_) => _runSelected(_filtered()),
                  decoration: InputDecoration(
                    hintText: translate('Search'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _ctrl.text.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Text(
                              'ESC',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          )
                        : IconButton(
                            tooltip: translate('Clear'),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() {
                                _selected = 0;
                                _cachedQuery = '';
                                _cachedList = _computeFiltered();
                              });
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          translate('Empty'),
                          style: TextStyle(color: theme.hintColor),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        shrinkWrap: true,
                        itemExtent: _kItemExtent,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: list.length,
                        itemBuilder: (ctx, idx) {
                          final item = list[idx];
                          final active = idx == _selected;
                          return Semantics(
                            selected: active,
                            button: true,
                            label: item.title,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              child: Material(
                                color: active
                                    ? theme.colorScheme.primary
                                        .withOpacity(0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    item.onRun();
                                  },
                                  onHover: (hover) {
                                    if (hover && _selected != idx) {
                                      setState(() => _selected = idx);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          item.icon,
                                          size: 18,
                                          color: active
                                              ? theme.colorScheme.primary
                                              : theme.hintColor,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (item.subtitle.isNotEmpty)
                                                Text(
                                                  item.subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          color:
                                                              theme.hintColor),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (item.badge != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: WorkspaceStyle
                                                  .elevatedSurface(context),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.badge!,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: theme.hintColor,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '↑↓  ·  ↵  ·  Esc',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
