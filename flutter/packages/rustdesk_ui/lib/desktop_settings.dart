import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Desktop settings and overlay surfaces, shared with the visual catalog.
class WorkspaceSettingsSection extends StatelessWidget {
  const WorkspaceSettingsSection(
      {super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: WorkspacePanel(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleMedium)),
                      ...?trailing,
                    ]),
                    const SizedBox(height: 16),
                    ...children,
                  ]),
            ),
          ),
        ),
      );
}

class WorkspaceSettingsNavItem extends StatelessWidget {
  const WorkspaceSettingsNavItem(
      {super.key,
      required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Material(
          color: selected
              ? WorkspaceStyle.accent.withOpacity(.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            selected: selected,
            selectedColor: Theme.of(context).colorScheme.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            minLeadingWidth: 20,
            horizontalTitleGap: 12,
            leading: Icon(icon, size: 20),
            title: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            onTap: onTap,
          ),
        ),
      );
}

class WorkspaceSettingsHeader extends StatelessWidget {
  const WorkspaceSettingsHeader(
      {super.key, required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Row(children: [
          WorkspaceIcon(icon: icon, size: 44),
          const SizedBox(width: 14),
          Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.headlineSmall)),
        ]),
      );
}

/// Layout only: callers continue to own focus, validation and native actions.
class WorkspaceDesktopDialog extends StatelessWidget {
  const WorkspaceDesktopDialog(
      {super.key,
      this.title,
      required this.content,
      this.actions,
      this.titlePadding});

  final Widget? title;
  final Widget content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? titlePadding;

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        title: title,
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        titlePadding: titlePadding ?? const EdgeInsets.fromLTRB(28, 28, 28, 0),
        content: content,
        contentTextStyle:
            Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        contentPadding: const EdgeInsets.all(28),
        actions: actions,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        buttonPadding: const EdgeInsets.only(left: 8),
      );
}

class WorkspaceDesktopStyle {
  WorkspaceDesktopStyle._();

  static ThemeData apply(ThemeData base) => base.copyWith(
        popupMenuTheme: base.popupMenuTheme.copyWith(
          color: base.cardColor,
          elevation: 8,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: base.dividerColor)),
          textStyle: base.textTheme.bodyMedium,
        ),
        dialogTheme: base.dialogTheme.copyWith(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: base.dividerColor)),
          titleTextStyle: base.textTheme.titleLarge,
          contentTextStyle: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      );
}
