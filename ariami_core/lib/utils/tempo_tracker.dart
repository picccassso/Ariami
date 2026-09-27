import 'dart:math' as math;
import 'dart:typed_data';

/// Estimates the tempo of the music from its drum hits, by finding the
/// spacing at which the last few seconds of hits best line up with
/// themselves (autocorrelation).
class TempoTracker {
  // Hits are gathered into 10 ms frames, 6 s of them.
  static const _frame = 0.01;
  static const _window = 600;
  // Beat spacings from 180 BPM down to 60 BPM.
  static const _minLag = 33;
  static const _maxLag = 100;
  // How strongly the hits must repeat to count as a steady beat.
  static const _minConfidence = 0.5;

  final _hits = Float64List(_window);
  int _head = 0;
  int _filled = 0;
  double _strongest = 0;
  double _frameTime = 0;
  double _sinceEstimate = 0;
  double _bpm = 0;

  /// Beats per minute, or 0 while there is no steady beat.
  double get bpm => _bpm;

  /// Takes the strength (0–1) of the hit heard over the last [dt] seconds.
  double update(double hit, double dt) {
    _strongest = math.max(_strongest, hit);
    _frameTime += dt;
    while (_frameTime >= _frame) {
      _frameTime -= _frame;
      // Each hit fades over a few frames, so hits a frame early or late
      // still line up.
      final last = _hits[(_head - 1) % _window];
      _hits[_head] = math.max(_strongest, last * 0.7);
      _head = (_head + 1) % _window;
      _filled = math.min(_filled + 1, _window);
      _strongest = 0;
      _sinceEstimate += _frame;
    }
    if (_filled == _window && _sinceEstimate >= 0.5) {
      _sinceEstimate = 0;
      _estimate();
    }
    return _bpm;
  }

  void _estimate() {
    double at(int n) => _hits[(_head + n) % _window];
    double correlation(int lag) {
      var sum = 0.0;
      for (var n = lag; n < _window; n++) {
        sum += at(n) * at(n - lag);
      }
      return sum / (_window - lag);
    }

    final energy = correlation(0);
    if (energy < 1e-4) {
      _bpm = 0;
      return;
    }
    final raw = [
      for (var lag = _minLag - 2; lag <= _maxLag + 2; lag++) correlation(lag),
    ];
    // Smoothed across neighbouring spacings: a beat that falls between two
    // frames splits its peak between them.
    final scores = [
      for (var i = 1; i < raw.length - 1; i++)
        0.25 * raw[i - 1] + 0.5 * raw[i] + 0.25 * raw[i + 1],
    ];
    var best = 0.0;
    var bestLag = 0;
    for (var lag = _minLag; lag <= _maxLag; lag++) {
      // Favour tempos near 130 BPM, so a beat isn't taken for its own half
      // or double. Centred a little high so drum & bass reads at 174, not
      // its half-time 87.
      final octaves = math.log(_bpmOf(lag.toDouble()) / 130) / math.ln2;
      final score =
          scores[lag - _minLag + 1] * math.exp(-0.5 * octaves * octaves);
      if (score > best) {
        best = score;
        bestLag = lag;
      }
    }
    final peak = scores[bestLag - _minLag + 1];
    if (peak / energy < _minConfidence) {
      _bpm = 0;
      return;
    }
    // Refine between frames by fitting a parabola through the peak.
    final before = scores[bestLag - _minLag];
    final after = scores[bestLag - _minLag + 2];
    final curve = before - 2 * peak + after;
    final shift = curve < 0 ? 0.5 * (before - after) / curve : 0.0;
    final estimate = _bpmOf(bestLag + shift.clamp(-0.5, 0.5));
    _bpm = _bpm == 0 ? estimate : _bpm + (estimate - _bpm) * 0.3;
  }

  static double _bpmOf(double lag) => 60 / (lag * _frame);
}
