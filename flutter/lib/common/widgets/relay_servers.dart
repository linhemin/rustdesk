import 'package:flutter/material.dart';

import '../../common.dart';
import '../relay_servers.dart';

class RelayServersField extends StatelessWidget {
  const RelayServersField(
      {super.key, required this.controller, this.error, this.enabled = true});

  final TextEditingController controller;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.multiline,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        decoration: InputDecoration(
          labelText: translate('Relay servers'),
          helperText: translate(
              'Enter one address per line. Leave empty to use only direct connections.'),
          helperMaxLines: 3,
          errorText: error == null || error!.isEmpty ? null : error,
          errorMaxLines: 3,
        ),
      );
}

Future<bool> editRelayServers(BuildContext context) async =>
    await showDialog<bool>(
        context: context, builder: (_) => const _RelayServersDialog()) ==
    true;

class _RelayServersDialog extends StatefulWidget {
  const _RelayServersDialog();

  @override
  State<_RelayServersDialog> createState() => _RelayServersDialogState();
}

class _RelayServersDialogState extends State<_RelayServersDialog> {
  final _controller = TextEditingController(text: configuredRelayText());
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final entries = parseRelayServers(_controller.text);
      setState(() {
        _saving = true;
        _error = null;
      });
      await storeRelayServers(entries);
      if (mounted) Navigator.pop(context, true);
    } on FormatException catch (e) {
      setState(() => _error = [
            translate(e.message),
            if (e.source != null) e.source.toString()
          ].join(' · '));
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = translate('Failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(translate('Relay servers')),
        content: SingleChildScrollView(
            child: SizedBox(
                width: 420,
                child: RelayServersField(
                    controller: _controller,
                    error: _error,
                    enabled: !_saving))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(translate('Cancel'))),
          TextButton(
              onPressed: _saving ? null : _save,
              child: Text(translate('Save'))),
        ],
      );
}
