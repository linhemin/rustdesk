import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The mobile session HUD; all readings and actions come from the live session.
class MobileSessionQualityMonitor extends StatefulWidget {
  const MobileSessionQualityMonitor({
    super.key,
    required this.connection,
    required this.direct,
    required this.metrics,
    this.diagnostics,
  });

  final String connection;
  final bool? direct;
  final List<(String, String)> metrics;
  final Widget? diagnostics;

  @override
  State<MobileSessionQualityMonitor> createState() =>
      _MobileSessionQualityMonitorState();
}

class _MobileSessionQualityMonitorState
    extends State<MobileSessionQualityMonitor> {
  Offset _offset = const Offset(12, 12);

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
        delegate: _QualityPosition(_offset, context),
        child: LayoutBuilder(builder: (cardContext, constraints) {
          // Keep the two-line heading and one full 48pt action usable.
          if (constraints.maxHeight <
              83 + MediaQuery.textScalerOf(context).scale(11) * 2.8) {
            return const SizedBox.shrink();
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              final card = cardContext.findRenderObject() as RenderBox?;
              final viewport = context.findRenderObject() as RenderBox?;
              if (card != null && viewport != null) {
                _offset = card.localToGlobal(Offset.zero, ancestor: viewport);
              }
            },
            onPanUpdate: (details) {
              final card = cardContext.findRenderObject() as RenderBox?;
              final viewport = context.findRenderObject() as RenderBox?;
              if (card == null || viewport == null) return;
              setState(() {
                _offset = _QualityPosition(_offset + details.delta, context)
                    .getPositionForChild(viewport.size, card.size);
              });
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x70000000),
                      blurRadius: 32,
                      offset: Offset(0, 12)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    width: 162,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xc2101622),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x24ffffff)),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                          color: Color(0xfff1f5fa),
                          fontSize: 10.5,
                          height: 1.4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: widget.direct == null
                                        ? const Color(0xff94a3b8)
                                        : widget.direct!
                                            ? const Color(0xff34d399)
                                            : const Color(0xff60a5fa))),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(widget.connection,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600))),
                            const Icon(Icons.drag_indicator,
                                size: 12, color: Color(0x9ee2eaf6)),
                          ]),
                          const Divider(color: Color(0x17ffffff), height: 13),
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (label, value) in widget.metrics)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              flex: 5,
                                              child: Text(label,
                                                  style: const TextStyle(
                                                      color:
                                                          Color(0x9ee2eaf6)))),
                                          const SizedBox(width: 4),
                                          Expanded(
                                              flex: 7,
                                              child: Text(value,
                                                  textAlign: TextAlign.end,
                                                  style: const TextStyle(
                                                      fontFeatures: [
                                                        ui.FontFeature
                                                            .tabularFigures()
                                                      ]))),
                                        ],
                                      ),
                                    ),
                                  if (widget.diagnostics
                                      case final diagnostics?)
                                    diagnostics,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );
}

class _QualityPosition extends SingleChildLayoutDelegate {
  // Native gamepad: 44pt arrows + 8pt gap + 116pt keys + 44pt bottom,
  // plus 12pt clearance. This viewport already excludes the bottom safe area.
  _QualityPosition(this.offset, BuildContext context)
      : bottomInset = (224.0 -
                View.of(context).viewPadding.bottom /
                    MediaQuery.of(context).devicePixelRatio)
            .clamp(12.0, 224.0);
  final Offset offset;
  final double bottomInset;
  static const _rightInset = 68.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints
          .loosen()
          .deflate(EdgeInsets.fromLTRB(12, 12, _rightInset, bottomInset));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(
      offset.dx.clamp(
          12.0,
          (size.width - childSize.width - _rightInset)
              .clamp(12.0, double.infinity)),
      offset.dy.clamp(
          12.0,
          (size.height - childSize.height - bottomInset)
              .clamp(12.0, double.infinity)),
    );
  }

  @override
  bool shouldRelayout(_QualityPosition oldDelegate) =>
      offset != oldDelegate.offset || bottomInset != oldDelegate.bottomInset;
}
