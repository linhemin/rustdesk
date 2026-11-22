import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Visuals for the native Apple and Windows workspaces.
bool get usesWorkspaceStyle =>
    !kIsWeb &&
    const {
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

class WorkspaceStyle {
  WorkspaceStyle._();
  static const accent = blue;
  static const ink = navy;
  static const muted = Color(0xff516077);
  static const background = Color(0xfff6f8fb);
  static const border = Color(0xffd4dde9);
  static const nightSurface = slate;
  static const blue = Color(0xff2454cc);
  static const navy = Color(0xff142746);
  static const mist = Color(0xffedf2f8);
  static const night = Color(0xff111923);
  static const slate = Color(0xff1d2939);
  static const ice = Color(0xffa8c6ff);

  static ThemeData apply(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final ios = !kIsWeb && base.platform == TargetPlatform.iOS;
    final paper = dark ? slate : Colors.white;
    final background = dark ? night : const Color(0xfff6f8fb);
    final ink = dark ? const Color(0xffedf3fd) : navy;
    final muted = dark ? const Color(0xffb2bfd1) : const Color(0xff516077);
    final line = dark ? const Color(0xff39475b) : const Color(0xffd4dde9);
    final accent = dark ? ice : blue;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final outlinedShape = shape.copyWith(side: BorderSide(color: line));
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    // Material 2 uses bodyLarge for rows and titleMedium for text fields.
    final iosRow =
        text.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w500);
    final fields = base.inputDecorationTheme;
    return base.copyWith(
      primaryColor: accent,
      canvasColor: paper,
      cardColor: paper,
      scaffoldBackgroundColor: background,
      dialogBackgroundColor: paper,
      dividerColor: line,
      hintColor: muted,
      hoverColor: accent.withOpacity(.08),
      focusColor: accent.withOpacity(.14),
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: dark ? navy : Colors.white,
        secondary: accent,
        onSecondary: dark ? navy : Colors.white,
        background: dark ? const Color(0xff192332) : mist,
        surface: paper,
        onSurface: ink,
        onBackground: ink,
        outline: muted,
        outlineVariant: line,
        surfaceContainerHighest: dark ? const Color(0xff29364a) : mist,
      ),
      textTheme: text.copyWith(
        bodyLarge: ios ? iosRow : null,
        titleLarge: text.titleLarge?.copyWith(
            fontSize: 21, letterSpacing: -.45, fontWeight: FontWeight.w700),
        titleMedium: ios
            ? iosRow
            : text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        backgroundColor: background,
        foregroundColor: ink,
        titleTextStyle: text.titleLarge?.copyWith(
            color: ink,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5),
      ),
      cardTheme: base.cardTheme
          .copyWith(color: paper, elevation: 0, shape: outlinedShape),
      dialogTheme: base.dialogTheme.copyWith(
          titleTextStyle: ios
              ? iosRow?.copyWith(fontSize: 17, fontWeight: FontWeight.w600)
              : null,
          contentTextStyle: ios ? text.bodyMedium : null,
          backgroundColor: paper,
          elevation: 6,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: line))),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: paper,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
      popupMenuTheme: base.popupMenuTheme
          .copyWith(color: paper, elevation: 4, shape: outlinedShape),
      listTileTheme: base.listTileTheme
          .copyWith(shape: shape, selectedColor: accent, iconColor: muted),
      dividerTheme: DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: fields.copyWith(
        fillColor: dark ? night : background,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: line)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: blue,
        foregroundColor: Colors.white,
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: paper,
        side: BorderSide(color: line),
        shape: shape,
      )),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: paper,
        elevation: 0,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
          backgroundColor: navy,
          contentTextStyle: const TextStyle(color: Colors.white)),
    );
  }
}

/// The input and actions retain their own focus, autocomplete and session state.
class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel(
      {super.key, required this.title, required this.controls, this.help});

  final String title;
  final Widget controls;
  final Widget? help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WorkspacePanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.north_east_rounded,
                size: 19, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: theme.textTheme.titleMedium)),
            if (help != null) ...[const SizedBox(width: 6), help!],
          ]),
          const SizedBox(height: 12),
          controls,
        ],
      ),
    );
  }
}

class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );
}

class WorkspaceHeading extends StatelessWidget {
  const WorkspaceHeading(
      {super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle!,
                      style: TextStyle(
                          color: Theme.of(context).hintColor, height: 1.5)),
                ],
              ])),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      );
}

class WorkspaceIcon extends StatelessWidget {
  const WorkspaceIcon({super.key, required this.icon, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: WorkspaceStyle.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon,
            color: Theme.of(context).colorScheme.primary, size: size * .48),
      );
}

class WorkspaceSidebar extends StatelessWidget {
  const WorkspaceSidebar({super.key, required this.child, this.width = 264});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: BorderDirectional(
              end: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: child,
      );
}
