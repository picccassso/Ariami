import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_event_tracker.dart';
import 'package:test/test.dart';

void main() {
  late List<ListeningEvent> events;
  late ListeningEventTracker tracker;

  const track = ListeningTrackInfo(
    songId: 'song-1',
    title: 'Song',
    artist: 'Artist',
    durationMs: 200000,
  );

  setUp(() {
    events = <ListeningEvent>[];
    tracker = ListeningEventTracker(onEvent: events.add);
  });

  /// Simulates steady playback ticks of [ms] total in 500ms steps.
  int playForward(int fromMs, int ms) {
    var pos = fromMs;
    final end = fromMs + ms;
    while (pos < end) {
      pos += 500;
      tracker.onPositionTick(pos);
    }
    return pos;
  }

  List<ListeningEvent> plays() => events.where((e) => e.plays > 0).toList();
  int listenedTotal() =>
      events.fold(0, (sum, e) => sum + e.listenedMs);

  test('counts a play once after 30 seconds of cumulative listening', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);

    playForward(0, 29000);
    expect(plays(), isEmpty);

    playForward(29000, 2000);
    expect(plays(), hasLength(1));
    expect(plays().single.playId, isNotNull);

    // Keeps listening: still just one play for this play-action.
    playForward(31000, 60000);
    expect(plays(), hasLength(1));
  });

  test('uses 50% of the track when that is under 30 seconds', () {
    const short = ListeningTrackInfo(songId: 'short-1', durationMs: 20000);
    tracker.onTrackChanged(short);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);

    playForward(0, 9000);
    expect(plays(), isEmpty);
    playForward(9000, 2000);
    expect(plays(), hasLength(1));
  });

  test('scrubbing forward does not credit listening time', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);

    playForward(0, 10000); // 10s real listening
    tracker.onPositionTick(150000); // scrub jump
    playForward(150000, 5000); // 5s more real listening
    tracker.stop();

    expect(listenedTotal(), 15000);
    expect(plays(), isEmpty); // only 15s of honest listening
  });

  test('scrubbing back and forth cannot inflate time or plays', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(100000);

    for (var i = 0; i < 20; i++) {
      tracker.onPositionTick(150000); // jump forward
      tracker.onPositionTick(100000); // jump back mid-track
    }
    tracker.stop();

    expect(listenedTotal(), 0);
    expect(plays(), isEmpty);
  });

  test('pause and resume keeps one play-action (no double play)', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 20000);

    tracker.onPlayingChanged(false);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(20000); // re-anchor
    playForward(20000, 15000);

    expect(plays(), hasLength(1)); // 35s cumulative crossed once
    tracker.stop();
    expect(listenedTotal(), 35000);
  });

  test('seek while paused is never credited', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 5000);

    tracker.onPlayingChanged(false);
    tracker.onPositionTick(120000); // position updates while paused
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(120000);
    playForward(120000, 5000);
    tracker.stop();

    expect(listenedTotal(), 10000);
  });

  test('repeat-one counts each full listen but never duplicates seconds', () {
    const loop = ListeningTrackInfo(songId: 'loop-1', durationMs: 90000);
    tracker.onTrackChanged(loop);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);

    playForward(0, 90000); // first full listen
    tracker.onPositionTick(0); // engine wraps to the start
    playForward(0, 90000); // second full listen
    tracker.onPositionTick(0);
    playForward(0, 40000); // third partial listen
    tracker.stop();

    expect(plays(), hasLength(3));
    // Each play belongs to a distinct play-action.
    expect(plays().map((e) => e.playId).toSet(), hasLength(3));
    expect(listenedTotal(), 90000 + 90000 + 40000);
  });

  test('track changes finalize the previous play-action', () {
    const other = ListeningTrackInfo(songId: 'song-2', durationMs: 100000);
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 10000);

    tracker.onTrackChanged(other);
    tracker.onPositionTick(0);
    playForward(0, 31000);
    tracker.stop();

    // 10s segment for song-1, 31s + one play for song-2.
    expect(
      events.where((e) => e.songId == 'song-1').fold(0, (s, e) => s + e.listenedMs),
      10000,
    );
    expect(plays().single.songId, 'song-2');
  });

  test('checkpoints long listens into multiple segments', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 95000);
    tracker.stop();

    final segments = events.where((e) => e.listenedMs > 0).toList();
    expect(segments.length, greaterThanOrEqualTo(3));
    expect(listenedTotal(), 95000);
    // All events carry unique ids.
    expect(events.map((e) => e.eventId).toSet(), hasLength(events.length));
  });
}
