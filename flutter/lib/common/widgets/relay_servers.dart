import 'dart:convert';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../relay_probe.dart';
import '../relay_servers.dart';
import 'workspace.dart';

class _RelayRow {
  _RelayRow(RelayEndpoint entry)
      : address = TextEditingController(text: entry.address),
        publicKey = TextEditingController(text: entry.publicKey),
        custom = entry.publicKey.isNotEmpty;

  final TextEditingController address;
  final TextEditingController publicKey;
  final addressFocus = FocusNode();
  bool custom;
  EndpointProbeResult? probeResult;
  bool probing = false;

  void dispose() {
    addressFocus.dispose();
    address.dispose();
    publicKey.dispose();
  }
}

class RelayServersField extends StatefulWidget {
  const RelayServersField(
      {super.key,
      required this.controller,
      this.error,
      this.enabled = true,
      this.readOnly = false,
      this.onEdited,
      this.probeConnector});

  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onEdited;
  final TcpProbeConnector? probeConnector;

  @override
  State<RelayServersField> createState() => _RelayServersFieldState();
}

class _RelayServersFieldState extends State<RelayServersField> {
  final _rows = <_RelayRow>[];
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _replaceRows();
    widget.controller.addListener(_fromParent);
  }

  @override
  void didUpdateWidget(RelayServersField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_fromParent);
      _replaceRows();
      widget.controller.addListener(_fromParent);
    }
  }

  void _replaceRows() {
    final entries = parseRelayServers(widget.controller.text);
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    _rows.addAll(entries.map(_RelayRow.new));
  }

  void _fromParent() {
    if (!_publishing) setState(_replaceRows);
  }

  void _publish() {
    final entries = [
      for (final row in _rows)
        if (row.custom && row.publicKey.text.trim().isEmpty)
          {'address': row.address.text, 'key': null}
        else if (row.address.text.trim().isNotEmpty || row.custom)
          RelayEndpoint(row.address.text, row.publicKey.text)
    ];
    _publishing = true;
    try {
      widget.controller.text = jsonEncode(entries);
    } finally {
      _publishing = false;
    }
    widget.onEdited?.call();
    setState(() {});
  }

  void _onAddress(_RelayRow row, String value) {
    final pasted = value
        .split(RegExp(r'[\r\n]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (pasted.length > 1 && _rows.length + pasted.length - 1 <= 8) {
      setState(() {
        row.address.text = pasted.first.trim();
        _rows.insertAll(_rows.indexOf(row) + 1,
            pasted.skip(1).map((s) => _RelayRow(RelayEndpoint(s.trim()))));
      });
    }
    _publish();
  }

  void _remove(_RelayRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
    _publish();
  }

  void _add() {
    final row = _RelayRow(const RelayEndpoint(''));
    setState(() => _rows.add(row));
    row.addressFocus.requestFocus();
  }

  bool get _anyProbing => _rows.any((r) => r.probing);

  Future<void> _probeAll() async {
    final targets =
        _rows.where((r) => r.address.text.trim().isNotEmpty).toList();
    if (targets.isEmpty || _anyProbing) return;
    setState(() {
      for (final row in targets) {
        row.probing = true;
        row.probeResult = null;
      }
    });
    await Future.wait(targets.map((row) async {
      final result = await probeTcpEndpoint(
        row.address.text.trim(),
        defaultPort: 21117,
        connector: widget.probeConnector,
      );
      if (!mounted) return;
      setState(() {
        row.probing = false;
        row.probeResult = result;
      });
    }));
  }

  Widget _probeBadge(BuildContext context, _RelayRow row) {
    if (row.probing) {
      return const Padding(
        padding: EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final res = row.probeResult;
    if (res == null) return const SizedBox.shrink();
    final Color color;
    final String label;
    if (res.reachable) {
      final ms = res.latencyMs ?? 1;
      color = ms <= 120
          ? WorkspaceStyle.success(context)
          : WorkspaceStyle.warning(context);
      label = '$ms ms';
    } else {
      color = WorkspaceStyle.danger(context);
      label = res.error ?? translate('Failed');
    }
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fromParent);
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  bool get _editable => widget.enabled && !widget.readOnly;

  String? _addressError(_RelayRow row) {
    final value = row.address.text.trim();
    if (value.isEmpty && !row.custom) return null;
    if (value.split(RegExp(r'[\r\n]+')).length + _rows.length - 1 > 8) {
      return translate('Enter up to eight relay servers');
    }
    return relayEndpointKey(value) == null
        ? translate('Invalid relay server address')
        : null;
  }

  String? _keyError(_RelayRow row) {
    final pin = row.publicKey.text.trim();
    if (row.custom &&
        (row.publicKey.text.contains(RegExp(r'[\r\n]')) ||
            !isEd25519PublicKey(pin))) {
      return translate('Enter a 32-byte Ed25519 public key in standard Base64');
    }
    final id = relayEndpointKey(row.address.text.trim());
    if (id != null &&
        _rows.any((other) =>
            other != row &&
            relayEndpointKey(other.address.text.trim()) == id &&
            other.publicKey.text.trim() != pin)) {
      return translate('Conflicting public keys for the same relay server');
    }
    return null;
  }

  Widget _node(BuildContext context, _RelayRow row) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final keyError = _keyError(row);
    final addressError = _addressError(row);
    final sourceLabel = translate(
        row.custom ? 'Custom public key' : 'Use the ID server public key');
    return Container(
      key: ObjectKey(row),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: TextField(
            controller: row.address,
            focusNode: row.addressFocus,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            decoration: InputDecoration(
                labelText: translate('Relay server address'),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: 'relay.example.com:21117',
                isDense: true,
                errorText: addressError,
                errorMaxLines: 3),
            minLines: 1,
            maxLines: 2,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            onChanged: (text) => _onAddress(row, text),
          )),
          if (!widget.readOnly)
            IconButton(
              tooltip:
                  '${translate("Remove")} ${row.address.text.trim().isEmpty ? translate("Relay Server") : row.address.text.trim()}',
              onPressed: _editable ? () => _remove(row) : null,
              icon: Icon(Icons.delete_outline,
                  size: 20, color: colors.onSurfaceVariant),
            ),
        ]),
        if (row.probing || row.probeResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.speed_rounded,
                    size: 14, color: colors.onSurfaceVariant),
                Flexible(child: _probeBadge(context, row)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          ExcludeSemantics(
              child: Icon(Icons.key_outlined,
                  color: colors.onSurfaceVariant, size: 18)),
          const SizedBox(width: 8),
          Expanded(
              child: widget.readOnly
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child:
                          Text(sourceLabel, style: theme.textTheme.bodyMedium))
                  : Semantics(
                      label: translate('Public key source'),
                      child: DropdownButtonHideUnderline(
                          child: DropdownButton<bool>(
                        isExpanded: true,
                        value: row.custom,
                        itemHeight: null,
                        icon: Icon(Icons.expand_more,
                            size: 20, color: colors.onSurfaceVariant),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurface),
                        items: [
                          for (final custom in [false, true])
                            DropdownMenuItem<bool>(
                                value: custom,
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Text(translate(custom
                                        ? 'Custom public key'
                                        : 'Use the ID server public key'))))
                        ],
                        onChanged: !_editable
                            ? null
                            : (value) {
                                if (value == null) return;
                                row.custom = value;
                                if (!value) row.publicKey.clear();
                                _publish();
                              },
                      )))),
        ]),
        if (row.custom)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: row.publicKey,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                decoration: InputDecoration(
                    labelText: translate('Relay public key'),
                    hintText: 'Ed25519 · Base64',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                    errorText: keyError,
                    errorMaxLines: 3),
                keyboardType: TextInputType.visiblePassword,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                onChanged: (_) => _publish(),
              ))
        else if (keyError != null)
          Semantics(
              liveRegion: true,
              child: Text(keyError,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.error))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasInlineError = _rows
        .any((row) => _addressError(row) != null || _keyError(row) != null);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('${translate("Relay nodes")}  ${_rows.length} / 8',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: colors.onSurfaceVariant)),
                if (_rows.any((r) => r.address.text.trim().isNotEmpty))
                  TextButton.icon(
                    onPressed: _anyProbing ? null : _probeAll,
                    icon: const Icon(Icons.speed_rounded, size: 16),
                    label: Text(translate('Test')),
                  ),
                if (widget.readOnly)
                  Text(translate('Managed by your administrator'),
                      style: theme.textTheme.bodySmall)
                else
                  OutlinedButton.icon(
                    onPressed: !_editable || _rows.length >= 8 ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(translate('Add relay server')),
                  ),
              ]),
          if (_rows.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.link, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(translate('Direct connections only'),
                          style: theme.textTheme.titleSmall),
                      if (!widget.readOnly)
                        Text(
                            translate(
                                'Both devices must use the same relay address and public key.'),
                            style: theme.textTheme.bodySmall),
                    ])),
              ]),
            ),
          for (final row in _rows) _node(context, row),
          if (widget.error?.isNotEmpty == true && !hasInlineError)
            Semantics(
                liveRegion: true,
                child: Text(widget.error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.error))),
        ]);
  }
}

