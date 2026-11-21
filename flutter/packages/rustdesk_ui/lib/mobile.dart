import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Grouped mobile content, shared with the bridge-free phone catalog.
class MobileWorkspaceSection extends StatelessWidget {
  const MobileWorkspaceSection(
      {super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).hintColor, fontSize: 12)),
          ),
          WorkspacePanel(padding: EdgeInsets.zero, child: child),
        ],
      );
}

class MobileSessionSurface extends StatelessWidget {
  const MobileSessionSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).cardColor,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(.18),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );
}

class MobileChatHeader extends StatelessWidget {
  const MobileChatHeader(
      {super.key,
      required this.title,
      required this.onMinimize,
      required this.onClose,
      this.minimizeLabel,
      this.closeLabel});
  final String title;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final String? minimizeLabel;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(children: [
          const WorkspaceIcon(
              icon: Icons.chat_bubble_outline_rounded, size: 36),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
              tooltip: minimizeLabel,
              onPressed: onMinimize,
              icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          IconButton(
              tooltip: closeLabel,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded)),
        ]),
      );
}

class MobileWorkspaceDialogTheme extends StatelessWidget {
  const MobileWorkspaceDialogTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
            dialogTheme: Theme.of(context).dialogTheme.copyWith(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: Theme.of(context).dividerColor)),
                )),
        child: child,
      );
}

class MobileWorkspaceDialog extends StatelessWidget {
  const MobileWorkspaceDialog(
      {super.key,
      required this.title,
      required this.content,
      this.actions = const []});
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => MobileWorkspaceDialogTheme(
          child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.all(16),
        scrollable: true,
        title: title,
        content: content,
        actions: actions,
      ));
}
