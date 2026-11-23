import 'package:flutter_hbb/common/widgets/peer_udp_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:rustdesk_ui/desktop.dart';

class DesktopQualityMonitor extends StatelessWidget {
  const DesktopQualityMonitor(this.model, {super.key});

  final QualityMonitorModel model;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: model,
        builder: (context, _) {
          if (!model.show) return const SizedBox.shrink();
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final data = model.data;
          final kbps = int.tryParse(data.targetBitrate ?? '');
          final bitrate = switch (kbps) {
            null => '—',
            < 1000 => '$kbps kb/s',
            _ => '${kbps % 1000 == 0 ? kbps ~/ 1000 : kbps / 1000} Mb/s',
          };
          final delay = data.delay == null ? '—' : '${data.delay} ms';
          final caption = theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          );
          final number = theme.textTheme.titleMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

          Widget reading(String label, String value) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: caption),
                  Text(value, style: number),
                ],
              );
          Widget detail(String label, String value) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(label, style: caption)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(value,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                  ],
                ),
              );
          return SessionOverlayFrame(
            child: Container(
              width: 236,
              color: theme.cardColor.withOpacity(0.95),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.south_west_rounded,
                        size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(translate('Speed'), style: caption)),
                    Expanded(
                        flex: 2,
                        child: Text(data.speed ?? '—',
                            textAlign: TextAlign.end, style: number)),
                    const SizedBox(width: 4),
                    Icon(Icons.drag_indicator_rounded,
                        size: 14, color: theme.hintColor.withOpacity(0.7)),
                  ]),
                  const Divider(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: reading(translate('FPS'), data.fps ?? '—')),
                    const SizedBox(width: 12),
                    Expanded(child: reading(translate('Delay'), delay)),
                  ]),
                  const Divider(height: 14),
                  detail(translate('Bitrate'), bitrate),
                  detail(translate('Codec'), data.codecFormat ?? '—'),
                  detail(translate('Chroma'), data.chroma ?? '—'),
                  if (model.udpReports.isNotEmpty) PeerUdpButton(model),
                  if (model.directConnection case final direct?) ...[
                    const Divider(height: 12),
                    detail(
                        translate(
                            direct ? 'Direct Connection' : 'Relay Connection'),
                        model.activeTransport ?? '—'),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

/// Draggable viewport overlay for [DesktopQualityMonitor].
class DraggableDesktopQualityMonitor extends StatefulWidget {
  const DraggableDesktopQualityMonitor(
    this.model, {
    super.key,
    this.wrap,
  });

  final QualityMonitorModel model;
  final Widget Function(Widget child)? wrap;

  @override
  State<DraggableDesktopQualityMonitor> createState() =>
      _DraggableDesktopQualityMonitorState();
}

class _DraggableDesktopQualityMonitorState
    extends State<DraggableDesktopQualityMonitor> {
  static const _panelWidth = 236.0;
  static const _estimatedHeight = 200.0;
  static const _edgeMargin = 10.0;

  Offset? _offset;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
      final maxH =
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
      final minX = _edgeMargin;
      final maxX = (maxW - _panelWidth - _edgeMargin).clamp(minX, maxW);
      final minY = _edgeMargin;
      final maxY = (maxH - _estimatedHeight - _edgeMargin).clamp(minY, maxH);

      final panel = MouseRegion(
        cursor: _dragging
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            setState(() {
              _dragging = true;
              _offset ??= Offset(maxX, maxY);
            });
          },
          onPanUpdate: (details) {
            final current = _offset ?? Offset(maxX, maxY);
            setState(() {
              _offset = Offset(
                (current.dx + details.delta.dx).clamp(minX, maxX),
                (current.dy + details.delta.dy).clamp(minY, maxY),
              );
            });
          },
          onPanEnd: (_) => setState(() => _dragging = false),
          onPanCancel: () => setState(() => _dragging = false),
          child: DesktopQualityMonitor(widget.model),
        ),
      );

      final wrapped = widget.wrap != null ? widget.wrap!(panel) : panel;
      final pos = _offset;
      if (pos == null) {
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned(
              right: _edgeMargin,
              bottom: 12,
              child: wrapped,
            ),
          ],
        );
      }
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: pos.dx.clamp(minX, maxX),
            top: pos.dy.clamp(minY, maxY),
            child: wrapped,
          ),
        ],
      );
    });
  }
}
