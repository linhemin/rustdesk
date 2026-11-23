import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:settings_ui/settings_ui.dart';

/// Unified inset-grouped settings list shared across iOS and Android.
class AppleSettingsList extends StatelessWidget {
  const AppleSettingsList({super.key, required this.sections});

  final List<AbstractSettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIOS = theme.platform == TargetPlatform.iOS;
    final gutter = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
          gutter, 8, gutter, MediaQuery.paddingOf(context).bottom + 28),
      children: [
        for (final section in sections)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: section is SettingsSection
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (section.title != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  14, 2, 14, 6),
                              child: Semantics(
                                header: true,
                                child: DefaultTextStyle(
                                  style: theme.textTheme.labelMedium!.copyWith(
                                    fontSize: 12,
                                    letterSpacing: isIOS ? 0.2 : 0,
                                    color: isIOS
                                        ? WorkspaceStyle.tertiaryInk(context)
                                        : theme.colorScheme.primary,
                                    fontWeight: isIOS
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                  ),
                                  child: section.title!,
                                ),
                              ),
                            ),
                          Material(
                            color: theme.cardColor,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: isIOS
                                    ? Colors.transparent
                                    : theme.dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(children: [
                              for (final (index, tile)
                                  in section.tiles.indexed) ...[
                                if (index > 0)
                                  Divider(
                                    indent: tile is SettingsTile &&
                                            tile.leading != null
                                        ? 56
                                        : 16,
                                    height: 1,
                                    thickness: 0.6,
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

Color _tileTintForLeading(Widget leading, Color fallback) {
  if (leading is Icon) {
    final code = leading.icon?.codePoint;
    if (code == Icons.security.codePoint ||
        code == Icons.lock.codePoint ||
        code == Icons.lock_outline.codePoint ||
        code == Icons.verified_user.codePoint ||
        code == Icons.verified_user_outlined.codePoint ||
        code == Icons.power_settings_new.codePoint ||
        code == Icons.battery_saver.codePoint ||
        code == Icons.phonelink_lock.codePoint) {
      return WorkspaceStyle.green;
    }
    if (code == Icons.language.codePoint ||
        code == Icons.translate.codePoint ||
        code == Icons.display_settings.codePoint ||
        code == Icons.desktop_windows.codePoint ||
        code == Icons.desktop_windows_outlined.codePoint ||
        code == Icons.monitor.codePoint ||
        code == Icons.edit_note.codePoint) {
      return WorkspaceStyle.amber;
    }
    if (code == Icons.dark_mode.codePoint ||
        code == Icons.light_mode.codePoint ||
        code == Icons.brightness_6.codePoint ||
        code == Icons.palette.codePoint ||
        code == Icons.palette_outlined.codePoint ||
        code == Icons.person.codePoint ||
        code == Icons.person_outline.codePoint ||
        code == Icons.account_circle.codePoint) {
      return WorkspaceStyle.indigo;
    }
    if (code == Icons.videocam.codePoint ||
        code == Icons.videocam_outlined.codePoint ||
        code == Icons.fiber_manual_record.codePoint ||
        code == Icons.memory.codePoint ||
        code == Icons.developer_board.codePoint) {
      return WorkspaceStyle.red;
    }
    if (code == Icons.layers.codePoint ||
        code == Icons.picture_in_picture.codePoint ||
        code == Icons.auto_awesome.codePoint ||
        code == Icons.tune.codePoint) {
      return WorkspaceStyle.purple;
    }
    if (code == Icons.info.codePoint ||
        code == Icons.info_outline.codePoint ||
        code == Icons.fingerprint.codePoint ||
        code == Icons.keyboard.codePoint ||
        code == Icons.keyboard_outlined.codePoint ||
        code == Icons.description.codePoint ||
        code == Icons.description_outlined.codePoint) {
      return WorkspaceStyle.neutralTile;
    }
  }
  return fallback;
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.tile});

  final SettingsTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSwitch = tile.tileType == SettingsTileType.switchTile;
    final canToggle = tile.enabled && tile.onToggle != null;
    final onPressed = tile.enabled ? tile.onPressed : null;
    final inlineValue = tile.value != null &&
        !isSwitch &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.3;
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
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              if (tile.leading != null) ...[
                Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        _tileTintForLeading(tile.leading!, WorkspaceStyle.blue),
                    borderRadius: BorderRadius.circular(7.5),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.16),
                      width: 0.5,
                    ),
                  ),
                  child: IconTheme.merge(
                    data: const IconThemeData(size: 17, color: Colors.white),
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
                    for (final secondary in [
                      if (!inlineValue) tile.value,
                      tile.description,
                    ].whereType<Widget>())
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: DefaultTextStyle(
                          style: theme.textTheme.bodySmall!
                              .copyWith(color: theme.hintColor),
                          child: secondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (inlineValue) ...[
                const SizedBox(width: 8),
                Flexible(
                    child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: WorkspaceStyle.tertiaryInk(context)),
                  child: tile.value!,
                )),
              ],
              if (tile.trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme.merge(
                    data: IconThemeData(color: theme.hintColor, size: 17),
                    child: tile.trailing!),
              ] else if (isSwitch) ...[
                const SizedBox(width: 12),
                CupertinoSwitch(
                  value: tile.initialValue ?? false,
                  onChanged: canToggle ? (v) => tile.onToggle!(v) : null,
                  activeColor:
                      tile.activeSwitchColor ?? theme.colorScheme.primary,
                ),
              ] else if (onPressed != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: theme.hintColor.withOpacity(0.75), size: 20),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
