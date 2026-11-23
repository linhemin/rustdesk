import 'package:flutter/material.dart';

class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.peer,
    required this.copyLabel,
    required this.pasteLabel,
    required this.closeLabel,
    required this.onCopy,
    required this.onPaste,
    required this.onClose,
  });

  final String peer;
  final String copyLabel;
  final String pasteLabel;
  final String closeLabel;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xff11141b),
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x1affffff)))),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(builder: (context, bounds) {
            final platform = Theme.of(context).platform;
            final showLabels = const {
                  TargetPlatform.macOS,
                  TargetPlatform.windows,
                  TargetPlatform.linux,
                }.contains(platform) &&
                bounds.maxWidth >= 560 &&
                MediaQuery.textScalerOf(context).scale(12) <= 18;
            Widget action(String label, IconData icon, Color color,
                    VoidCallback onPressed) =>
                showLabels
                    ? Tooltip(
                        message: label,
                        child: TextButton.icon(
                            onPressed: onPressed,
                            style: TextButton.styleFrom(foregroundColor: color),
                            icon: Icon(icon, size: 16),
                            label: Text(label)))
                    : IconButton(
                        tooltip: label,
                        color: color,
                        iconSize: 17,
                        onPressed: onPressed,
                        icon: Icon(icon));
            return Row(children: [
              const Icon(Icons.terminal_rounded,
                  size: 16, color: Color(0xff94a3b8)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(peer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xffe6edf3),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              action(copyLabel, Icons.copy_outlined, const Color(0xff94a3b8),
                  onCopy),
              action(pasteLabel, Icons.content_paste_rounded,
                  const Color(0xff94a3b8), onPaste),
              action(closeLabel, Icons.close_rounded, const Color(0xfff87171),
                  onClose),
            ]);
          }),
        ),
      );
}
