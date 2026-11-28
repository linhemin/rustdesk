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
      alignment: AlignmentDirectional.topCenter,
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
                  radius: 12,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        children[i],
                      ],
                    ],
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
        color: selected ? WorkspaceStyle.accentSoft(context) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected
                ? WorkspaceStyle.accentBorder(context)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              WorkspaceIconTile(
                icon: icon,
                color: tileTint,
                size: 20,
                radius: 5.5,
                iconSize: 12,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? accent : theme.colorScheme.onSurface,
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
      alignment: AlignmentDirectional.topCenter,
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

class WorkspaceSettingsThemePicker extends StatelessWidget {
  const WorkspaceSettingsThemePicker({
    super.key,
    required this.value,
    required this.labels,
    this.onChanged,
  });

  final String value;
  final Map<String, String> labels;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final entry in labels.entries)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              selected: value == entry.key,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: value == entry.key
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                    width: value == entry.key ? 2 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed:
                    onChanged == null ? null : () => onChanged!(entry.key),
                child: Column(children: [
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        colors: entry.key == 'system'
                            ? const [Color(0xfff5f6f9), Color(0xff151921)]
                            : List.filled(
                                2,
                                entry.key == 'dark'
                                    ? const Color(0xff151921)
                                    : const Color(0xfff5f6f9)),
                        stops: const [0.5, 0.5],
                      ),
                    ),
                    child: Row(children: [
                      Container(
                          width: 20,
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(.2),
                              borderRadius: BorderRadius.circular(3))),
                      Expanded(
                          child: Container(
                              margin: const EdgeInsets.fromLTRB(0, 6, 6, 6),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3)),
                              child: entry.key == 'system'
                                  ? const Row(children: [
                                      Expanded(
                                          child: ColoredBox(
                                              color: Colors.white,
                                              child: SizedBox.expand())),
                                      Expanded(
                                          child: ColoredBox(
                                              color: Color(0xff262c38),
                                              child: SizedBox.expand())),
                                    ])
                                  : ColoredBox(
                                      color: entry.key == 'dark'
                                          ? const Color(0xff262c38)
                                          : Colors.white,
                                      child: const SizedBox.expand()))),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text(entry.value,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
