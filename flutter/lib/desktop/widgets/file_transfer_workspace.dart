import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

/// Collapses ancestors into a menu rather than clipping part of a path label.
class FileTransferBreadcrumbs extends StatelessWidget {
  const FileTransferBreadcrumbs(
      {super.key, required this.parts, required this.onSelected});

  final List<String> parts;
  final ValueChanged<List<String>> onSelected;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    const buttonInset = 4.0;
    const chevronSize = 16.0;
    final style = Theme.of(context)
        .textTheme
        .labelLarge!
        .copyWith(fontSize: 12, fontWeight: FontWeight.w500);
    Widget button(int index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: buttonInset),
        child: Tooltip(
            message: parts[index],
            child: TextButton(
                style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: buttonInset),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: AlignmentDirectional.centerStart,
                    textStyle: style),
                onPressed: () => onSelected(parts.sublist(0, index + 1)),
                child: Text(parts[index],
                    maxLines: 1, overflow: TextOverflow.ellipsis))));
    return LayoutBuilder(builder: (context, bounds) {
      final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context));
      double width = parts.length * buttonInset * 4 +
          (parts.length - 1) * chevronSize +
          buttonInset * 2;
      for (final part in parts) {
        painter.text = TextSpan(text: part, style: style);
        painter.layout();
        width += painter.width;
      }
      painter.dispose();
      final shortRoot = parts.first == '/' ||
          (parts.first.length <= 3 && parts.first.contains(':'));
      final hiddenStart = shortRoot ? 1 : 0;
      final collapse =
          width > bounds.maxWidth && parts.length - hiddenStart > 1;
      final visible = collapse
          ? [if (shortRoot) 0, -1, parts.length - 1]
          : List.generate(parts.length, (index) => index);
      return Row(children: [
        for (var position = 0; position < visible.length; position++) ...[
          if (position > 0)
            const Icon(Icons.keyboard_arrow_right_rounded, size: chevronSize),
          if (visible[position] < 0)
            SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<int>(
                    tooltip: parts.take(parts.length - 1).join(' › '),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (index) =>
                        onSelected(parts.sublist(0, index + 1)),
                    itemBuilder: (_) => [
                          for (var index = hiddenStart;
                              index < parts.length - 1;
                              index++)
                            PopupMenuItem(
                                value: index,
                                child: Tooltip(
                                    message: parts[index],
                                    child: Text(parts[index],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis))),
                        ]))
          else if (visible[position] == parts.length - 1)
            Expanded(
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: button(visible[position])))
          else
            button(visible[position]),
        ],
      ]);
    });
  }
}

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
          final bottomQueue = dualPane && bounds.maxHeight >= 480;
          final showBrowsers = !_showQueue || bottomQueue;
          final queueButton = TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
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
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DefaultTextStyle.merge(
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary),
                    child: widget.queueCount),
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
                  if (_showQueue && !bottomQueue) widget.queue,
                ]),
              ),
              const Divider(height: 1),
              Material(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    if (!dualPane) ...[
                      _sideButton(widget.localLabel, true),
                      _sideButton(widget.remoteLabel, false),
                    ],
                    Flexible(child: queueButton),
                  ]),
                ),
              ),
              if (_showQueue && bottomQueue)
                SizedBox(
                  height: (bounds.maxHeight * .24).clamp(100.0, 200.0),
                  child: widget.queue,
                ),
            ]),
          );
        },
      );
}
