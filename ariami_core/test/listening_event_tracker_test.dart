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

  test('onTrackCompleted counts a short track that never crossed the threshold',
      () {
    const short = ListeningTrackInfo(songId: 'short-2', durationMs: 20000);
    tracker.onTrackChanged(short);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 8000); // below the 10s (50%) threshold

    tracker.onTrackCompleted();
    expect(plays(), hasLength(1));

    // Redundant completion notifications never double-count.
    tracker.onTrackCompleted();
    expect(plays(), hasLength(1));
  });

  test('onTrackCompleted never counts tracks at or above the 30s threshold',
      () {
    tracker.onTrackChanged(track); // 200s track
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 10000);

    tracker.onTrackCompleted();
    expect(plays(), isEmpty);
  });

  test('onTrackCompleted no-ops when the play already counted honestly', () {
    const short = ListeningTrackInfo(songId: 'short-3', durationMs: 20000);
    tracker.onTrackChanged(short);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 20000); // full listen: play counted at 50%
    expect(plays(), hasLength(1));

    tracker.onTrackCompleted();
    expect(plays(), hasLength(1));
  });

  test('trusted forward jumps credit coalesced background progress', () {
    final trusted = ListeningEventTracker(
      onEvent: events.add,
      trustPlayingForwardJumps: true,
    );
    trusted.onTrackChanged(track);
    trusted.onPlayingChanged(true);
    trusted.onPositionTick(0);
    trusted.onPositionTick(45000); // one coalesced background jump
    trusted.stop();

    expect(listenedTotal(), 45000);
    expect(plays(), hasLength(1));
  });

  test('trusted forward jumps still never credit an explicitly-notified seek',
      () {
    final trusted = ListeningEventTracker(
      onEvent: events.add,
      trustPlayingForwardJumps: true,
    );
    trusted.onTrackChanged(track);
    trusted.onPlayingChanged(true);
    trusted.onPositionTick(0);
    trusted.onPositionTick(1000); // +1s
    trusted.onSeek();
    trusted.onPositionTick(80000); // re-anchor only
    trusted.onPositionTick(81000); // +1s
    trusted.stop();

    expect(listenedTotal(), 2000);
    expect(plays(), isEmpty);
  });

  test('detectRestarts: false keeps one play-action across backward wraps',
      () {
    final sessionDriven = ListeningEventTracker(
      onEvent: events.add,
      detectRestarts: false,
    );
    const loop = ListeningTrackInfo(songId: 'loop-2', durationMs: 90000);
    sessionDriven.onTrackChanged(loop);
    sessionDriven.onPlayingChanged(true);
    sessionDriven.onPositionTick(0);

    var pos = 0;
    void forward(int ms) {
      final end = pos + ms;
      while (pos < end) {
        pos += 500;
        sessionDriven.onPositionTick(pos);
      }
    }

    forward(40000); // play counted at 30s
    pos = 0;
    sessionDriven.onPositionTick(0); // un-notified wrap to the start
    forward(31000);
    sessionDriven.stop();

    // The play-action never split, so the wrap can't earn a second play,
    // while every honest second is still credited.
    expect(plays(), hasLength(1));
    expect(listenedTotal(), 40000 + 31000);
  });

  test('a configured checkpoint interval emits segments at that cadence', () {
    final frequent = ListeningEventTracker(
      onEvent: events.add,
      checkpointMs: 15000,
    );
    frequent.onTrackChanged(track);
    frequent.onPlayingChanged(true);
    frequent.onPositionTick(0);
    var pos = 0;
    while (pos < 35000) {
      pos += 500;
      frequent.onPositionTick(pos);
    }
    frequent.stop();

    final segments = events.where((e) => e.listenedMs > 0).toList();
    expect(segments.map((e) => e.listenedMs), [15000, 15000, 5000]);
    expect(listenedTotal(), 35000);
  });

  test('copies source context and client kind onto every event', () {
    final contextual = ListeningEventTracker(
      onEvent: events.add,
      clientKind: 'desktop',
    );
    const fromPlaylist = ListeningTrackInfo(
      songId: 'song-ctx',
      durationMs: 200000,
      sourceKind: 'playlist',
      playlistId: 'pl-9',
    );
    contextual.onTrackChanged(fromPlaylist);
    contextual.onPlayingChanged(true);
    contextual.onPositionTick(0);
    var pos = 0;
    while (pos < 31000) {
      pos += 500;
      contextual.onPositionTick(pos);
    }
    contextual.stop();

    expect(events, isNotEmpty);
    for (final event in events) {
      expect(event.sourceKind, 'playlist');
      expect(event.playlistId, 'pl-9');
      expect(event.clientKind, 'desktop');
    }
  });

  test('events without source context leave the fields unset', () {
    tracker.onTrackChanged(track);
    tracker.onPlayingChanged(true);
    tracker.onPositionTick(0);
    playForward(0, 31000);
    tracker.stop();

    expect(events, isNotEmpty);
    for (final event in events) {
      expect(event.sourceKind, isNull);
      expect(event.playlistId, isNull);
      expect(event.clientKind, isNull);
    }
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
