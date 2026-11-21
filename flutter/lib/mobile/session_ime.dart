import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef SessionImeEdit = ({int backspaces, String text});

class SessionIme {
  // Leaving one character in the local editor lets the IME report backspace
  // even when it has no text of its own. The marker is never sent to the peer.
  static const _marker = '\u2060';
  static const initialValue = TextEditingValue(
    text: _marker,
    selection: TextSelection.collapsed(offset: 1),
  );

  String _committed = '';

  void reset() => _committed = '';

  SessionImeEdit? update(TextEditingValue value) {
    if (value.isComposingRangeValid && !value.composing.isCollapsed) {
      return null;
    }
    final marked = value.text.startsWith(_marker);
    final text = marked ? value.text.substring(_marker.length) : value.text;
    if (!marked && text.isEmpty && _committed.isEmpty) {
      return (backspaces: 1, text: '');
    }
    if (text == _committed) return null;

    final before = _committed.characters.toList(growable: false);
    final after = text.characters.toList(growable: false);
    var common = 0;
    while (common < before.length &&
        common < after.length &&
        before[common] == after[common]) {
      common++;
    }
    _committed = text;
    return (
      backspaces: before.length - common,
      text: after.skip(common).join(),
    );
  }

  TextEditingValue? restoreMarker(TextEditingValue value) {
    if (value.text.startsWith(_marker) ||
        (value.isComposingRangeValid && !value.composing.isCollapsed)) {
      return null;
    }
    final text = _marker + value.text;
    final selection = value.selection;
    return TextEditingValue(
      text: text,
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset:
                  (selection.baseOffset + 1).clamp(1, text.length).toInt(),
              extentOffset:
                  (selection.extentOffset + 1).clamp(1, text.length).toInt(),
            )
          : TextSelection.collapsed(offset: text.length),
    );
  }
}

bool isSessionImeModifier(LogicalKeyboardKey key) => const [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    ].contains(key);

bool useRemoteSessionKey(
  LogicalKeyboardKey key, {
  required bool composing,
  required bool shortcut,
}) {
  if (shortcut || isSessionImeModifier(key)) return true;
  if (composing) return false;
  return const [
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.insert,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ].contains(key);
}
