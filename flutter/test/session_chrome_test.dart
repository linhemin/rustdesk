import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rustdesk_ui/desktop.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('session toolbar menus stay usable in $brightness',
        (tester) async {
      var selected = false;
      await tester.pumpWidget(MaterialApp(
        theme: WorkspaceStyle.apply(ThemeData(brightness: brightness)),
        home: Scaffold(
          body: Center(
            child: SessionToolbarSurface(
              child: Builder(
                  builder: (context) => MenuAnchor(
                        style: DesktopSessionStyle.menuStyle(context),
                        menuChildren: [
                          MenuItemButton(
                            onPressed: () => selected = true,
                            child: const Text('Balanced'),
                          ),
                        ],
                        builder: (context, controller, child) => TextButton(
                          onPressed: controller.open,
                          child: const Text('Quality'),
                        ),
                      )),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Quality'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Balanced'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
