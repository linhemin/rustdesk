import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

class WorkspaceDestination {
  const WorkspaceDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The master window keeps a single instance of each session workspace.
class WorkspaceNavigation extends StatelessWidget {
  const WorkspaceNavigation(
      {super.key,
      required this.brand,
      required this.mark,
      required this.destinations,
      required this.current,
      required this.onSelect,
      required this.child,
      this.settings,
      this.onSettings});
  final String brand;
  final Widget mark;
  final List<WorkspaceDestination> destinations;
  final int current;
  final ValueChanged<int> onSelect;
  final String? settings;
  final VoidCallback? onSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final inkDefault = theme.colorScheme.onSurface;
        final muted = theme.hintColor;
        final wide = bounds.maxWidth >= 740;
        final railWidth = !wide ? 64.0 : bounds.maxWidth < 950 ? 184.0 : 216.0;
        Widget item(
            String label, IconData icon, bool selected, VoidCallback action) {
          final ink = selected ? primary : WorkspaceStyle.tertiaryInk(context);
          return Semantics(
              selected: selected,
              button: true,
              label: label,
              child: Tooltip(
                  message: wide ? '' : label,
                  child: Material(
                      color: selected ? theme.cardColor : Colors.transparent,
                      shape: RoundedRectangleBorder(
                          side: BorderSide(
                              color: selected
                                  ? theme.dividerColor
                                  : Colors.transparent),
                          borderRadius: BorderRadius.circular(8)),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: action,
                          child: ExcludeSemantics(
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: wide ? 12 : 0, vertical: 10),
                                  child: Row(
                                      mainAxisAlignment: wide
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        Icon(icon, size: 17, color: ink),
                                        if (wide) ...[
                                          const SizedBox(width: 11),
                                          Expanded(
                                              child: Text(label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      color: selected
                                                          ? inkDefault
                                                          : muted,
                                                      fontSize: 13,
                                                      fontWeight: selected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500))),
                                        ]
                                      ])))))));
        }

        return Row(children: [
          Container(
              width: railWidth,
              decoration: BoxDecoration(
                color: WorkspaceStyle.sidebarColor(context),
                border: BorderDirectional(
                    end: BorderSide(color: theme.dividerColor)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding: EdgeInsets.fromLTRB(
                            wide ? 16 : 16, 18, wide ? 12 : 16, 18),
                        child: Row(children: [
                          SizedBox.square(dimension: 28, child: mark),
                          if (wide) ...[
                            const SizedBox(width: 9),
                            Expanded(
                                child: Text(brand,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: inkDefault,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        letterSpacing: -.4)))
                          ]
                        ])),
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            children: [
                          for (var i = 0; i < destinations.length; i++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: item(
                                    destinations[i].label,
                                    destinations[i].icon,
                                    i == current,
                                    () => onSelect(i))),
                        ])),
                    if (onSettings != null && settings != null) ...[
                      Divider(
                          color: theme.dividerColor,
                          height: 1,
                          indent: 12,
                          endIndent: 12),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                          child: item(settings!, Icons.tune_rounded,
                              current == destinations.length, onSettings!)),
                    ],
                  ])),
          Expanded(child: child),
        ]);
      });
}

class SessionModePicker extends StatelessWidget {
  const SessionModePicker(
      {super.key,
      required this.choices,
      required this.selected,
      required this.onSelect});
  final List<WorkspaceDestination> choices;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, bounds) {
      Widget choice(int index) {
        final active = index == selected;
        final color = active ? theme.colorScheme.primary : theme.hintColor;
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        return Semantics(
          selected: active,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: Duration(milliseconds: reducedMotion ? 0 : 140),
              decoration: BoxDecoration(
                color: active ? theme.cardColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: active
                    ? Border.all(color: theme.dividerColor)
                    : Border.all(color: Colors.transparent),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(choices[index].icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(choices[index].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w500,
                            color: active
                                ? theme.colorScheme.onSurface
                                : theme.hintColor))),
              ]),
            ),
          ),
        );
      }

      return Material(
          color: Colors.transparent,
          child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: WorkspaceStyle.elevatedSurface(context),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: theme.dividerColor)),
              child: Wrap(spacing: bounds.maxWidth >= 640 ? 4 : 2, children: [
                for (var i = 0; i < choices.length; i++) choice(i)
              ])));
    });
  }
}
