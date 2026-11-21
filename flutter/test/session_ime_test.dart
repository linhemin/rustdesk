import 'package:flutter/services.dart';
import 'package:flutter_hbb/mobile/session_ime.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _value(String text, {TextRange composing = TextRange.empty}) =>
    TextEditingValue(
      text: SessionIme.initialValue.text + text,
      selection: TextSelection.collapsed(offset: text.length + 1),
      composing: composing,
    );

void main() {
  test('IME forwards committed text once even if only composing changes', () {
    final ime = SessionIme();
    expect(ime.update(_value('1')), (backspaces: 0, text: '1'));
    expect(ime.update(_value('1ni', composing: TextRange(start: 2, end: 4))),
        isNull);
    final candidate =
        _value('1你', composing: const TextRange(start: 2, end: 3));
    expect(ime.update(candidate), isNull);
    final committed = candidate.copyWith(composing: TextRange.empty);
    expect(ime.update(committed), (backspaces: 0, text: '你'));
    expect(ime.update(committed), isNull);
  });

  test('IME replacements send the corrected suffix and empty backspaces work',
      () {
    final ime = SessionIme();
    expect(ime.update(_value('()')), (backspaces: 0, text: '()'));
    expect(ime.update(_value('(你)')), (backspaces: 1, text: '你)'));
    expect(ime.update(_value('(他)')), (backspaces: 2, text: '他)'));
    expect(ime.update(_value('(👩‍💻)')), (backspaces: 2, text: '👩‍💻)'));
    expect(ime.update(_value('()')), (backspaces: 2, text: ')'));
    expect(ime.update(TextEditingValue.empty), (backspaces: 2, text: ''));
    expect(ime.restoreMarker(TextEditingValue.empty), SessionIme.initialValue);
    expect(ime.update(SessionIme.initialValue), isNull);
    expect(ime.update(TextEditingValue.empty), (backspaces: 1, text: ''));
  });

  test('physical keys bypass IME only for shortcuts or remote navigation', () {
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.keyA,
            composing: false, shortcut: false),
        isFalse);
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.backspace,
            composing: false, shortcut: false),
        isFalse);
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.keyA,
            composing: true, shortcut: true),
        isTrue);
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.controlRight,
            composing: false, shortcut: false),
        isTrue);
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.arrowDown,
            composing: true, shortcut: false),
        isFalse);
    expect(
        useRemoteSessionKey(LogicalKeyboardKey.arrowDown,
            composing: false, shortcut: false),
        isTrue);
  });
}
