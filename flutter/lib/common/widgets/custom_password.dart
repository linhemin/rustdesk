// https://github.com/rodrigobastosv/fancy_password_field
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:get/get.dart';
import 'package:password_strength/password_strength.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

abstract class ValidationRule {
  String get name;
  bool validate(String value);
}

class UppercaseValidationRule extends ValidationRule {
  @override
  String get name => translate('uppercase');
  @override
  bool validate(String value) {
    return value.runes.any((int rune) {
      var character = String.fromCharCode(rune);
      return character.toUpperCase() == character &&
          character.toLowerCase() != character;
    });
  }
}

class LowercaseValidationRule extends ValidationRule {
  @override
  String get name => translate('lowercase');

  @override
  bool validate(String value) {
    return value.runes.any((int rune) {
      var character = String.fromCharCode(rune);
      return character.toLowerCase() == character &&
          character.toUpperCase() != character;
    });
  }
}

class DigitValidationRule extends ValidationRule {
  @override
  String get name => translate('digit');

  @override
  bool validate(String value) {
    return value.contains(RegExp(r'[0-9]'));
  }
}

class SpecialCharacterValidationRule extends ValidationRule {
  @override
  String get name => translate('special character');

  @override
  bool validate(String value) {
    return value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  }
}

class MinCharactersValidationRule extends ValidationRule {
  final int _numberOfCharacters;
  MinCharactersValidationRule(this._numberOfCharacters);

  @override
  String get name => translate('length>=$_numberOfCharacters');

  @override
  bool validate(String value) {
    return value.length >= _numberOfCharacters;
  }
}

class PasswordStrengthIndicator extends StatelessWidget {
  final RxString password;
  final double weakMedium = 0.33;
  final double mediumStrong = 0.67;
  const PasswordStrengthIndicator({Key? key, required this.password})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var strength = estimatePasswordStrength(password.value);
      final label = password.isEmpty ? '' : translate(_getLabel(strength));
      final color = _getColor(context, strength);
      final inactiveColor = Theme.of(context).dividerColor;
      return Semantics(
        liveRegion: true,
        label: label,
        child: Row(
          children: [
            Expanded(
                child: _indicator(password.isEmpty ? inactiveColor : color)),
            Expanded(
                child: _indicator(
                    password.isEmpty || strength < weakMedium ? inactiveColor : color)),
            Expanded(
                child: _indicator(password.isEmpty || strength < mediumStrong
                    ? inactiveColor
                    : color)),
            if (label.isNotEmpty) Text(label).marginOnly(left: 8),
          ],
        ),
      );
    });
  }

  Widget _indicator(Color color) {
    return Container(
      height: 8,
      color: color,
    );
  }

  String _getLabel(double strength) {
    if (strength < weakMedium) {
      return 'Weak';
    } else if (strength < mediumStrong) {
      return 'Medium';
    } else {
      return 'Strong';
    }
  }

  Color _getColor(BuildContext context, double strength) {
    if (strength < weakMedium) {
      return WorkspaceStyle.danger(context);
    } else if (strength < mediumStrong) {
      return WorkspaceStyle.warning(context);
    } else {
      return WorkspaceStyle.success(context);
    }
  }
}
