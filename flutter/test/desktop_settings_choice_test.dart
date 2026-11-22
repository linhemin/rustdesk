import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/settings_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'an unavailable saved setting can be replaced without writing a default',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 360);
    addTearDown(tester.view.reset);
    const label = 'Automatic selection of supported hardware decoders';
    final changes = <String>[];
    Future<void> show(bool fixed, String value) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WorkspaceSettingsSection(
        title: 'Default video decoder configuration',
        trailing: [
          Flexible(
              child: WorkspaceSettingsChoice(
            value: value,
            fallback: 'Default',
            options: const {'auto': label, 'vp9': 'VP9'},
            onChanged: fixed ? null : changes.add,
          ))
        ],
        children: const [],
      ))));
    }

    await show(true, 'removed-codec');
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await show(false, '');
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VP9').last);
    await tester.pumpAndSettle();
    expect(changes, ['vp9']);
    await show(false, 'auto');
    expect(find.text('Default'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
