import 'package:flutter/material.dart';

import 'package:rustdesk_ui/rustdesk_ui.dart';

/// Desktop settings groups use the same width as the category heading.
class WorkspaceSettingsSection extends StatelessWidget {
  const WorkspaceSettingsSection(
      {super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  ...?trailing,
                ]),
              ),
              if (children.isNotEmpty)
                WorkspacePanel(
                  radius: 14,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceSettingsNavItem extends StatelessWidget {
  const WorkspaceSettingsNavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tileColor,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final tileTint = tileColor ?? accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 3),
      child: Material(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              WorkspaceIconTile(
                icon: icon,
                color: selected ? Colors.white.withOpacity(0.22) : tileTint,
                size: 22,
                radius: 6,
                iconSize: 13,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class WorkspaceSettingsHeader extends StatelessWidget {
  const WorkspaceSettingsHeader({
    super.key,
    required this.title,
    required this.icon,
    this.tileColor,
  });
  final String title;
  final IconData icon;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Row(children: [
            WorkspaceIconTile(
              icon: icon,
              color: tileColor ?? theme.colorScheme.primary,
              size: 34,
              radius: 9,
              iconSize: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class WorkspaceSettingsChoice extends StatelessWidget {
  const WorkspaceSettingsChoice(
      {super.key,
      required this.value,
      required this.options,
      this.fallback,
      this.onChanged});
  final String value;
  final String? fallback;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.containsKey(value) ? value : null,
            hint: fallback == null
                ? null
                : Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(fallback!)),
            isExpanded: true,
            isDense: true,
            alignment: AlignmentDirectional.centerEnd,
            style: Theme.of(context).textTheme.bodyMedium,
            borderRadius: BorderRadius.circular(12),
            selectedItemBuilder: (context) => [
              for (final label in options.values)
                Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            items: [
              for (final item in options.entries)
                DropdownMenuItem(
                    value: item.key,
                    child: Text(item.value,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged == null
                ? null
                : (key) {
                    if (key != null && key != value) onChanged!(key);
                  },
          ),
        ),
      );
}
