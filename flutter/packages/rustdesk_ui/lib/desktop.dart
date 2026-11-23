import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Desktop-session chrome only; remote image and input layers stay untouched.
class DesktopSessionStyle {
  DesktopSessionStyle._();

  static const buttonSize = 34.0;
  static const buttonRadius = 17.0;
  static const toolbarRadius = 28.0;
  static const inactive = Color(0xFF1C212C);
  static const inactiveHover = Color(0xFF2B3445);

  static MenuStyle menuStyle(BuildContext context) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Theme.of(context).cardColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(12),
        shadowColor: const WidgetStatePropertyAll(Color(0x3805070B)),
        side: WidgetStatePropertyAll(
            BorderSide(color: Theme.of(context).dividerColor)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
      );
}

class SessionToolbarSurface extends StatelessWidget {
  const SessionToolbarSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(DesktopSessionStyle.toolbarRadius),
          boxShadow: const [
            BoxShadow(
                color: Color(0x3805070B), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(DesktopSessionStyle.toolbarRadius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Theme.of(context).cardColor.withOpacity(0.88),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(DesktopSessionStyle.toolbarRadius),
                side: BorderSide(color: WorkspaceStyle.strongBorder(context)),
              ),
              child: child,
            ),
          ),
        ),
      );
}

class SessionOverlayFrame extends StatelessWidget {
  const SessionOverlayFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x36000000),
                  blurRadius: 20,
                  offset: Offset(0, 6))
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: child,
          ),
        ),
      );
}

class DesktopOverlaySurface extends StatelessWidget {
  const DesktopOverlaySurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(
              color: Color(0x3605070B), blurRadius: 24, offset: Offset(0, 8))
        ]),
        child: Material(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
          borderRadius: BorderRadius.circular(16),
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
