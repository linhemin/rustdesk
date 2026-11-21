import 'package:flutter/material.dart';

import '../../common.dart';
import '../../models/input_model.dart';
import 'session_controls.dart';

enum SessionModifier { ctrl, shift, alt, meta }

enum _KeyboardPage { keys, function, shortcuts }

typedef SessionShortcut = void Function(SessionModifier modifier, String key);
typedef _RemoteKey = (String, String);

const _editKeys = <_RemoteKey>[
  ('Esc', 'VK_ESCAPE'),
  ('Tab', 'VK_TAB'),
  ('Home', 'VK_HOME'),
  ('End', 'VK_END'),
  ('Ins', 'VK_INSERT'),
  ('Del', 'VK_DELETE'),
  ('PgUp', 'VK_PRIOR'),
  ('PgDn', 'VK_NEXT'),
];

const _navigation = <_RemoteKey>[
  ('←', 'VK_LEFT'),
  ('↑', 'VK_UP'),
  ('↓', 'VK_DOWN'),
  ('→', 'VK_RIGHT'),
];

class SessionKeyboard extends StatefulWidget {
  const SessionKeyboard({
    super.key,
    required this.compact,
    required this.isMac,
    required this.showMouseButtons,
    required this.enabled,
    required this.modifiers,
    required this.onModifier,
    required this.onKey,
    required this.onMouse,
    required this.onShortcut,
    required this.onTextInput,
    required this.onClose,
  });

  final bool compact;
  final bool isMac;
  final bool showMouseButtons;
  final bool enabled;
  final Set<SessionModifier> modifiers;
  final ValueChanged<SessionModifier> onModifier;
  final ValueChanged<String> onKey;
  final ValueChanged<MouseButtons> onMouse;
  final SessionShortcut onShortcut;
  final VoidCallback onTextInput;
  final VoidCallback onClose;

  @override
  State<SessionKeyboard> createState() => _SessionKeyboardState();
}

class _SessionKeyboardState extends State<SessionKeyboard> {
  _KeyboardPage _page = _KeyboardPage.keys;

  Widget _key(String label, VoidCallback action,
      {bool active = false, double width = 44, String? description}) {
    final button = SizedBox(
      width: width,
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          foregroundColor: active ? const Color(0xFF101725) : sessionControlInk,
          disabledForegroundColor: sessionControlInk.withOpacity(.4),
          backgroundColor:
              active ? sessionControlAccent : const Color(0xFF303E54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: widget.enabled ? action : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4, bottom: 4),
      child: description == null
          ? button
          : Tooltip(message: translate(description), child: button),
    );
  }

