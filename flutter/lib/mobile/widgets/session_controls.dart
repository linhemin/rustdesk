import 'package:flutter/material.dart';

import '../../common.dart';

const sessionControlSurface = Color(0xF01A242E);
const sessionControlInk = Color(0xFFEDF4F7);
const sessionControlAccent = Color(0xFFA2F4D8);

enum SessionInputMode {
  touch('Touchscreen mode', Icons.touch_app_outlined),
  pointer('Pointer mode', Icons.mouse_outlined);

  const SessionInputMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum SessionAction {
  display('Display Settings', Icons.monitor_outlined),
  chat('Chat', Icons.chat_bubble_outline),
  mobile('Mobile Actions', Icons.smartphone_outlined),
  more('More', Icons.tune),
  disconnect('Disconnect', Icons.link_off);

  const SessionAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SessionControlsSurface extends StatelessWidget {
  const SessionControlsSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: sessionControlSurface,
        elevation: 4,
        shadowColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x4D93A9B8)),
        ),
        child: child,
      );
}

class SessionControlsDock extends StatelessWidget {
  const SessionControlsDock({
    super.key,
    required this.mode,
    required this.showInputModes,
    required this.onMode,
    required this.virtualMouseEnabled,
    required this.onToggleVirtualMouse,
    required this.onGestureSettings,
    required this.onKeyboard,
    required this.actions,
    required this.onAction,
  });

  final SessionInputMode mode;
  final bool showInputModes;
  final ValueChanged<SessionInputMode> onMode;
  final bool virtualMouseEnabled;
  final VoidCallback? onToggleVirtualMouse;
  final VoidCallback onGestureSettings;
  final VoidCallback? onKeyboard;
  final List<SessionAction> actions;
  final ValueChanged<SessionAction> onAction;

  PopupMenuItem<T> _item<T>(T value, String text, IconData icon,
      {bool selected = false, bool destructive = false}) {
    final color = destructive
        ? const Color(0xFFFFB4AE)
        : selected
            ? sessionControlAccent
            : sessionControlInk;
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Text(translate(text), style: TextStyle(color: color))),
          if (selected)
            const Icon(Icons.check, size: 18, color: sessionControlAccent),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SessionControlsSurface(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showInputModes)
              PopupMenuButton<SessionInputMode>(
                tooltip: translate(mode.label),
                color: sessionControlSurface,
                icon: Icon(mode.icon, color: sessionControlAccent),
                onSelected: onMode,
                itemBuilder: (context) => [
                  for (final choice in SessionInputMode.values)
                    _item(choice, choice.label, choice.icon,
                        selected: choice == mode),
                  const PopupMenuDivider(),
                  PopupMenuItem<SessionInputMode>(
                    onTap: onGestureSettings,
                    child: Text(translate('Gesture guide'),
                        style: const TextStyle(color: sessionControlInk)),
                  ),
                ],
              ),
            if (onToggleVirtualMouse != null)
              IconButton(
                tooltip: translate(virtualMouseEnabled
                    ? 'Hide virtual mouse'
                    : 'Show virtual mouse'),
                isSelected: virtualMouseEnabled,
                onPressed: onToggleVirtualMouse,
                color: sessionControlInk,
                icon: const Icon(Icons.mouse_outlined),
                selectedIcon:
                    const Icon(Icons.mouse, color: sessionControlAccent),
              ),
            if (onKeyboard != null)
              IconButton(
                tooltip: translate('Keyboard'),
                onPressed: onKeyboard,
                color: sessionControlInk,
                icon: const Icon(Icons.keyboard_outlined),
              ),
            PopupMenuButton<SessionAction>(
              tooltip: translate('More'),
              color: sessionControlSurface,
              icon: const Icon(Icons.more_horiz, color: sessionControlInk),
              onSelected: onAction,
              itemBuilder: (context) => [
                for (final action in actions)
                  _item(action, action.label, action.icon,
                      destructive: action == SessionAction.disconnect),
              ],
            ),
          ],
        ),
      );
}
