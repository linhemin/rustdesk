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
          child: Row(children: [
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
            IconButton(
                tooltip: copyLabel,
                color: const Color(0xff94a3b8),
                iconSize: 17,
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined)),
            IconButton(
                tooltip: pasteLabel,
                color: const Color(0xff94a3b8),
                iconSize: 17,
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded)),
            IconButton(
                tooltip: closeLabel,
                color: const Color(0xfff87171),
                iconSize: 17,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded)),
          ]),
        ),
      );
}
