import 'package:ariami_core/utils/music_voices.dart';
import 'package:test/test.dart';

void main() {
  const dt = 256 / 44100;

  // Feeds [bands] (kick, bass, snare, hats, centre mids, wide mids, wide
  // instruments, left and right highs, left and right mids) for [seconds]
  // and returns the last voices heard.
  MusicVoices feed(VoiceDetector detector, List<double> bands, double seconds) {
    var voices = MusicVoices.silent;
    for (var t = 0.0; t < seconds; t += dt) {
      voices = detector.update(bands, dt);
    }
    return voices;
  }

  test('a sudden jump in a drum band is a hit', () {
    final detector = VoiceDetector();
    feed(detector, [0.01, 0, 0.01, 0.002, 0, 0, 0, 0, 0, 0, 0], 1);
    final hit = detector.update([0.2, 0, 0.2, 0.05, 0, 0, 0, 0, 0, 0, 0], dt);
    expect(hit.kick, greaterThan(0.5));
    expect(hit.snare, greaterThan(0.5));
    expect(hit.hats, greaterThan(0.5));
  });

  test('centred mids read as vocals, wide ones as instruments', () {
    final centred =
        feed(VoiceDetector(), [0, 0, 0, 0, 0.1, 0.01, 0.01, 0, 0, 0, 0], 2);
    expect(centred.vocal, closeTo(0.5, 0.05));

    // Mids spread across the stereo image are not a lead vocal.
    final wide =
        feed(VoiceDetector(), [0, 0, 0, 0, 0.1, 0.1, 0.1, 0, 0, 0, 0], 2);
    expect(wide.vocal, 0);
    expect(wide.instruments, closeTo(0.5, 0.05));
  });

  test('a steady voice rests in the middle and swells above it', () {
    final detector = VoiceDetector();
    List<double> bass(double level) => [0, level, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    // Loud or quiet, a steady bass line rests at the middle.
    expect(feed(detector, bass(0.02), 6).bass, closeTo(0.5, 0.05));
    expect(feed(VoiceDetector(), bass(0.3), 6).bass, closeTo(0.5, 0.05));
    // Twice as loud (+6 dB) surges toward the top, then settles again.
    expect(feed(detector, bass(0.04), 0.5).bass, greaterThan(0.75));
    expect(feed(detector, bass(0.04), 20).bass, closeTo(0.5, 0.05));
    // A drop dips below the middle.
    expect(feed(detector, bass(0.02), 0.8).bass, lessThan(0.3));
  });

  test('silence moves nothing', () {
    final voices = feed(VoiceDetector(), List.filled(11, 0.0), 2);
    expect(voices.bass + voices.vocal + voices.instruments, 0);
  });

  test('pans follow the louder channel of each band', () {
    // Cymbals leaning left, instruments leaning right.
    final voices =
        feed(VoiceDetector(), [0, 0, 0, 0, 0, 0, 0, 0.03, 0.01, 0.01, 0.03], 2);
    expect(voices.drumPan, lessThan(-0.9));
    expect(voices.instrumentPan, greaterThan(0.9));

    // A centred mix sits in the middle.
    final centred =
        feed(VoiceDetector(), [0, 0, 0, 0, 0, 0, 0, 0.02, 0.02, 0.02, 0.02], 2);
    expect(centred.drumPan, closeTo(0, 1e-9));
    expect(centred.instrumentPan, closeTo(0, 1e-9));
  });

  test('a kick-band-only meter yields only kicks', () {
    final detector = VoiceDetector();
    feed(detector, [0.01], 1);
    expect(detector.update([0.2], dt).kick, greaterThan(0.5));
  });

  test('merging keeps the strongest hits and the latest loudness', () {
    const earlier = MusicVoices(kick: 0.8, bass: 0.2, vocal: 0.9);
    const later = MusicVoices(kick: 0.1, snare: 0.4, bass: 0.6, vocal: 0.3);
    final merged = earlier.merge(later);
    expect(merged.kick, 0.8);
    expect(merged.snare, 0.4);
    expect(merged.bass, 0.6);
    expect(merged.vocal, 0.3);
    expect(merged.held.kick, 0);
  });
}
