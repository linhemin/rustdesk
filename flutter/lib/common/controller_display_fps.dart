import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A screen's declared refresh rate does not drop when the desktop goes idle.
class ControllerDisplayFps {
  final double Function() viewRefreshRate;
  final Future<int?> Function()? nativeRefreshRate;
  final Future<void> Function(int?) send;
  int? hz;
  bool _busy = false;
  bool _disposed = false;

  ControllerDisplayFps(this.viewRefreshRate, this.nativeRefreshRate, this.send);

  void dispose() => _disposed = true;

  Future<void> refresh() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      int? native;
      try {
        native = await nativeRefreshRate?.call();
      } on MissingPluginException {
        // Older platform runners still report their screen through Flutter.
      } on PlatformException catch (e) {
        debugPrint('Unable to read screen refresh rate: ${e.code}');
      }
      if (_disposed) return;
      final rate = native != null && native > 0
          ? native.toDouble()
          : viewRefreshRate();
      final limit = rate.isFinite && rate >= 15 && rate <= 1000
          ? rate.round().clamp(15, 120).toInt()
          : null;
      if (hz == limit) return;
      await send(limit);
      if (!_disposed) hz = limit;
    } finally {
      _busy = false;
    }
  }
}
