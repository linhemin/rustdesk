import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../common.dart';
import '../../consts.dart';
import '../relay_probe.dart';
import '../relay_servers.dart';
import '../../models/platform_model.dart';
import 'workspace.dart';

/// Displays a scannable QR code encoding the current ID + multi-relay + key
/// server configuration so mobile clients can import it in one scan.
Future<void> showServerConfigQrDialog(BuildContext context) async {
  final config = ServerConfig(
    idServer: bind.mainGetOptionSync(key: 'custom-rendezvous-server'),
    relayServer: configuredRelayText(),
    apiServer: bind.mainGetOptionSync(key: 'api-server'),
    key: bind.mainGetOptionSync(key: 'key'),
  );
  final encoded = 'config=${config.encode()}';
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(translate('ID/Relay Server')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: encoded,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                config.idServer.isEmpty
                    ? translate('Default')
                    : config.idServer,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(translate('Export Server Config')),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: config.encode()));
              showToast(translate('Copied'));
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(translate('Close')),
          ),
        ],
      );
    },
  );
}

/// Interactive human-readable network diagnostics dialog probing ID & relay servers.
Future<void> showNetworkDiagnosticsDialog(
  BuildContext context, {
  TcpProbeConnector? connector,
}) async {
  final idServer = bind.mainGetOptionSync(key: 'custom-rendezvous-server');
  final relays = parseRelayServers(configuredRelayText())
      .map((e) => e.address.trim())
      .where((a) => a.isNotEmpty)
      .toList();
  final directOnly = mainGetLocalBoolOptionSync(kOptionDirectOnly);

  await showDialog<void>(
    context: context,
    builder: (ctx) => _NetworkDiagnosticsDialog(
      idServer: idServer,
      relayServers: relays,
      directOnly: directOnly,
      connector: connector,
    ),
  );
}

class _NetworkDiagnosticsDialog extends StatefulWidget {
  const _NetworkDiagnosticsDialog({
    required this.idServer,
    required this.relayServers,
    required this.directOnly,
    this.connector,
  });

  final String idServer;
  final List<String> relayServers;
  final bool directOnly;
  final TcpProbeConnector? connector;

  @override
  State<_NetworkDiagnosticsDialog> createState() =>
      _NetworkDiagnosticsDialogState();
}

class _NetworkDiagnosticsDialogState extends State<_NetworkDiagnosticsDialog> {
  List<NetworkDiagnosticCheck>? _checks;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _checks = null);
    final results = await runNetworkDiagnostics(
      idServer: widget.idServer,
      relayServers: widget.relayServers,
      directOnly: widget.directOnly,
      connector: widget.connector,
    );
    if (mounted) setState(() => _checks = results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checks = _checks;
    return AlertDialog(
      title: Text(translate('Diagnostics')),
      content: SizedBox(
        width: 400,
        child: checks == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final check in checks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        check.ok
                            ? (check.warning
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_rounded)
                            : Icons.error_outline_rounded,
                        color: check.ok
                            ? (check.warning
                                ? WorkspaceStyle.warning(context)
                                : WorkspaceStyle.success(context))
                            : WorkspaceStyle.danger(context),
                      ),
                      title: Text(
                        check.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        check.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: check.ok
                              ? theme.hintColor
                              : WorkspaceStyle.danger(context),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(translate('Refresh')),
          onPressed: checks == null ? null : _run,
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Close')),
        ),
      ],
    );
  }
}
