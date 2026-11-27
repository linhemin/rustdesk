import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../local_peer_backup.dart';
import '../../models/platform_model.dart';
import 'workspace.dart';

/// Opens the WebDAV backup/sync dialog and executes push or pull.
Future<int?> showWebDavSyncDialog(BuildContext context) async {
  final current = WebDavSyncConfig.load();
  final urlCtrl = TextEditingController(text: current.endpoint);
  final userCtrl = TextEditingController(text: current.username);
  final passCtrl = TextEditingController(text: current.password);
  try {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'WebDAV URL',
                  hintText: 'https://dav.example.com/rustdesk/',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userCtrl,
                decoration: InputDecoration(labelText: translate('Username')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(labelText: translate('Password')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Cancel')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'pull'),
            child: Text(translate('Import')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'push'),
            child: Text(translate('Export')),
          ),
        ],
      ),
    );
    if (action == null) return null;
    final config = WebDavSyncConfig(
      endpoint: urlCtrl.text,
      username: userCtrl.text,
      password: passCtrl.text,
    );
    await config.save();
    return action == 'push'
        ? await pushLocalPeersToWebDav(config)
        : await pullLocalPeersFromWebDav(config);
  } finally {
    urlCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
  }
}

/// Unified status and local backup/WebDAV sync card for Account settings.
class AccountSyncCard extends StatefulWidget {
  const AccountSyncCard({super.key, this.allowFileBackup = true});

  final bool allowFileBackup;

  @override
  State<AccountSyncCard> createState() => _AccountSyncCardState();
}

class _AccountSyncCardState extends State<AccountSyncCard> {
  bool _busy = false;
  String _lastSync = '';

  @override
  void initState() {
    super.initState();
    _refreshTimestamp();
  }

  void _refreshTimestamp() {
    final raw = bind.getLocalFlutterOption(k: kLocalSyncTimestampKey).trim();
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) {
      _lastSync = '';
      return;
    }
    String pad(int n) => n.toString().padLeft(2, '0');
    _lastSync =
        '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await action();
      _refreshTimestamp();
      if (mounted && msg != null) showToast(msg);
    } catch (_) {
      if (mounted) showToast(translate('Failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showWebDavDialog() async {
    await _run(() async {
      final count = await showWebDavSyncDialog(context);
      return count == null ? null : '${translate('Successful')} ($count)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final loggedIn = gFFI.userModel.userName.value.isNotEmpty;
      final modeColor = loggedIn
          ? WorkspaceStyle.success(context)
          : theme.colorScheme.primary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: modeColor.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      loggedIn ? Icons.cloud_done_outlined : Icons.devices_other,
                      size: 14,
                      color: modeColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      translate(loggedIn ? 'Account' : 'Local'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: modeColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (_lastSync.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _lastSync,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: Text(translate('Export')),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final count = await exportLocalPeersToClipboard();
                          return '${translate('Copied')} ($count)';
                        }),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.content_paste_rounded, size: 15),
                label: Text(translate('Import')),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final count = await importLocalPeersFromClipboard();
                          return '${translate('Successful')} ($count)';
                        }),
              ),
              if (widget.allowFileBackup && !isWeb) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_alt_rounded, size: 15),
                  label: Text('${translate('Export')} JSON'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final count = await exportLocalPeersToFile();
                            return count == null
                                ? null
                                : '${translate('Successful')} ($count)';
                          }),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open_outlined, size: 15),
                  label: Text('${translate('Import')} JSON'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final count = await importLocalPeersFromFile();
                            return count == null
                                ? null
                                : '${translate('Successful')} ($count)';
                          }),
                ),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_sync_outlined, size: 15),
                label: const Text('WebDAV'),
                onPressed: _busy ? null : _showWebDavDialog,
              ),
            ],
          ),
        ],
      );
    });
  }
}
