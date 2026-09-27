import 'dart:math' as math;

import 'kick_detector.dart';
import 'tempo_tracker.dart';

/// What the music playing here is doing, each 0–1. The drums ([kick],
/// [snare], [hats]) are hit strengths; the rest are loudness within their
/// own recent range (0.5 steady, higher swelling, lower dipping). [drumPan] and [instrumentPan] say where in the stereo
/// image the kit and the instruments sit, from -1 (left) to 1 (right), and
/// [tempo] how fast the beat is.
class MusicVoices {
  const MusicVoices({
    this.kick = 0,
    this.bass = 0,
    this.snare = 0,
    this.hats = 0,
    this.vocal = 0,
    this.instruments = 0,
    this.drumPan = 0,
    this.instrumentPan = 0,
    this.tempo = 0,
  });

  static const silent = MusicVoices();

  final double kick;
  final double bass;
  final double snare;
  final double hats;
  final double vocal;
  final double instruments;

  /// Measured on the cymbals and hi-hats, which carry most of a kit's
  /// stereo spread (the kick and snare usually sit dead centre).
  final double drumPan;
  final double instrumentPan;

  /// Beats per minute, or 0 while there is no steady beat.
  final double tempo;

  /// The strongest hits of this and [later], with [later]'s loudness.
  MusicVoices merge(MusicVoices later) => MusicVoices(
        kick: math.max(kick, later.kick),
        bass: later.bass,
        snare: math.max(snare, later.snare),
        hats: math.max(hats, later.hats),
        vocal: later.vocal,
        instruments: later.instruments,
        drumPan: later.drumPan,
        instrumentPan: later.instrumentPan,
        tempo: later.tempo,
      );

  /// Everything but the hits.
  MusicVoices get held => MusicVoices(
        bass: bass,
        vocal: vocal,
        instruments: instruments,
        drumPan: drumPan,
        instrumentPan: instrumentPan,
        tempo: tempo,
      );
}

/// Pulls [MusicVoices] out of metered band levels (the eleven bands of
/// `NativeLevels`, in order). A player metering only the kick band yields
/// only kicks.
class VoiceDetector {
  final _kick = KickDetector();
  final _snare = KickDetector(floor: 0.002, minPeak: 0.008);
  final _hatHits = KickDetector(floor: 0.0005, minPeak: 0.004);
  final _hats = _Loudness(0.01, 0.15, floor: 0.0005);
  final _bass = _Loudness(0.06, 0.35, floor: 0.003);
  final _vocal = _Loudness(0.08, 0.45, floor: 0.002);
  final _instruments = _Loudness(0.3, 1.2, floor: 0.001);
  final _drumPan = _Pan(0.05, floor: 0.0005);
  final _instrumentPan = _Pan(0.3, floor: 0.001);
  final _tempo = TempoTracker();

  MusicVoices update(List<double> bands, double dt) {
    final kick = _kick.update(bands.first, dt);
    if (bands.length < 11) {
      return MusicVoices(kick: kick, tempo: _tempo.update(kick, dt));
    }
    final snare = _snare.update(bands[2], dt);
    final hatHit = _hatHits.update(bands[3], dt);
    // The centre's mids less their stereo spread: mostly the lead vocal.
    final centre = bands[4] * bands[4] - bands[5] * bands[5];
    return MusicVoices(
      kick: kick,
      bass: _bass.update(bands[1], dt),
      snare: snare,
      hats: math.max(hatHit, 0.5 * _hats.update(bands[3], dt)),
      vocal: _vocal.update(math.sqrt(math.max(0, centre)), dt),
      instruments: _instruments.update(bands[6], dt),
      drumPan: _drumPan.update(bands[7], bands[8], dt),
      instrumentPan: _instrumentPan.update(bands[9], bands[10], dt),
      // Kick and snare mark the beat; hats mostly subdivide it.
      tempo: _tempo.update(
        math.min(1, kick + snare + 0.3 * hatHit),
        dt,
      ),
    );
  }
}

/// Loudness as movement: where the level sits within its own range over
/// the last few seconds, in decibels. A steady part rests at 0.5, a swell
/// rises toward 1 and a dip falls toward 0, whatever the master's loudness.
/// Eases in over [attack] and out over [release] seconds; below [floor] is
/// silence (0).
class _Loudness {
  _Loudness(this.attack, this.release, {required this.floor});

  // The narrowest range a level is spread over, so a flat passage's small
  // wobbles aren't magnified into swells.
  static const _minRange = 9.0;
  // How quickly the range forgets louder and quieter moments, in seconds.
  static const _memory = 4.0;

  final double attack;
  final double release;
  final double floor;
  double? _high;
  double? _low;
  double _value = 0;

  double update(double level, double dt) {
    var target = 0.0;
    if (level >= floor) {
      final db = 20 * math.log(level) / math.ln10;
      final high = _high ?? db;
      final low = _low ?? db;
      _high = math.max(db, high + (db - high) * _ease(dt, _memory));
      _low = math.min(db, low + (db - low) * _ease(dt, _memory));
      final range = math.max(_high! - _low!, _minRange);
      target = (0.5 + (db - (_high! + _low!) / 2) / range).clamp(0.0, 1.0);
    }
    _value += (target - _value) * _ease(dt, target > _value ? attack : release);
    return _value;
  }

  static double _ease(double dt, double seconds) => 1 - math.exp(-dt / seconds);
}

/// Where a band sits between the left and right channels, from -1 (left) to
/// 1 (right), easing over [seconds]. Mixes rarely pan anything hard, so small
/// leans are magnified; below [floor] the band is silent and drifts to the
/// middle.
class _Pan {
  _Pan(this.seconds, {required this.floor});

  final double seconds;
  final double floor;
  double _value = 0;

  double update(double left, double right, double dt) {
    final total = left + right;
    final target =
        total < floor ? 0.0 : (3 * (right - left) / total).clamp(-1.0, 1.0);
    _value += (target - _value) * _Loudness._ease(dt, seconds);
    return _value;
  }
}
