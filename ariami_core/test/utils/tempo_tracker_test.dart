import 'dart:math' as math;

import 'package:ariami_core/utils/tempo_tracker.dart';
import 'package:test/test.dart';

void main() {
  const dt = 256 / 44100;

  // Feeds [seconds] of readings, each hit as strong as [hitAt] says.
  double feed(
      TempoTracker tracker, double seconds, double Function(int) hitAt) {
    var bpm = 0.0;
    for (var n = 0; n * dt < seconds; n++) {
      bpm = tracker.update(hitAt(n), dt);
    }
    return bpm;
  }

  // Kick or snare on every beat at [bpm], with a quieter hat on each
  // off-beat.
  double Function(int) beat(double bpm) {
    final spacing = 60 / bpm / dt;
    return (n) => (n % spacing) < 1
        ? 1
        : ((n + spacing / 2) % spacing) < 1
            ? 0.3
            : 0;
  }

  for (final bpm in [72.0, 95.0, 120.0, 150.0, 174.0]) {
    test('finds $bpm BPM', () {
      expect(feed(TempoTracker(), 12, beat(bpm)), closeTo(bpm, bpm * 0.04));
    });
  }

  test('follows a change of tempo', () {
    final tracker = TempoTracker();
    feed(tracker, 10, beat(90));
    expect(feed(tracker, 12, beat(140)), closeTo(140, 6));
  });

  test('finds no beat in silence or in scattered hits', () {
    expect(feed(TempoTracker(), 10, (_) => 0), 0);
    final random = math.Random(1);
    expect(
      feed(TempoTracker(), 10, (_) => random.nextDouble() < 0.02 ? 1 : 0),
      0,
    );
  });
}
