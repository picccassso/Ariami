import 'dart:async';
import 'dart:collection';

import 'package:ariami_core/utils/music_voices.dart';

import '../player_host.dart';

class AudioLevelMeter {
  AudioLevelMeter._();

  static final instance = AudioLevelMeter._();

  static const _sameFrame = Duration(milliseconds: 4);

  final _clock = Stopwatch()..start();
  final _pending = Queue<({Duration at, MusicVoices voices})>();
  final _detector = VoiceDetector();
  LevelMeterBackend? _backend;
  int _holders = 0;
  bool _reading = false;
  Duration _sampledAt = -_sameFrame;
  MusicVoices _heard = MusicVoices.silent;

  void configure(LevelMeterBackend? backend) {
    if (identical(_backend, backend)) return;
    if (_holders > 0) unawaited(_setEnabled(false));
    _backend = backend;
    if (_holders > 0) unawaited(_setEnabled(true));
  }

  void acquire() {
    if (_holders++ == 0) unawaited(_setEnabled(true));
  }

  void release() {
    if (--_holders > 0) return;
    _holders = 0;
    _pending.clear();
    _heard = MusicVoices.silent;
    unawaited(_setEnabled(false));
  }

  MusicVoices sample() {
    final due = _clock.elapsed;
    if (due - _sampledAt < _sameFrame) return _heard;
    _sampledAt = due;
    if (_holders > 0 && !_reading && (_backend?.isSupported ?? false)) {
      _reading = true;
      unawaited(_read());
    }
    var voices = _heard.held;
    while (_pending.isNotEmpty && _pending.first.at <= due) {
      voices = voices.merge(_pending.removeFirst().voices);
    }
    return _heard = voices;
  }

  Future<void> _read() async {
    try {
      final backend = _backend;
      if (backend == null || !backend.isSupported) return;
      final reading = await backend.read();
      if (reading == null) return;
      for (final bands in reading.readings) {
        _add(_detector.update(bands, reading.blockSeconds), reading.latency);
      }
    } catch (_) {
    } finally {
      _reading = false;
    }
  }

  void _add(MusicVoices voices, Duration latency) {
    if (_holders > 0) {
      _pending.add((at: _clock.elapsed + latency, voices: voices));
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      final backend = _backend;
      if (backend != null && backend.isSupported) {
        await backend.setEnabled(enabled);
      }
    } catch (_) {}
  }
}
