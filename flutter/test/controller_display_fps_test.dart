import 'dart:async';

import 'package:flutter_hbb/common/controller_display_fps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing screen or power policy updates the session once per rate',
      () async {
    var screen = 59.94;
    int? native = 120;
    final requests = <int?>[];
    final display = ControllerDisplayFps(
        () => screen, () async => native, (rate) async => requests.add(rate));
    await display.refresh();
    native = 60;
    await display.refresh();
    await display.refresh();
    native = null;
    await display.refresh();
    screen = 144;
    await display.refresh();
    screen = 0;
    await display.refresh();
    expect(requests, [120, 60, 120, null]);
  });

  test('a delayed screen read cannot update a closed session', () async {
    final result = Completer<int?>();
    final requests = <int?>[];
    final display = ControllerDisplayFps(
        () => 60, () => result.future, (rate) async => requests.add(rate));
    final read = display.refresh();
    display.dispose();
    result.complete(120);
    await read;
    expect(requests, isEmpty);
  });
}
