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
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: WorkspacePanel(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleMedium)),
                      ...?trailing,
                    ]),
                    if (children.isNotEmpty) const SizedBox(height: 10),
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
              ? Theme.of(context).colorScheme.primary.withOpacity(.12)
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
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Row(children: [
          WorkspaceIcon(icon: icon, size: 44),
          const SizedBox(width: 14),
          Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.headlineSmall)),
        ]),
      );
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
