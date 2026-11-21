import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/widgets/workspace.dart';

const sessionControlSurface = WorkspaceStyle.nightSurface;
const sessionControlInk = Color(0xFFE8EDF7);
const sessionControlAccent = Color(0xFFA5B4FC);

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
  Widget build(BuildContext context) => Theme(
        // Session tools stay dark against arbitrary remote desktop imagery.
        data: WorkspaceStyle.apply(ThemeData.dark(useMaterial3: false)),
        child: MobileSessionSurface(child: child),
      );
}

class SessionControlsDock extends StatefulWidget {
  const SessionControlsDock({
    super.key,
    required this.mode,
    required this.showInputModes,
    required this.onMode,
    required this.virtualMouseEnabled,
    required this.onToggleVirtualMouse,
    required this.onGestureSettings,
    required this.onKeyboard,
    required this.onCenterCursor,
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
  final VoidCallback? onCenterCursor;
  final List<SessionAction> actions;
  final ValueChanged<SessionAction> onAction;

  @override
  State<SessionControlsDock> createState() => _SessionControlsDockState();
}

class _SessionControlsDockState extends State<SessionControlsDock> {
  bool _expanded = false;

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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expanded) ..._actions(),
              IconButton(
                tooltip:
                    translate(_expanded ? 'Collapse toolbar' : 'Show Toolbar'),
                onPressed: () => setState(() => _expanded = !_expanded),
                color: sessionControlAccent,
                icon: Icon(_expanded ? Icons.close : Icons.widgets_outlined),
              ),
            ],
          ),
        ),
      );

  List<Widget> _actions() => [
        if (widget.showInputModes)
          PopupMenuButton<SessionInputMode>(
            tooltip: translate(widget.mode.label),
            color: sessionControlSurface,
            icon: Icon(widget.mode.icon, color: sessionControlAccent),
            onSelected: widget.onMode,
            itemBuilder: (context) => [
              for (final choice in SessionInputMode.values)
                _item(choice, choice.label, choice.icon,
                    selected: choice == widget.mode),
              const PopupMenuDivider(),
              PopupMenuItem<SessionInputMode>(
                onTap: widget.onGestureSettings,
                child: Text(translate('Gesture guide'),
                    style: const TextStyle(color: sessionControlInk)),
              ),
            ],
          ),
        if (widget.onToggleVirtualMouse != null)
          IconButton(
            tooltip: translate(widget.virtualMouseEnabled
                ? 'Hide virtual mouse'
                : 'Show virtual mouse'),
            isSelected: widget.virtualMouseEnabled,
            onPressed: widget.onToggleVirtualMouse,
            color: sessionControlInk,
            icon: const Icon(Icons.mouse_outlined),
            selectedIcon: const Icon(Icons.mouse, color: sessionControlAccent),
          ),
        if (widget.onCenterCursor != null)
          IconButton(
            tooltip: translate('Center cursor'),
            onPressed: widget.onCenterCursor,
            color: sessionControlInk,
            icon: const Icon(Icons.center_focus_strong),
          ),
        if (widget.onKeyboard != null)
          IconButton(
            tooltip: translate('Keyboard'),
            onPressed: widget.onKeyboard,
            color: sessionControlInk,
            icon: const Icon(Icons.keyboard_outlined),
          ),
        PopupMenuButton<SessionAction>(
          tooltip: translate('More'),
          color: sessionControlSurface,
          icon: const Icon(Icons.more_horiz, color: sessionControlInk),
          onSelected: widget.onAction,
          itemBuilder: (context) => [
            for (final action in widget.actions)
              _item(action, action.label, action.icon,
                  destructive: action == SessionAction.disconnect),
          ],
        ),
      ];
}