  Widget _row(Widget child) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: child,
      );

  Widget _remoteKeys(Iterable<_RemoteKey> keys,
          {double width = 44, bool uniform = false}) =>
      _row(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, code) in keys)
            _key(label, () => widget.onKey(code),
                width: uniform || label.length <= 3 ? width : 56),
        ],
      ));

  Widget _modifiers(bool dense, {bool includeMouse = true}) => _row(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (modifier, label) in [
            (SessionModifier.ctrl, 'Ctrl'),
            (SessionModifier.shift, 'Shift'),
            (SessionModifier.alt, 'Alt'),
            (SessionModifier.meta, widget.isMac ? 'Cmd' : 'Win'),
          ])
            _key(label, () => widget.onModifier(modifier),
                active: widget.modifiers.contains(modifier),
                width: dense ? 38 : 46),
          if (includeMouse && widget.showMouseButtons) ...[
            const SizedBox(width: 4),
            _key('L', () => widget.onMouse(MouseButtons.left),
                width: dense ? 34 : 44, description: 'Left button'),
            _key('M', () => widget.onMouse(MouseButtons.wheel),
                width: dense ? 34 : 44, description: 'Middle mouse button'),
            _key('R', () => widget.onMouse(MouseButtons.right),
                width: dense ? 34 : 44, description: 'Right button'),
          ],
        ],
      ));

  List<_RemoteKey> _letters(String row) =>
      row.split('').map((letter) => (letter, 'VK_$letter')).toList();

  List<Widget> _rows(double availableWidth) {
    double fit(int count) =>
        (availableWidth / count - 4).clamp(28, 44).toDouble();
    switch (_page) {
      case _KeyboardPage.keys:
        return [
          for (final row in [
            '1234567890',
            'QWERTYUIOP',
            'ASDFGHJKL',
            'ZXCVBNM'
          ])
            _remoteKeys(_letters(row), width: fit(10)),
          _remoteKeys(
            const [
              ('Esc', 'VK_ESCAPE'),
              ('Tab', 'VK_TAB'),
              ('Space', 'VK_SPACE'),
              ('Bksp', 'VK_BACK'),
              ('Enter', 'VK_RETURN'),
              ..._navigation,
            ],
            width: fit(9),
            uniform: true,
          ),
        ];
      case _KeyboardPage.function:
        return [
          for (final start in [1, 7])
            _remoteKeys([
              for (var i = start; i < start + 6; i++) ('F$i', 'VK_F$i'),
            ]),
          _remoteKeys(_editKeys),
          _remoteKeys([
            ..._navigation,
            ('Caps', 'VK_CAPITAL'),
            if (!widget.isMac) ...const [
              ('PrtSc', 'VK_SNAPSHOT'),
              ('ScrLk', 'VK_SCROLL'),
              ('Pause', 'VK_PAUSE'),
              ('Menu', 'Apps'),
            ],
          ]),
          _remoteKeys(const [
            ('-', 'VK_MINUS'),
            ('=', 'VK_PLUS'),
            ('[', 'VK_LBRACKET'),
            (']', 'VK_RBRACKET'),
            (';', 'VK_SEMICOLON'),
            ("'", 'VK_QUOTE'),
            (r'\', 'VK_BACKSLASH'),
            (',', 'VK_COMMA'),
            ('.', '.'),
            ('/', 'VK_SLASH'),
          ]),
        ];
      case _KeyboardPage.shortcuts:
        final primary =
            widget.isMac ? SessionModifier.meta : SessionModifier.ctrl;
        final label = widget.isMac ? '⌘' : 'Ctrl';
        return [
          _row(Row(
            children: [
              for (final key in ['C', 'V', 'X', 'Z', 'A', 'S'])
                _key('$label+$key', () => widget.onShortcut(primary, 'VK_$key'),
                    width: 64),
            ],
          )),
          _row(Row(
            children: [
              if (widget.isMac)
                _key('⌘+Tab',
                    () => widget.onShortcut(SessionModifier.meta, 'VK_TAB'),
                    width: 72)
              else ...[
                _key('Alt+Tab',
                    () => widget.onShortcut(SessionModifier.alt, 'VK_TAB'),
                    width: 72),
                _key('Win+D',
                    () => widget.onShortcut(SessionModifier.meta, 'VK_D'),
                    width: 72),
              ],
            ],
          )),
        ];
    }
  }

  Widget _compactBar() {
    final primary = widget.isMac ? SessionModifier.meta : SessionModifier.ctrl;
    final prefix = widget.isMac ? 'Cmd' : 'Ctrl';
    return Row(
      children: [
        PopupMenuButton<_RemoteKey>(
          tooltip: translate('Shortcuts'),
          enabled: widget.enabled,
          icon: const Icon(Icons.bolt_outlined, color: sessionControlAccent),
          itemBuilder: (context) => [
            for (final letter in ['C', 'V', 'X', 'Z', 'A', 'S'])
              PopupMenuItem<_RemoteKey>(
                value: ('', 'VK_$letter'),
                child: Text('$prefix+$letter'),
              ),
            const PopupMenuDivider(),
            for (final (label, key) in const [
              ('Esc', 'VK_ESCAPE'),
              ('Tab', 'VK_TAB'),
              ..._navigation,
              ('Enter', 'VK_RETURN'),
            ])
              PopupMenuItem<_RemoteKey>(
                  value: (label, key), child: Text(label)),
          ],
          onSelected: (entry) {
            final (label, key) = entry;
            if (label.isEmpty) {
              widget.onShortcut(primary, key);
            } else {
              widget.onKey(key);
            }
          },
        ),
        Expanded(child: _modifiers(true, includeMouse: false)),
        IconButton(
          tooltip: translate('Input keyboard'),
          onPressed: widget.onTextInput,
          color: sessionControlAccent,
          icon: const Icon(Icons.dialpad),
        ),
        IconButton(
          tooltip: translate('Exit keyboard'),
          onPressed: widget.onClose,
          color: sessionControlInk,
          icon: const Icon(Icons.keyboard_hide),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SessionControlsSurface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: widget.compact
              ? SingleChildScrollView(child: _compactBar())
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _row(Row(
                                children: [
                                  for (final (page, label) in [
                                    (_KeyboardPage.keys, 'ABC'),
                                    (_KeyboardPage.function, 'F1–F12'),
                                    (_KeyboardPage.shortcuts, 'Shortcuts'),
                                  ])
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: page == _page
                                            ? sessionControlAccent
                                            : sessionControlInk,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                      ),
                                      onPressed: () =>
                                          setState(() => _page = page),
                                      child:
                                          Text(translate(label), maxLines: 1),
                                    ),
                                ],
                              )),
                            ),
                            IconButton(
                              tooltip: translate('Local keyboard'),
                              onPressed: widget.onTextInput,
                              color: sessionControlAccent,
                              icon: const Icon(Icons.keyboard),
                            ),
                            IconButton(
                              tooltip: translate('Exit keyboard'),
                              onPressed: widget.onClose,
                              color: sessionControlInk,
                              icon: const Icon(Icons.keyboard_hide),
                            ),
                          ],
                        ),
                        _modifiers(constraints.maxWidth < 352),
                        ..._rows(constraints.maxWidth),
                      ],
                    ),
                  ),
                ),
        ),
      );
}
