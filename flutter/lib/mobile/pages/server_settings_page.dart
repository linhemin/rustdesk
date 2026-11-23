import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/api_server_warning.dart';
import '../../models/platform_model.dart';
import '../server_config_qr.dart';
import '../widgets/apple_settings_list.dart';
import 'scan_page.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, this.initialConfig});

  final ServerConfig? initialConfig;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final _controllers = [
    for (final key in [
      'custom-rendezvous-server',
      'relay-server',
      'api-server',
      'key'
    ])
      TextEditingController(text: bind.mainGetOptionSync(key: key)),
  ];
  final _errors = [for (var i = 0; i < 3; i++) ''.obs];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialConfig != null) _import(widget.initialConfig!.encode());
  }

  ServerConfig get _config => ServerConfig(
      idServer: _controllers[0].text,
      relayServer: _controllers[1].text,
      apiServer: _controllers[2].text,
      key: _controllers[3].text);

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _import(String? value) {
    if (value == null || value.trim().isEmpty) {
      showToast(translate('Clipboard is empty'));
      return;
    }
    try {
      final config = ServerConfig.decode(value.trim());
      if (config.idServer.isEmpty) throw const FormatException();
      final values = [
        config.idServer,
        config.relayServer,
        config.apiServer,
        config.key
      ];
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = values[i];
      }
      for (final error in _errors) {
        error.value = '';
      }
    } catch (_) {
      showToast(translate('Invalid server configuration'));
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context)
        .push<({String code, bool gallery})>(
            MaterialPageRoute(builder: (_) => ScanPage()));
    if (!mounted || result == null) return;
    final config =
        serverConfigFromQr(result.code, uriPrefix: bind.mainUriPrefixSync());
    if (config != null) {
      _import(config);
    } else if (result.gallery &&
        result.code.startsWith(bind.mainUriPrefixSync())) {
      handleUriLink(uriString: result.code);
    } else {
      showToast(translate('Invalid QR code'));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    for (final error in _errors) {
      error.value = '';
    }
    try {
      final success = await setServerConfig(null, _errors, _config);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
        showToast(translate('Successful'));
      } else {
        showToast(translate('Failed'));
      }
    } catch (error) {
      if (mounted) showToast(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            leadingWidth: 76,
            leading: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(translate('Cancel'))),
            title: Text(translate('ID/Relay Server'),
                style: const TextStyle(fontSize: 15)),
            actions: [
              TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text(translate('Save')))
            ],
          ),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
              children: [
                Material(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Obx(() => Column(children: [
                        for (var i = 0; i < _controllers.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 16),
                          AppleSettingsField(
                            label: translate([
                              'ID Server',
                              'Relay Server',
                              'API Server',
                              'Key'
                            ][i]),
                            controller: _controllers[i],
                            enabled: !_saving,
                            error: i < _errors.length ? _errors[i].value : null,
                          ),
                        ],
                      ])),
                ),
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                        translate('Leave empty to use the public server.'),
                        style: Theme.of(context).textTheme.bodySmall)),
                ApiServerWarning(
                    controller: _controllers[2],
                    idController: _controllers[0],
                    message: translate('api_server_connection_tip'),
                    emptyMessage: translate('api_server_empty_tip')),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                    onPressed: _saving ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner, size: 17),
                    label: Text(translate('Scan QR to import'))),
                Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final data = await Clipboard.getData(
                                      Clipboard.kTextPlain);
                                  if (mounted) _import(data?.text);
                                },
                          icon: const Icon(Icons.content_paste, size: 17),
                          label: Text(translate('Import server config'))),
                      IconButton(
                          tooltip: translate('Export Server Config'),
                          onPressed: _saving
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: _config.encode()));
                                  showToast(translate(
                                      'Export server configuration successfully'));
                                },
                          icon: const Icon(Icons.copy, size: 17)),
                    ]),
                if (_saving) const LinearProgressIndicator(),
              ]),
        ),
      );
}
