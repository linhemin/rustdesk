import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Desktop-session chrome only; remote image and input layers stay untouched.
class DesktopSessionStyle {
  DesktopSessionStyle._();

  static const buttonSize = 36.0;
  static const buttonRadius = 10.0;
  static const toolbarRadius = 16.0;
  static const inactive = Color(0xFF25344B);
  static const inactiveHover = Color(0xFF3B4D69);

  static MenuStyle menuStyle(BuildContext context) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Theme.of(context).cardColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: const WidgetStatePropertyAll(Color(0x240B1426)),
        side: WidgetStatePropertyAll(
            BorderSide(color: Theme.of(context).dividerColor)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      );
}

class SessionToolbarSurface extends StatelessWidget {
  const SessionToolbarSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).cardColor,
        elevation: 6,
        shadowColor: const Color(0x240B1426),
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(DesktopSessionStyle.toolbarRadius),
            side: BorderSide(color: Theme.of(context).dividerColor)),
        child: child,
      );
}

class SessionOverlayFrame extends StatelessWidget {
  const SessionOverlayFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x665B6B85)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 16,
                  offset: Offset(0, 4))
            ]),
        child: ClipRRect(borderRadius: BorderRadius.circular(11), child: child),
      );
}

class DesktopOverlaySurface extends StatelessWidget {
  const DesktopOverlaySurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(
              color: Color(0x260B1426), blurRadius: 24, offset: Offset(0, 8))
        ]),
        child: Material(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor)),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

class TransferPane extends StatelessWidget {
  const TransferPane({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(8),
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );
}

class TransferPaneHeading extends StatelessWidget {
  const TransferPaneHeading({
    super.key,
    required this.leading,
    required this.title,
    this.trailing,
  });
  final Widget leading;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
      );
}

class TransferEmptyState extends StatelessWidget {
  const TransferEmptyState({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const WorkspaceIcon(icon: Icons.swap_horiz_rounded, size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Theme.of(context).hintColor, height: 1.5)),
          ]),
        ),
      );
}
