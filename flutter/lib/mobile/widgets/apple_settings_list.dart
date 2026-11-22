import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';

/// An inset list shared by the iPhone and iPad settings destinations.
class AppleSettingsList extends StatelessWidget {
  const AppleSettingsList({super.key, required this.sections});

  final List<AbstractSettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gutter = MediaQuery.sizeOf(context).width < 360 ? 14.0 : 20.0;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
          gutter, 8, gutter, MediaQuery.paddingOf(context).bottom + 20),
      children: [
        for (final section in sections)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: section is SettingsSection
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (section.title != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  4, 2, 4, 8),
                              child: Semantics(
                                header: true,
                                child: DefaultTextStyle(
                                  style: theme.textTheme.labelLarge!.copyWith(
                                    color: theme.hintColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  child: section.title!,
                                ),
                              ),
                            ),
                          Material(
                            color: theme.cardColor,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(children: [
                              for (final (index, tile)
                                  in section.tiles.indexed) ...[
                                if (index > 0)
                                  Divider(
                                    indent: tile is SettingsTile &&
                                            tile.leading != null
                                        ? 64
                                        : 16,
                                    height: 1,
                                    thickness: .6,
                                  ),
                                if (tile is SettingsTile)
                                  _SettingsRow(tile: tile)
                                else
                                  tile,
                              ],
                            ]),
                          ),
                        ],
                      ),
                    )
                  : section,
            ),
          ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.tile});

  final SettingsTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isSwitch = tile.tileType == SettingsTileType.switchTile;
    final canToggle = tile.enabled && tile.onToggle != null;
    final onPressed = tile.enabled ? tile.onPressed : null;
    final titleColor = !tile.enabled || (isSwitch && !canToggle)
        ? theme.hintColor
        : theme.colorScheme.onSurface;
    return MergeSemantics(
      child: InkWell(
        onTap: onPressed != null
            ? () => onPressed(context)
            : canToggle
                ? () => tile.onToggle!(!(tile.initialValue ?? false))
                : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              if (tile.leading != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(size: 19, color: primary),
                    child: tile.leading!,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w500,
                      ),
                      child: tile.title,
                    ),
                    for (final secondary
                        in [tile.value, tile.description].whereType<Widget>())
                      DefaultTextStyle(
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: theme.hintColor),
                        child: secondary,
                      ),
                  ],
                ),
              ),
              if (tile.trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme.merge(
                    data: IconThemeData(color: theme.hintColor, size: 16),
                    child: tile.trailing!),
              ] else if (isSwitch) ...[
                const SizedBox(width: 12),
                CupertinoSwitch(
                  value: tile.initialValue ?? false,
                  onChanged: canToggle ? (v) => tile.onToggle!(v) : null,
                  activeColor: tile.activeSwitchColor ?? primary,
                ),
              ] else if (onPressed != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: theme.hintColor, size: 20),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
