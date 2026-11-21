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
        final wide = bounds.maxWidth >= 740;
        final railWidth = !wide ? 64.0 : bounds.maxWidth < 950 ? 174.0 : 188.0;
        Widget item(
            String label, IconData icon, bool selected, VoidCallback action) {
          final ink = selected ? Colors.white : const Color(0xffbbcbdf);
          return Semantics(
              selected: selected,
              button: true,
              label: label,
              child: Tooltip(
                  message: wide ? '' : label,
                  child: Material(
                      color: selected
                          ? const Color(0xff294975)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: action,
                          child: ExcludeSemantics(
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: wide ? 12 : 0, vertical: 13),
                                  child: Row(
                                      mainAxisAlignment: wide
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        Icon(icon, size: 21, color: ink),
                                        if (wide) ...[
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Text(label,
                                                  style: TextStyle(
                                                      color: ink,
                                                      fontSize: 14,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500))),
                                        ]
                                      ])))))));
        }

        return Row(children: [
          SizedBox(
              width: railWidth,
              child: ColoredBox(
                  color: WorkspaceStyle.navy,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: EdgeInsets.fromLTRB(
                                wide ? 18 : 16, 22, wide ? 12 : 16, 24),
                            child: Row(children: [
                              SizedBox.square(dimension: 32, child: mark),
                              if (wide) ...[
                                const SizedBox(width: 9),
                                Expanded(
                                    child: Text(brand,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 19,
                                            letterSpacing: -.6)))
                              ]
                            ])),
                        Expanded(
                            child: ListView(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                children: [
                              for (var i = 0; i < destinations.length; i++)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: item(
                                        destinations[i].label,
                                        destinations[i].icon,
                                        i == current,
                                        () => onSelect(i))),
                            ])),
                        if (onSettings != null && settings != null) ...[
                          const Divider(
                              color: Color(0xff304867),
                              indent: 12,
                              endIndent: 12),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                              child: item(settings!, Icons.tune_rounded,
                                  current == destinations.length, onSettings!)),
                        ],
                      ]))),
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
            borderRadius: BorderRadius.circular(7),
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: Duration(milliseconds: reducedMotion ? 0 : 150),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          width: 2.5,
                          color: active ? color : Colors.transparent))),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(choices[index].icon, size: 18, color: color),
                const SizedBox(width: 7),
                Flexible(
                    child: Text(choices[index].label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                            color: color))),
              ]),
            ),
          ),
        );
      }

      return Material(
          color: Colors.transparent,
          child: DecoratedBox(
              decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: theme.dividerColor))),
              child: Wrap(spacing: bounds.maxWidth >= 640 ? 16 : 3, children: [
                for (var i = 0; i < choices.length; i++) choice(i)
              ])));
    });
  }
}
