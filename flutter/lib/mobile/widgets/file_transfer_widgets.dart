import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

class MobileFileIcon extends StatelessWidget {
  const MobileFileIcon(
      {super.key,
      required this.name,
      this.directory = false,
      this.drive = false});

  final String name;
  final bool directory;
  final bool drive;

  @override
  Widget build(BuildContext context) {
    final extension = name.toLowerCase().split('.').last;
    final (icon, color) = directory
        ? (Icons.folder_outlined, WorkspaceStyle.warning(context))
        : drive
            ? (Icons.storage_rounded, Theme.of(context).colorScheme.primary)
            : switch (extension) {
                'mp4' || 'mov' || 'mkv' || 'avi' => (
                    Icons.videocam_outlined,
                    WorkspaceStyle.information(context)
                  ),
                'zip' || 'tar' || 'gz' || '7z' || 'rar' => (
                    Icons.inventory_2_outlined,
                    WorkspaceStyle.success(context)
                  ),
                'json' ||
                'yaml' ||
                'yml' ||
                'toml' ||
                'rs' ||
                'dart' ||
                'ts' ||
                'js' ||
                'py' ||
                'pub' ||
                'key' ||
                'pem' ||
                'sh' =>
                  (Icons.code_rounded, Theme.of(context).colorScheme.primary),
                'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => (
                    Icons.image_outlined,
                    WorkspaceStyle.indigo
                  ),
                'pdf' || 'doc' || 'docx' || 'txt' || 'md' => (
                    Icons.description_outlined,
                    WorkspaceStyle.danger(context)
                  ),
                _ => (
                    Icons.insert_drive_file_outlined,
                    Theme.of(context).hintColor
                  ),
              };
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

class MobileFileLocationFooter extends StatelessWidget {
  const MobileFileLocationFooter(
      {super.key, required this.path, required this.summary});

  final String path;
  final String summary;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(
            message: path,
            child: Text(path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: WorkspaceStyle.tertiaryInk(context))),
          ),
          const SizedBox(height: 4),
          Text(summary,
              style: TextStyle(
                  fontSize: 10, color: WorkspaceStyle.tertiaryInk(context))),
        ]),
      );
}

class MobileTransferPill extends StatelessWidget {
  const MobileTransferPill(
      {super.key,
      required this.label,
      required this.detail,
      required this.expanded,
      required this.onToggle,
      this.active = false});

  final String label;
  final String detail;
  final bool expanded;
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.dividerColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        active ? theme.colorScheme.primary : theme.hintColor)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500))),
            if (detail.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                  child: Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()]))),
            ],
            Icon(expanded ? Icons.expand_more : Icons.expand_less,
                size: 14, color: theme.colorScheme.primary),
          ]),
        ),
      ),
    );
  }
}
