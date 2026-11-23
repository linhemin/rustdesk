import 'package:flutter_hbb/common/widgets/peer_udp_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:rustdesk_ui/desktop.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

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

          Widget reading(String label, String value) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: WorkspaceStyle.elevatedSurface(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: caption),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: number),
                    ),
                  ],
                ),
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
              width: 272,
              color: theme.cardColor.withOpacity(0.88),
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.drag_indicator_rounded,
                        size: 14, color: theme.hintColor),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(translate('Connection quality'),
                            style: theme.textTheme.labelLarge)),
                    IconButton(
                      tooltip: translate('Close'),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () async {
                        final sessionId = model.parent.target?.sessionId;
                        if (sessionId == null) return;
                        await bind.sessionToggleOption(
                            sessionId: sessionId,
                            value: 'show-quality-monitor');
                        await model.checkShowQualityMonitor(sessionId);
                      },
                    ),
                  ]),
                  const Divider(height: 12),
                  Row(children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: model.directConnection == null
                            ? theme.hintColor
                            : model.directConnection == true
                                ? WorkspaceStyle.success(context)
                                : colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(translate('Speed'), style: caption)),
                    Expanded(
                        flex: 2,
                        child: Text(data.speed ?? '—',
                            textAlign: TextAlign.end, style: number)),
                  ]),
                  const Divider(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: reading(translate('FPS'), data.fps ?? '—')),
                    const SizedBox(width: 6),
                    Expanded(child: reading(translate('Delay'), delay)),
                    const SizedBox(width: 6),
                    Expanded(child: reading(translate('Bitrate'), bitrate)),
                  ]),
                  const Divider(height: 14),
                  detail(translate('Codec'), data.codecFormat ?? '—'),
                  detail(translate('Chroma'), data.chroma ?? '—'),
                  if (model.directConnection case final direct?) ...[
                    const Divider(height: 12),
                    detail(
                        translate(
                            direct ? 'Direct Connection' : 'Relay Connection'),
                        model.activeTransport ?? '—'),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: model.udpReports.isEmpty
                            ? null
                            : () => showPeerUdpReport(context, model),
                        icon: const Icon(Icons.expand_more_rounded, size: 16),
                        label: Text(translate('UDP diagnostics')),
                      )),
                ],
              )),
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
  });

  final QualityMonitorModel model;

  @override
  State<DraggableDesktopQualityMonitor> createState() =>
      _DraggableDesktopQualityMonitorState();
}

class _DraggableDesktopQualityMonitorState
    extends State<DraggableDesktopQualityMonitor> {
  Offset _offset = const Offset(20, 68);
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
        delegate: _DesktopQualityPosition(_offset),
        child: Builder(builder: (cardContext) {
          final panel = MouseRegion(
            cursor: _dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                final card = cardContext.findRenderObject() as RenderBox?;
                final viewport = context.findRenderObject() as RenderBox?;
                setState(() {
                  _dragging = true;
                  if (card != null && viewport != null) {
                    _offset =
                        card.localToGlobal(Offset.zero, ancestor: viewport);
                  }
                });
              },
              onPanUpdate: (details) {
                final card = cardContext.findRenderObject() as RenderBox?;
                final viewport = context.findRenderObject() as RenderBox?;
                if (card == null || viewport == null) return;
                setState(() {
                  _offset = _DesktopQualityPosition(_offset + details.delta)
                      .getPositionForChild(viewport.size, card.size);
                });
              },
              onPanEnd: (_) => setState(() => _dragging = false),
              onPanCancel: () => setState(() => _dragging = false),
              child: DesktopQualityMonitor(widget.model),
            ),
          );

          return panel;
        }));
  }
}

class _DesktopQualityPosition extends SingleChildLayoutDelegate {
  _DesktopQualityPosition(this.offset);
  final Offset offset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(10));

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
        offset.dx.clamp(10.0,
            (size.width - childSize.width - 10).clamp(10.0, double.infinity)),
        offset.dy.clamp(10.0,
            (size.height - childSize.height - 10).clamp(10.0, double.infinity)),
      );

  @override
  bool shouldRelayout(_DesktopQualityPosition oldDelegate) =>
      offset != oldDelegate.offset;
}
