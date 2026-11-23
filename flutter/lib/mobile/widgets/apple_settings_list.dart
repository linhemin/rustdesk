import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:settings_ui/settings_ui.dart';

/// Unified inset-grouped settings list shared across iOS and Android.
class AppleSettingsList extends StatelessWidget {
  const AppleSettingsList({
    super.key,
    required this.sections,
    this.header,
    this.leading = const [],
    this.searchQuery = '',
  });

  final List<AbstractSettingsSection> sections;
  final Widget? header;
  final List<Widget> leading;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIOS = theme.platform == TargetPlatform.iOS;
    final gutter = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, 8, gutter,
          MediaQuery.paddingOf(context).bottom + (isIOS ? 112 : 28)),
      children: [
        for (final section in [
          if (header != null) CustomSettingsSection(child: header!),
          for (final child in leading) CustomSettingsSection(child: child),
          ..._matchingSections(sections, searchQuery),
        ])
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

Iterable<AbstractSettingsSection> _matchingSections(
    List<AbstractSettingsSection> sections, String query) sync* {
  query = query.trim().toLowerCase();
  for (final section in sections) {
    if (query.isEmpty) {
      yield section;
    } else if (section is SettingsSection) {
      final groupMatches = _settingsText(section.title).contains(query);
      final tiles = section.tiles
          .where((tile) =>
              groupMatches ||
              tile is SettingsTile &&
                  [tile.title, tile.value, tile.description]
                      .any((label) => _settingsText(label).contains(query)))
          .toList();
      if (tiles.isNotEmpty) {
        yield SettingsSection(title: section.title, tiles: tiles);
      }
    }
  }
}

String _settingsText(Widget? widget) {
  if (widget is Text) {
    return (widget.data ?? widget.textSpan?.toPlainText() ?? '').toLowerCase();
  }
  if (widget is Flex) return widget.children.map(_settingsText).join(' ');
  if (widget is Padding) return _settingsText(widget.child);
  return '';
}

class AppleSettingsHeader extends StatelessWidget {
  const AppleSettingsHeader(
      {super.key,
      required this.title,
      required this.searchHint,
      required this.controller,
      required this.onSearch,
      this.scan});

  final String title;
  final String searchHint;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final Widget? scan;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6))),
            if (scan != null)
              Material(
                  color: Theme.of(context).cardColor,
                  shape: const CircleBorder(),
                  child: scan!),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: onSearch,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search, size: 17),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              isDense: true,
              filled: true,
              fillColor: WorkspaceStyle.elevatedSurface(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
      );
}

class AppleSettingsAccountCard extends StatelessWidget {
  const AppleSettingsAccountCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.avatar,
      required this.onTap});

  final String title;
  final String subtitle;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                      width: 54,
                      height: 54,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [Color(0xff0a84ff), Color(0xff5e5ce6)])),
                      alignment: Alignment.center,
                      child: avatar),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: WorkspaceStyle.tertiaryInk(context))),
                      ])),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: WorkspaceStyle.tertiaryInk(context)),
                ]),
              )),
        ),
      );
}

class AppleSettingsField extends StatelessWidget {
  const AppleSettingsField(
      {super.key,
      required this.label,
      required this.controller,
      this.error,
      this.enabled = true});

  final String label;
  final TextEditingController controller;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 14.5))),
          const SizedBox(width: 8),
          Expanded(
              child: Semantics(
                  label: label,
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w400),
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    enableIMEPersonalizedLearning: false,
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                    decoration: InputDecoration(
                      errorText: error?.isEmpty == true ? null : error,
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ))),
        ]),
      );
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
        code == Icons.phonelink_lock.codePoint ||
        code == Icons.public.codePoint) {
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
        code == Icons.nightlight_round.codePoint ||
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
                        fontSize:
                            theme.platform == TargetPlatform.iOS ? 14.5 : null,
                        color: titleColor,
                        fontWeight: theme.platform == TargetPlatform.iOS
                            ? FontWeight.w400
                            : FontWeight.w500,
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