Future<bool> editRelayServers(BuildContext context) async =>
    await showDialog<bool>(
        context: context,
        builder: (_) =>
            _RelayServersDialog(readOnly: isOptionFixed(relayServersOption))) ==
    true;

class _RelayServersDialog extends StatefulWidget {
  const _RelayServersDialog({required this.readOnly});
  final bool readOnly;

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
      if (mounted) {
        setState(() {
          _saving = false;
          _error = translate(e.message);
        });
      }
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    final gap = compact ? 18.0 : 24.0;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 12 : 32, vertical: 18),
      titlePadding: EdgeInsets.fromLTRB(gap, gap, gap, 12),
      contentPadding: EdgeInsets.fromLTRB(gap, 4, gap, 0),
      actionsPadding: EdgeInsets.fromLTRB(gap, 12, gap, gap),
      title: Row(children: [
        Icon(Icons.dns_outlined, color: colors.primary, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(translate('Relay servers'))),
      ]),
      content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
              child: RelayServersField(
            controller: _controller,
            error: _error,
            enabled: !_saving,
            readOnly: widget.readOnly,
            onEdited: () {
              if (_error != null) setState(() => _error = null);
            },
          ))),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(translate(widget.readOnly ? 'Close' : 'Cancel'))),
        if (!widget.readOnly)
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(translate('Save'))),
      ],
    );
  }
}
