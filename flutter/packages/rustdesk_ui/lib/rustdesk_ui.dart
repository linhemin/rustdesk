import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Visuals for the unified desktop and mobile workspaces.
bool get usesWorkspaceStyle =>
    !kIsWeb &&
    const {
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

class WorkspaceStyle {
  WorkspaceStyle._();
  static const accent = blue;
  static const ink = navy;
  static const muted = Color(0xff64748b);
  static const background = Color(0xfff5f6f9);
  static const border = Color(0xffe2e7f0);
  static const nightSurface = slate;
  static const blue = Color(0xff2563eb);
  static const navy = Color(0xff0f172a);
  static const mist = Color(0xffeef1f6);
  static const night = Color(0xff0b0d11);
  static const slate = Color(0xff151921);
  static const ice = Color(0xff60a5fa);

  static const sidebarDark = Color(0xff101319);
  static const sidebarLight = Color(0xffffffff);
  static const surfaceElevatedDark = Color(0xff1c212c);
  static const surfaceElevatedLight = Color(0xffeef1f6);
  static const borderDark = Color(0xff232936);
  static const green = Color(0xff30b158);
  static const amber = Color(0xffff9f0a);
  static const red = Color(0xffff453a);
  static const purple = Color(0xffaf52de);
  static const indigo = Color(0xff5e5ce6);
  static const neutralTile = Color(0xff636366);

  static Color sidebarColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? sidebarDark
          : sidebarLight;

  static Color elevatedSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? surfaceElevatedDark
          : surfaceElevatedLight;

  static ThemeData apply(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final ios = !kIsWeb && base.platform == TargetPlatform.iOS;
    final paper = dark ? slate : Colors.white;
    final background = dark ? night : const Color(0xfff5f6f9);
    final ink = dark ? const Color(0xffeef2f8) : navy;
    final muted = dark ? const Color(0xff8b95a7) : const Color(0xff64748b);
    final line = dark ? borderDark : border;
    final accent = dark ? ice : blue;
    final elevated = dark ? surfaceElevatedDark : surfaceElevatedLight;
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
        onPrimary: dark ? const Color(0xff0b0d11) : Colors.white,
        secondary: accent,
        onSecondary: dark ? const Color(0xff0b0d11) : Colors.white,
        background: background,
        surface: paper,
        onSurface: ink,
        onBackground: ink,
        outline: muted,
        outlineVariant: line,
        surfaceContainerHighest: elevated,
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
        scrolledUnderElevation: 0,
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)))),
      popupMenuTheme: base.popupMenuTheme
          .copyWith(color: paper, elevation: 6, shape: outlinedShape),
      listTileTheme: base.listTileTheme
          .copyWith(shape: shape, selectedColor: accent, iconColor: muted),
      dividerTheme: DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: fields.copyWith(
        fillColor: dark ? night : elevated,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accent, width: 1.4)),
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
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
          backgroundColor: dark ? surfaceElevatedDark : navy,
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
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium)),
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
      this.padding = const EdgeInsets.all(20),
      this.radius = 16});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(radius),
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
                  const SizedBox(height: 6),
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
          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            color: Theme.of(context).colorScheme.primary, size: size * .48),
      );
}

/// Colored rounded-square vector icon tile (macOS / iOS settings style).
class WorkspaceIconTile extends StatelessWidget {
  const WorkspaceIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
    this.radius = 7.5,
    this.iconSize,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: iconSize ?? size * 0.56, color: Colors.white),
      );
}

class WorkspaceSidebar extends StatelessWidget {
  const WorkspaceSidebar({super.key, required this.child, this.width = 232});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        decoration: BoxDecoration(
          color: WorkspaceStyle.sidebarColor(context),
          border: BorderDirectional(
              end: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: child,
      );
}
