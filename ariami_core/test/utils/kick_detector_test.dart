import 'dart:math' as math;

import 'package:ariami_core/utils/kick_detector.dart';
import 'package:test/test.dart';

void main() {
  const dt = 256 / 44100; // one native reading

  /// Feeds [seconds] of kick-band envelope from [level] (a function of time)
  /// and returns the strongest kick detected in each 0.5 s beat.
  List<double> run(double Function(double t) level, {double seconds = 6}) {
    final detector = KickDetector();
    final beats = List<double>.filled((seconds / 0.5).ceil(), 0);
    for (var t = 0.0; t < seconds; t += dt) {
      final kick = detector.update(level(t), dt);
      final beat = (t / 0.5).floor();
      beats[beat] = math.max(beats[beat], kick);
    }
    return beats.sublist(2); // let the detector settle
  }

  /// A kick every 0.5 s: jumps to [peak] above [bed], decaying in ~60 ms.
  double Function(double) kicks(double peak, double bed) =>
      (t) => bed + peak * math.exp(-(t % 0.5) / 0.06);

  test('silence never kicks', () {
    expect(run((_) => 0.001 * math.Random(1).nextDouble()), everyElement(0));
  });

  test('a steady level, however loud, never kicks', () {
    expect(run((_) => 0.4), everyElement(0));
  });

  test('every kick lands at full strength', () {
    expect(run(kicks(0.3, 0.02)), everyElement(greaterThan(0.9)));
  });

  test('kicks still land on top of a loud sustained bass line', () {
    // The bass sits at twice the kick's own jump: a level-based meter reads
    // this as nearly constant, but the rise still stands out.
    expect(run(kicks(0.15, 0.3)), everyElement(greaterThan(0.9)));
  });

  test('quiet and loud masters kick alike', () {
    expect(run(kicks(0.03, 0.005)), everyElement(greaterThan(0.9)));
  });

  test('small wobbles between kicks are ignored', () {
    final detector = KickDetector();
    var strongestWobble = 0.0;
    for (var t = 0.0; t < 6; t += dt) {
      final wobble = 0.01 * math.sin(t * 2 * math.pi * 7);
      final kick = detector.update(kicks(0.3, 0.1)(t) + wobble, dt);
      // Between kicks: after the hit has decayed.
      if (t > 1 && t % 0.5 > 0.25) {
        strongestWobble = math.max(strongestWobble, kick);
      }
    }
    expect(strongestWobble, 0);
  });
}
