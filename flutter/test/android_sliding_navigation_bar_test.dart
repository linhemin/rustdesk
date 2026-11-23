import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/android_sliding_navigation_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android taps and held slides select the released tab',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
      builder: (_, setState) => Scaffold(
        bottomNavigationBar: AndroidSlidingNavigationBar(
          child: BottomNavigationBar(
            currentIndex: selected,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
            onTap: (index) => setState(() => selected = index),
          ),
        ),
      ),
    )));
    final home = tester.getCenter(find.byIcon(Icons.home));
    final settings = tester.getCenter(find.byIcon(Icons.settings));
    await tester.tapAt(settings);
    await tester.pumpAndSettle();
    expect(selected, 1);

    final slide = await tester.startGesture(settings);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await slide.moveTo(home);
    await slide.up();
    await tester.pumpAndSettle();
    expect(selected, 0);

    final outside = await tester.startGesture(home);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await outside.moveTo(settings - const Offset(0, 150));
    await outside.up();
    await tester.pumpAndSettle();
    expect(selected, 0);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
