import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AndroidSlidingNavigationBar extends StatelessWidget {
  const AndroidSlidingNavigationBar({super.key, required this.child});

  final BottomNavigationBar child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return child;
    return Builder(
        builder: (barContext) => GestureDetector(
              onLongPressEnd: (details) {
                final box = barContext.findRenderObject();
                if (box is! RenderBox ||
                    !(Offset.zero & box.size).contains(details.localPosition)) {
                  return;
                }
                final index = (details.localPosition.dx /
                        box.size.width *
                        child.items.length)
                    .floor();
                child.onTap?.call(index);
              },
              child: child,
            ));
  }
}
