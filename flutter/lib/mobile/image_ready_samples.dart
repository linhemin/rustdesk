/// Counts images available to the Flutter painter. Pixel upload and image
/// creation use the local monotonic clock, independently of transport RTT.
class ImageReadySamples {
  DateTime? _start;
  DateTime? _sample;
  int _frames = 0;
  int _totalUs = 0;
  int _fps = 0;
  int _meanMs = 0;

  void reset() {
    _start = null;
    _sample = null;
    _frames = 0;
    _totalUs = 0;
  }

  void add(DateTime now, int uploadUs) {
    final start = _start;
    if (start == null || now.isBefore(start) ||
        now.difference(start) > const Duration(seconds: 3)) {
      reset();
      _start = now;
      return;
    }
    _frames++;
    _totalUs += uploadUs;
    final elapsed = now.difference(start).inMicroseconds;
    if (elapsed < 1000000) return;
    _fps = (_frames * 1000000 / elapsed).round();
    _meanMs = (_totalUs / _frames / 1000).round();
    _sample = now;
    _start = now;
    _frames = 0;
    _totalUs = 0;
  }

  String format(DateTime opened, DateTime now) {
    final sample = _sample;
    if (sample == null || sample.isBefore(opened) || now.isBefore(sample) ||
        now.difference(sample) > const Duration(seconds: 3)) return '';
    return ' imageReadyFps=$_fps rgbaToImageMeanMs=$_meanMs';
  }
}
