import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';

Future<void> showPeerUdpReport(BuildContext context, QualityMonitorModel model) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('UDP · ${translate("Remote device")}'),
        content: SizedBox(
          width: 420,
          child: ListenableBuilder(
            listenable: model,
            builder: (_, __) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final report in model.udpReports.reversed) ...[
                    SelectableText(report.split('\n').first),
                    if (!report.contains('\n')) Text(translate('Waiting')),
                    if (report.contains('\n'))
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          horizontalMargin: 0,
                          columnSpacing: 12,
                          dataRowMinHeight: 28,
                          dataRowMaxHeight: 34,
                          columns: [
                            for (final title in [translate('Local Port'), 'RX', 'RX ✓', 'TX', 'ACK TX', 'TX err'])
                              DataColumn(label: Text(title)),
                          ],
                          rows: [
                            for (final line in report.split('\n').skip(2))
                              DataRow(cells: [for (final value in line.split(' | ')) DataCell(Text(value))]),
                          ],
                        ),
                      ),
                    const Divider(),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(translate('Close'))),
        ],
      ),
    );

class PeerUdpButton extends StatelessWidget {
  const PeerUdpButton(this.model, {this.foreground, super.key});
  final QualityMonitorModel model;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => showPeerUdpReport(context, model),
        style: TextButton.styleFrom(foregroundColor: foreground),
        child: Text(model.udpReports.last.split('\n').first),
      );
}
