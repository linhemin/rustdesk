import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

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
                  ? WorkspaceStyle.accentSoft(context)
                  : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
          final showBrowsers = !_showQueue || dualPane;
          final queueButton = TextButton.icon(
            onPressed: () => setState(() => _showQueue = !_showQueue),
            icon: const Icon(Icons.swap_vert_rounded, size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(widget.queueLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: WorkspaceStyle.accentSoft(context),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: widget.queueCount,
              ),
              const SizedBox(width: 8),
              Icon(_showQueue ? Icons.expand_more : Icons.expand_less,
                  size: 16),
            ]),
          );
          return ColoredBox(
            color: WorkspaceStyle.canvas(context),
            child: Column(children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  Stack(fit: StackFit.expand, children: [
                    _browser(widget.local, showBrowsers && (dualPane || _local),
                        AlignmentDirectional.centerStart, dualPane ? .5 : 1),
                    _browser(
                        widget.remote,
                        showBrowsers && (dualPane || !_local),
                        AlignmentDirectional.centerEnd,
                        dualPane ? .5 : 1),
                    if (dualPane) Center(child: VerticalDivider(width: 1)),
                  ]),
                  if (_showQueue && !dualPane) widget.queue,
                ]),
              ),
              const Divider(height: 1),
              Material(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(children: [
                    if (!dualPane) ...[
                      _sideButton(widget.localLabel, true),
                      _sideButton(widget.remoteLabel, false),
                    ],
                    Flexible(child: queueButton),
                  ]),
                ),
              ),
              if (_showQueue && dualPane)
                SizedBox(
                  height: (bounds.maxHeight * .38).clamp(100.0, 260.0),
                  child: widget.queue,
                ),
            ]),
          );
        },
      );
}
