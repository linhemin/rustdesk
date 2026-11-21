import 'package:flutter/material.dart';

/// Keeps both file browsers mounted while changing the visible pane.
class FileTransferWorkspace extends StatefulWidget {
  const FileTransferWorkspace({
    super.key,
    required this.local,
    required this.remote,
    required this.queue,
    required this.localLabel,
    required this.remoteLabel,
    required this.queueLabel,
    required this.queueCount,
  });

  final Widget local;
  final Widget remote;
  final Widget queue;
  final String localLabel;
  final String remoteLabel;
  final String queueLabel;
  final Widget queueCount;

  @override
  State<FileTransferWorkspace> createState() => _FileTransferWorkspaceState();
}

class _FileTransferWorkspaceState extends State<FileTransferWorkspace> {
  bool _local = true;
  bool _showQueue = false;

  Widget _browser(Widget child, bool visible, AlignmentDirectional alignment,
      double widthFactor) {
    return Offstage(
      offstage: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: Align(
          alignment: alignment,
          child: FractionallySizedBox(widthFactor: widthFactor, child: child),
        ),
      ),
    );
  }

  Widget _sideButton(String label, bool local) => Expanded(
        child: Semantics(
          selected: !_showQueue && _local == local,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: !_showQueue && _local == local
                  ? Theme.of(context).colorScheme.primary.withOpacity(.12)
                  : null,
            ),
            onPressed: () => setState(() {
              _local = local;
              _showQueue = false;
            }),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, bounds) {
          final dualPane = bounds.maxWidth >= 780;
          final sideQueue = _showQueue && bounds.maxWidth >= 1100;
          final queueWidth = sideQueue ? 280.0 : 0.0;
          final showBrowsers = !_showQueue || sideQueue;
          final queueButton = TextButton.icon(
            onPressed: () => setState(() => _showQueue = !_showQueue),
            icon: Icon(_showQueue ? Icons.expand_more : Icons.swap_vert,
                size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(widget.queueLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              widget.queueCount,
            ]),
          );
          return Column(children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: queueWidth),
                  child: Stack(fit: StackFit.expand, children: [
                    _browser(widget.local, showBrowsers && (dualPane || _local),
                        AlignmentDirectional.centerStart, dualPane ? .5 : 1),
                    _browser(
                        widget.remote,
                        showBrowsers && (dualPane || !_local),
                        AlignmentDirectional.centerEnd,
                        dualPane ? .5 : 1),
                  ]),
                ),
                if (_showQueue)
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    start: sideQueue ? null : 0,
                    end: 0,
                    width: sideQueue ? queueWidth : null,
                    child: widget.queue,
                  ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!dualPane) ...[
                  _sideButton(widget.localLabel, true),
                  _sideButton(widget.remoteLabel, false),
                ],
                Flexible(child: queueButton),
              ]),
            ),
          ]);
        },
      );
}
