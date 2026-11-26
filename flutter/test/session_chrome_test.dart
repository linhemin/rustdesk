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

    testWidgets(
        'session toolbar pill enforces uniform icon size and compact mode in $brightness',
        (tester) async {
      var statusTapped = false;
      await tester.pumpWidget(MaterialApp(
        theme: WorkspaceStyle.apply(ThemeData(brightness: brightness)),
        home: Scaffold(
          body: Center(
            child: SessionToolbarSurface(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SessionStatusPill(
                      dotColor: const Color(0xFF10B981),
                      label: 'TCP · 0 ms',
                      active: true,
                      onPressed: () => statusTapped = true,
                    ),
                    const SessionToolbarDivider(horizontal: true),
                    const SessionToolbarPillVisual(
                      icon: Icon(Icons.folder_open_rounded),
                      label: 'Transfer file',
                    ),
                    const SessionToolbarPillVisual(
                      icon: Icon(Icons.tune_rounded),
                      label: 'Image Quality',
                      hasDropdown: true,
                      open: true,
                    ),
                    const SessionToolbarPillVisual(
                      icon: Icon(Icons.terminal_rounded),
                      label: 'Terminal',
                      compact: true,
                    ),
                    const SessionToolbarPillVisual(
                      icon: Icon(Icons.close_rounded),
                      label: 'Disconnect',
                      destructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('TCP · 0 ms'), findsOneWidget);
      expect(find.text('Transfer file'), findsOneWidget);
      expect(find.text('Image Quality'), findsOneWidget);
      // Compact vertical mode hides the text label while preserving the icon.
      expect(find.text('Terminal'), findsNothing);
      expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
      // Dropdown visual shows rotated chevron when open.
      final rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.turns, 0.5);
      // Folder icon inherits DesktopSessionStyle.iconSize instead of 24px default.
      final folderSize = tester.getSize(find.byIcon(Icons.folder_open_rounded));
      expect(folderSize.width, DesktopSessionStyle.iconSize);
      expect(folderSize.height, DesktopSessionStyle.iconSize);

      await tester.tap(find.text('TCP · 0 ms'));
      await tester.pump();
      expect(statusTapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
