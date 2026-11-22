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
              width: 232,
              color: theme.cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.south_west_rounded,
                        size: 18, color: colors.primary),
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
                    const SizedBox(width: 12),
                    Expanded(child: reading(translate('Delay'), delay)),
                  ]),
                  const Divider(height: 14),
                  detail(translate('Bitrate'), bitrate),
                  detail(translate('Codec'), data.codecFormat ?? '—'),
                  detail(translate('Chroma'), data.chroma ?? '—'),
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
