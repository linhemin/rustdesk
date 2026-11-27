import 'package:flutter/material.dart';

import '../../common.dart';
import '../awesun/awesun_flutter_overlay.dart';

enum MobileActionCategory {
  canvas,
  remote,
  power,
  diagnostics,
}

class MobileSessionActionItem {
  const MobileSessionActionItem({
    required this.title,
    required this.category,
    required this.onPressed,
    this.icon,
    this.danger = false,
    this.trailing,
  });

  final String title;
  final MobileActionCategory category;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool danger;
  final Widget? trailing;
}

/// Classifies a mobile session action by its actionId or label so menus stay
/// cleanly grouped instead of dumping every action into one flat list.
MobileActionCategory classifyMobileSessionAction({
  String? actionId,
  required String rawTitle,
}) {
  switch (actionId) {
    case 'refresh':
    case 'reset_canvas':
      return MobileActionCategory.canvas;
    case 'restart_remote':
      return MobileActionCategory.power;
    case 'send_ctrl_alt_del':
    case 'insert_lock':
    case 'toggle_block_input':
    case 'switch_sides':
    case 'send_clipboard_keystrokes':
    case 'toggle_recording':
    case 'screenshot':
      return MobileActionCategory.remote;
  }
  final lower = rawTitle.toLowerCase();
  if (lower.contains('diagnostic') ||
      lower.contains('诊断') ||
      lower.contains('p2p') ||
      lower.contains('udp')) {
    return MobileActionCategory.diagnostics;
  }
  if (lower.contains('restart') ||
      lower.contains('reboot') ||
      lower.contains('重启') ||
      lower.contains('关机') ||
      lower.contains('shutdown')) {
    return MobileActionCategory.power;
  }
  if (lower.contains('refresh') ||
      lower.contains('刷新') ||
      lower.contains('reset canvas') ||
      lower.contains('重置画面') ||
      lower.contains('center cursor') ||
      lower.contains('光标居中') ||
      lower.contains('lock display') ||
      lower.contains('lock canvas') ||
      lower.contains('锁定画面')) {
    return MobileActionCategory.canvas;
  }
  return MobileActionCategory.remote;
}

IconData iconForMobileSessionAction({
  String? actionId,
  required String rawTitle,
  required MobileActionCategory category,
}) {
  if (category == MobileActionCategory.diagnostics) {
    return Icons.bug_report_outlined;
  }
  if (category == MobileActionCategory.power) {
    return Icons.restart_alt_rounded;
  }
  switch (actionId) {
    case 'refresh':
      return Icons.refresh_rounded;
    case 'reset_canvas':
      return Icons.fit_screen_rounded;
    case 'send_ctrl_alt_del':
      return Icons.security_rounded;
    case 'insert_lock':
      return Icons.lock_outline_rounded;
    case 'toggle_block_input':
      return Icons.do_not_touch_outlined;
    case 'switch_sides':
      return Icons.swap_horiz_rounded;
    case 'send_clipboard_keystrokes':
      return Icons.content_paste_go_rounded;
    case 'toggle_recording':
      return Icons.fiber_manual_record_rounded;
    case 'screenshot':
      return Icons.camera_alt_outlined;
  }
  final lower = rawTitle.toLowerCase();
  if (lower.contains('cursor') || lower.contains('光标')) {
    return Icons.center_focus_strong_rounded;
  }
  if (lower.contains('password') || lower.contains('密码')) {
    return Icons.key_rounded;
  }
  if (lower.contains('elevation') || lower.contains('权限') || lower.contains('提权')) {
    return Icons.admin_panel_settings_outlined;
  }
  if (lower.contains('lock') || lower.contains('锁定')) {
    return Icons.lock_outline_rounded;
  }
  if (lower.contains('volume') || lower.contains('音量')) {
    return Icons.volume_up_outlined;
  }
  if (lower.contains('back') || lower.contains('返回')) {
    return Icons.arrow_back_rounded;
  }
  if (lower.contains('home') || lower.contains('主页')) {
    return Icons.home_outlined;
  }
  return Icons.tune_rounded;
}

/// Grouped dark-glass bottom sheet for mobile "More tools", keeping everyday
/// controls organized and tucking developer diagnostics into a collapsed drawer.
class MobileSessionMoreSheet extends StatefulWidget {
  const MobileSessionMoreSheet({
    super.key,
    required this.items,
    this.translateLabel,
  });

