import 'dart:async';
import 'dart:math' as math;

import 'package:ariami_core/utils/kick_detector.dart';
import 'package:just_audio/just_audio.dart';

/// Detects kicks in this device's playback, for UI that follows the music.
///
/// Metering is on while at least one holder has [acquire]d it. [sample]
/// returns the strongest kick heard since the previous call and requests
/// fresh readings, so holders simply call it once per frame. Readings arrive
/// already aligned to the playhead by the native meter.
class AudioLevelMeter {
  AudioLevelMeter._();

  static final instance = AudioLevelMeter._();

  final _detector = KickDetector();
  int _holders = 0;
  bool _reading = false;
  double _kick = 0;

  void acquire() {
    if (_holders++ == 0) unawaited(_setEnabled(true));
  }

  void release() {
    if (--_holders > 0) return;
    _holders = 0;
    _kick = 0;
    unawaited(_setEnabled(false));
  }

  /// Strength (0–1) of the strongest kick heard since the previous call.
  double sample() {
    if (_holders > 0 && !_reading) {
      _reading = true;
      unawaited(_read());
    }
    final kick = _kick;
    _kick = 0;
    return kick;
  }

  Future<void> _read() async {
    try {
      final levels = await NativeLevelMeter.levels();
      if (levels == null || _holders == 0) return;
      for (final level in levels.values) {
        _kick = math.max(_kick, _detector.update(level, levels.blockSeconds));
      }
    } catch (_) {
      // No meter on this platform: the backdrop just drifts.
    } finally {
      _reading = false;
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      await NativeLevelMeter.setEnabled(enabled);
    } catch (_) {}
  }
}
