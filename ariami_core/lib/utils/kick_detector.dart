import 'dart:math' as math;

/// Turns a kick-band (35–150 Hz) energy envelope into kick strengths (0–1).
///
/// A kick is a sudden jump in low-end energy, so this scores how far each
/// reading rises above the last ~50 ms, relative to the biggest recent rises.
/// Measuring the rise — not the level — lets a kick land on top of a
/// sustained bass line, and normalising it makes quiet and loud masters hit
/// alike.
class KickDetector {
  // Below this (≈ -50 dBFS) is silence: no kicks, whatever the rise.
  static const _floor = 0.003;
  // Smallest rise treated as a full kick, so near-silent passages don't
  // magnify small wobbles into hits.
  static const _minPeak = 0.01;
  // Rises below this share of a full kick are ignored as ordinary movement.
  static const _gate = 0.2;

  double? _reference;
  double _peakRise = _minPeak;

  double update(double level, double dt) {
    final reference = _reference ?? level;
    final rise = level - reference;
    _reference = reference + (level - reference) * _ease(dt, 0.05);
    _peakRise =
        math.max(rise, _peakRise + (_minPeak - _peakRise) * _ease(dt, 4));
    if (level < _floor || rise <= 0) return 0;
    final strength = (rise / _peakRise).clamp(0.0, 1.0);
    return math.max(0, (strength - _gate) / (1 - _gate));
  }

  static double _ease(double dt, double seconds) => 1 - math.exp(-dt / seconds);
}
