import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Device identity and actions shared by the home and device-library views.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.name,
    required this.remoteId,
    required this.platform,
    required this.platformIcon,
    required this.online,
    required this.status,
    required this.actions,
    this.details = '',
    this.note = '',
    this.tags = const [],
    this.grid = false,
    this.selected = false,
    this.passwordSaved = false,
  });

  final String name;
  final String remoteId;
  final String platform;
  final IconData platformIcon;
  final bool online;
  final String status;
  final List<Widget> actions;
  final String details;
  final String note;
  final List<String> tags;
  final bool grid;
  final bool selected;
  final bool passwordSaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = online
        ? WorkspaceStyle.success(context)
        : WorkspaceStyle.tertiaryInk(context);
    final icon = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: online
            ? WorkspaceStyle.accentSoft(context)
            : WorkspaceStyle.elevatedSurface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(platformIcon,
          size: 20,
          color: online ? theme.colorScheme.primary : theme.hintColor,
          semanticLabel: platform),
    );
    final identity = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.circle, size: 6, color: statusColor),
          const SizedBox(width: 6),
          Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
          if (passwordSaved) ...[
            const SizedBox(width: 4),
            Icon(Icons.key_rounded, size: 12, color: theme.hintColor),
          ],
        ]),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: remoteId),
            TextSpan(
                text: ' · ${grid && details.isNotEmpty ? details : status}',
                style: TextStyle(color: grid ? theme.hintColor : statusColor)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontFamily: 'monospace',
              color: WorkspaceStyle.tertiaryInk(context)),
        ),
        if (!grid && note.isNotEmpty)
          Text(note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
      ],
    );
    return Tooltip(
      triggerMode: TooltipTriggerMode.manual,
      message: [name, remoteId, details, status, note, ...tags]
          .where((value) => value.isNotEmpty)
          .join(' · '),
      child: Container(
        padding: EdgeInsets.all(grid ? 14 : 12),
        decoration: BoxDecoration(
          color:
              selected ? WorkspaceStyle.accentSoft(context) : theme.cardColor,
          border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.dividerColor),
          borderRadius: BorderRadius.circular(grid ? 12 : 16),
        ),
        child: grid
            ? Column(children: [
                Expanded(
                    child: Row(children: [
                  Expanded(child: identity),
                  const SizedBox(width: 8),
                  icon,
                ])),
                if (note.isNotEmpty)
                  Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall)),
                Divider(height: 18),
                Row(children: [
                  Expanded(
                      child: Text(status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: statusColor))),
                  ...actions,
                ]),
              ])
            : Row(children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: identity),
                ...actions,
              ]),
      ),
    );
  }
}
