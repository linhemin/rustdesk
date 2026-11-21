import 'package:flutter/material.dart';

/// Visual primitives shared by the app and the backend-free UI catalog.
class WorkspaceStyle {
  WorkspaceStyle._();

  static const accent = Color(0xFF4263EB);
  static const ink = Color(0xFF17233B);
  static const muted = Color(0xFF66758C);
  static const background = Color(0xFFF4F6FA);
  static const border = Color(0xFFE2E7F0);
  static const night = Color(0xFF101725);
  static const nightSurface = Color(0xFF1A2436);

  static ThemeData apply(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final surface = dark ? nightSurface : Colors.white;
    final line = dark ? const Color(0xFF303E54) : border;
    final text = dark ? const Color(0xFFE8EDF7) : ink;
    final interactive = dark ? const Color(0xFFA5B4FC) : accent;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: line),
    );
    return base.copyWith(
      primaryColor: accent,
      scaffoldBackgroundColor: dark ? night : background,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: line,
      hintColor: dark ? const Color(0xFF9AA9BF) : muted,
      colorScheme: base.colorScheme.copyWith(
        primary: interactive,
        onPrimary: dark ? night : Colors.white,
        secondary: interactive,
        surface: surface,
        onSurface: text,
        background: dark ? night : background,
        onBackground: text,
      ),
      textTheme:
          base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
                headlineSmall: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: text,
                    letterSpacing: -0.8),
                titleLarge: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: text,
                    letterSpacing: -0.4),
                titleMedium: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: text),
              ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: text,
            letterSpacing: -0.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? night : background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: accent, width: 2)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: shape,
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: line),
        minimumSize: const Size(48, 44),
        shape: shape,
      )),
      listTileTheme: base.listTileTheme.copyWith(
          shape: shape, iconColor: dark ? const Color(0xFF9AA9BF) : muted),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: dark ? const Color(0xFF9AA9BF) : muted,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(MaterialState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color:
                  states.contains(MaterialState.selected) ? interactive : text,
            )),
        iconTheme: MaterialStateProperty.resolveWith((states) => IconThemeData(
              color:
                  states.contains(MaterialState.selected) ? interactive : text,
            )),
      ),
      dialogTheme: base.dialogTheme
          .copyWith(elevation: 0, backgroundColor: surface, shape: shape),
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