  final List<MobileSessionActionItem> items;
  final String Function(String key)? translateLabel;

  @override
  State<MobileSessionMoreSheet> createState() => _MobileSessionMoreSheetState();
}

class _MobileSessionMoreSheetState extends State<MobileSessionMoreSheet> {
  bool _diagnosticsExpanded = false;

  String _tr(String key) =>
      widget.translateLabel?.call(key) ?? translate(key);

  @override
  Widget build(BuildContext context) {
    final byCategory = <MobileActionCategory, List<MobileSessionActionItem>>{
      for (final category in MobileActionCategory.values) category: [],
    };
    for (final item in widget.items) {
      byCategory[item.category]!.add(item);
    }

    final canvasItems = byCategory[MobileActionCategory.canvas]!;
    final remoteItems = byCategory[MobileActionCategory.remote]!;
    final powerItems = byCategory[MobileActionCategory.power]!;
    final diagItems = byCategory[MobileActionCategory.diagnostics]!;

    return Container(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: AwesunVisualPalette.sheetFill,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x26FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr('More'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AwesunVisualPalette.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _tr('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AwesunVisualPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canvasItems.isNotEmpty) ...[
                      _sectionHeading(_tr('Display')),
                      const SizedBox(height: 8),
                      _itemList(context, canvasItems),
                      const SizedBox(height: 14),
                    ],
                    if (remoteItems.isNotEmpty) ...[
                      _sectionHeading(_tr('Action')),
                      const SizedBox(height: 8),
                      _itemList(context, remoteItems),
                      const SizedBox(height: 14),
                    ],
                    if (powerItems.isNotEmpty) ...[
                      _sectionHeading(_tr('Power')),
                      const SizedBox(height: 8),
                      _itemList(context, powerItems),
                      const SizedBox(height: 14),
                    ],
                    if (diagItems.isNotEmpty) ...[
                      Material(
                        color: Colors.white.withOpacity(0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => setState(
                                () => _diagnosticsExpanded =
                                    !_diagnosticsExpanded,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.troubleshoot_rounded,
                                      size: 18,
                                      color: AwesunVisualPalette.dim,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _tr('Diagnostics'),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AwesunVisualPalette.dim,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      _diagnosticsExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 18,
                                      color: AwesunVisualPalette.dim,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_diagnosticsExpanded) ...[
                              Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.08),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: _itemList(context, diagItems),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(String title) => Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AwesunVisualPalette.dim,
        ),
      );

  Widget _itemList(
    BuildContext context,
    List<MobileSessionActionItem> items,
  ) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _actionRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _actionRow(BuildContext context, MobileSessionActionItem item) {
    final danger = item.danger || item.category == MobileActionCategory.power;
    final fg = danger ? const Color(0xFFFCA5A5) : AwesunVisualPalette.ink;
    final bg = danger
        ? AwesunVisualPalette.danger.withOpacity(0.14)
        : Colors.white.withOpacity(0.06);
    final border = danger
        ? AwesunVisualPalette.danger.withOpacity(0.30)
        : Colors.white.withOpacity(0.08);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          item.onPressed();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: danger
                      ? AwesunVisualPalette.danger.withOpacity(0.20)
                      : Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon ??
                      iconForMobileSessionAction(
                        rawTitle: item.title,
                        category: item.category,
                      ),
                  size: 16,
                  color: fg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              if (item.trailing != null)
                item.trailing!
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AwesunVisualPalette.dim,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crisp local arrow pointer rendered when the user's own cursor is active in
/// pointer mode without the expanded Awesun radial wheel.
class LocalPointerArrow extends StatelessWidget {
  const LocalPointerArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox(
        width: 16,
        height: 22,
        child: CustomPaint(painter: _LocalPointerArrowPainter()),
      ),
    );
  }
}

class _LocalPointerArrowPainter extends CustomPainter {
  const _LocalPointerArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 17.5)
      ..lineTo(4.6, 13.5)
      ..lineTo(7.8, 20.5)
      ..lineTo(10.4, 19.3)
      ..lineTo(7.2, 12.4)
      ..lineTo(13.0, 12.2)
      ..close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.65), 2, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
