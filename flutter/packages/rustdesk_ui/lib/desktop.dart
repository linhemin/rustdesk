import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'rustdesk_ui.dart';

/// Desktop-session chrome only; remote image and input layers stay untouched.
class DesktopSessionStyle {
  DesktopSessionStyle._();

  static const buttonSize = 30.0;
  static const buttonRadius = 15.0;
  static const toolbarRadius = 20.0;
  static const collapsedToolbarRadius = 16.0;
  static const iconSize = 15.5;
  static const toolbarEdgeMargin = 8.0;
  static const inactive = Color(0xFF1C212C);
  static const inactiveHover = Color(0xFF2B3445);

  static MenuStyle menuStyle(BuildContext context) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Theme.of(context).cardColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(14),
        shadowColor: const WidgetStatePropertyAll(Color(0x4205070B)),
        side: WidgetStatePropertyAll(
            BorderSide(color: WorkspaceStyle.strongBorder(context))),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      );
}

class SessionToolbarSurface extends StatelessWidget {
  const SessionToolbarSurface({
    super.key,
    required this.child,
    this.borderRadius = DesktopSessionStyle.toolbarRadius,
  });

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x52030509) : const Color(0x220F172A),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: dark ? const Color(0x36000000) : const Color(0x140F172A),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Theme.of(context).cardColor.withOpacity(dark ? 0.88 : 0.92),
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: WorkspaceStyle.strongBorder(context)),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class SessionToolbarDivider extends StatelessWidget {
  const SessionToolbarDivider({super.key, this.horizontal = true});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.12);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal ? 4 : 0,
        vertical: horizontal ? 0 : 4,
      ),
      child: ColoredBox(
        color: color,
        child: SizedBox(
          width: horizontal ? 1 : 16,
          height: horizontal ? 16 : 1,
        ),
      ),
    );
  }
}

class SessionToolbarPillVisual extends StatelessWidget {
  const SessionToolbarPillVisual({
    super.key,
    required this.icon,
    this.label,
    this.compact = false,
    this.hover = false,
    this.active = false,
    this.open = false,
    this.destructive = false,
    this.muted = false,
    this.hasDropdown = false,
    this.accentColor,
    this.height = DesktopSessionStyle.buttonSize,
  });

  final Widget icon;
  final String? label;
  final bool compact;
  final bool hover;
  final bool active;
  final bool open;
  final bool destructive;
  final bool muted;
  final bool hasDropdown;
  final Color? accentColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final primary = accentColor ?? theme.colorScheme.primary;
    final danger = WorkspaceStyle.danger(context);
    final showLabel = !compact && label != null && label!.isNotEmpty;

    final Color fg;
    final Color bg;
    final Color border;
    if (destructive) {
      fg = danger;
      bg = danger.withOpacity(hover ? 0.22 : 0.12);
      border = danger.withOpacity(hover ? 0.36 : 0.22);
    } else if (active || open) {
      fg = primary;
      bg = primary.withOpacity(dark
          ? (hover ? 0.24 : 0.17)
          : (hover ? 0.16 : 0.11));
      border = primary.withOpacity(dark ? 0.38 : 0.28);
    } else {
      fg = muted
          ? theme.hintColor.withOpacity(hover ? 1.0 : 0.90)
          : ink.withOpacity(hover ? 1.0 : 0.88);
      bg = hover
          ? ink.withOpacity(dark ? 0.10 : 0.07)
          : Colors.transparent;
      border = Colors.transparent;
    }

    final themedIcon = IconTheme.merge(
      data: IconThemeData(color: fg, size: DesktopSessionStyle.iconSize),
      child: icon,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minWidth: height, minHeight: height),
      padding: showLabel
          ? EdgeInsetsDirectional.only(
              start: destructive ? 10 : 9,
              end: hasDropdown ? 6 : (destructive ? 10 : 9),
              top: 4,
              bottom: 4,
            )
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: border, width: 1),
      ),
      alignment: Alignment.center,
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                themedIcon,
                const SizedBox(width: 5),
                Text(
                  label!,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: (destructive || active || open)
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: fg,
                  ),
                ),
                if (hasDropdown) ...[
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: fg.withOpacity(open ? 1.0 : 0.72),
                    ),
                  ),
                ],
              ],
            )
          : themedIcon,
    );
  }
}

class SessionStatusPill extends StatefulWidget {
  const SessionStatusPill({
    super.key,
    required this.dotColor,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.active = false,
    this.compact = false,
    this.height = DesktopSessionStyle.buttonSize,
    this.trailing,
  });

  final Color dotColor;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final bool compact;
  final double height;
  final Widget? trailing;

  @override
  State<SessionStatusPill> createState() => _SessionStatusPillState();
}

class _SessionStatusPillState extends State<SessionStatusPill> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = widget.dotColor;
    final highlighted = _hover || _focused;
    final bg = color.withOpacity(widget.active
        ? (dark ? 0.20 : 0.14)
        : (highlighted ? (dark ? 0.16 : 0.12) : (dark ? 0.10 : 0.08)));
    final border = color.withOpacity(widget.active
        ? 0.44
        : (highlighted ? 0.30 : 0.18));

    final pill = Semantics(
      button: widget.onPressed != null,
      enabled: widget.onPressed != null,
      label: widget.tooltip ?? widget.label,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: widget.onPressed != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: widget.onPressed == null
            ? null
            : <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<Intent>(
                  onInvoke: (_) {
                    widget.onPressed?.call();
                    return null;
                  },
                ),
              },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            constraints: BoxConstraints(
                minWidth: widget.height, minHeight: widget.height),
            padding: widget.compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(
                  color: _focused ? color : border, width: _focused ? 1.4 : 1),
            ),
            alignment: Alignment.center,
            child: widget.compact
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 12,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 4),
                        widget.trailing!,
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: pill);
    }
    return pill;
  }
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
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: child,
            ),
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
