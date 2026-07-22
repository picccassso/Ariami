import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_stats_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late ListeningStatsStore store;

  final day1 = DateTime.utc(2026, 3, 1, 12).millisecondsSinceEpoch;
  final day2 = DateTime.utc(2026, 3, 2, 12).millisecondsSinceEpoch;

  ListeningEvent event({
    required String eventId,
    String songId = 'song-1',
    String? playId,
    int listenedMs = 0,
    int plays = 0,
    int? occurredAtMs,
    int tzOffsetMinutes = 0,
    String? title,
    String? artist,
  }) {
    return ListeningEvent(
      eventId: eventId,
      songId: songId,
      playId: playId,
      listenedMs: listenedMs,
      plays: plays,
      occurredAtMs: occurredAtMs ?? day1,
      tzOffsetMinutes: tzOffsetMinutes,
      songTitle: title,
      songArtist: artist,
    );
  }

  /// A Spotify import interleaved with real tracked history and a device
  /// baseline, plus a second user for isolation checks.
  void seedMixedHistory() {
    store.applyEvents('user-a', 'device-1', [
      // Spotify import: two songs across two days, one play marker.
      event(
        eventId: 'spotify:user-a:h1',
        listenedMs: 60000,
        title: 'Imported Song',
        artist: 'Imported Artist',
      ),
      event(
        eventId: 'spotify:user-a:h2',
        plays: 1,
        playId: 'sp-p1',
        title: 'Imported Song',
        artist: 'Imported Artist',
      ),
      event(
        eventId: 'spotify:user-a:h3',
        songId: 'song-2',
        listenedMs: 45000,
        occurredAtMs: day2,
        title: 'Imported Song 2',
        artist: 'Imported Artist',
      ),
      // Real tracked history.
      event(
        eventId: 'live-1',
        songId: 'song-3',
        listenedMs: 30000,
        title: 'Live Song',
        artist: 'Live Artist',
      ),
      event(
        eventId: 'live-2',
        songId: 'song-3',
        plays: 1,
        playId: 'live-p1',
        occurredAtMs: day2,
        title: 'Live Song',
        artist: 'Live Artist',
      ),
      // Device baseline import: all-time totals only, never the day grain.
      event(
        eventId: 'baseline:device-1:song-4',
        songId: 'song-4',
        listenedMs: 999000,
        plays: 42,
        title: 'Baseline Song',
        artist: 'Baseline Artist',
      ),
    ]);
    store.applyEvents('user-b', 'device-9', [
      event(eventId: 'b-live', songId: 'song-9', listenedMs: 7000),
    ]);
  }

  List<String> rawEventIds(String userId) {
    final raw = sqlite3.open('${tempDir.path}/listening_stats.db');
    try {
      return raw
          .select(
            'SELECT event_id FROM listening_events '
            'WHERE user_id = ? ORDER BY event_id',
            [userId],
          )
          .map((row) => row['event_id'] as String)
          .toList();
    } finally {
      raw.close();
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spotify_reset_test');
    store = ListeningStatsStore(
      databasePath: '${tempDir.path}/listening_stats.db',
    );
    store.initialize();
  });

  tearDown(() {
    store.close();
    tempDir.deleteSync(recursive: true);
  });

  test('removes only the source import and rebuilds rollups from survivors',
      () {
    seedMixedHistory();

    final deleted = store.resetUserBySource('user-a', 'spotify:');

    expect(deleted, 3);
    expect(rawEventIds('user-a'), [
      'baseline:device-1:song-4',
      'live-1',
      'live-2',
    ]);

    // All-time rollups reflect only the survivors.
    final summary = store.getSummary('user-a');
    expect(
      summary.songs.map((song) => song.songId),
      unorderedEquals(['song-3', 'song-4']),
    );
    expect(summary.totalListenedMs, 30000 + 999000);
    expect(summary.totalPlays, 1 + 42);

    // The day grain reflects only the survivors (baseline stays excluded).
    final daily = store.getDailyTotals('user-a', days: 400);
    expect(daily.keys, ['2026-03-01', '2026-03-02']);
    expect(daily['2026-03-01']!.listenedMs, 30000);
    expect(daily['2026-03-01']!.playCount, 0);
    expect(daily['2026-03-02']!.listenedMs, 0);
    expect(daily['2026-03-02']!.playCount, 1);

    // Artist rollups no longer credit the imported artist.
    final artists = store
        .getTopArtists('user-a')
        .map((artist) => artist.artistDisplay)
        .toList();
    expect(artists, containsAll(['Live Artist', 'Baseline Artist']));
    expect(artists, isNot(contains('Imported Artist')));

    // Other users are untouched.
    expect(store.getSummary('user-b').totalListenedMs, 7000);
  });

  test('treats SQL wildcard characters literally instead of widening reset',
      () {
    seedMixedHistory();

    for (final bad in ['', '   ']) {
      expect(
        () => store.resetUserBySource('user-a', bad),
        throwsArgumentError,
        reason: 'prefix "$bad"',
      );
    }

    // LIKE wildcards are ordinary characters in the exact prefix match.
    for (final literal in ['%', '%%', '_', 'spot%', 'spot_fy:']) {
      expect(store.resetUserBySource('user-a', literal), 0,
          reason: 'prefix "$literal"');
    }
    expect(store.resetUserBySource('user-a', 'other:'), 0);

    // Everything, import included, survives.
    final summary = store.getSummary('user-a');
    expect(summary.totalListenedMs, 60000 + 45000 + 30000 + 999000);
    expect(summary.totalPlays, 1 + 1 + 42);
    expect(store.getDailyTotals('user-a', days: 400), hasLength(2));
  });

  test('full resetUser still wipes everything', () {
    seedMixedHistory();

    store.resetUser('user-a');

    final summary = store.getSummary('user-a');
    expect(summary.songs, isEmpty);
    expect(summary.totalListenedMs, 0);
    expect(summary.totalPlays, 0);
    expect(store.getDailyTotals('user-a', days: 400), isEmpty);
    expect(store.getTopArtists('user-a'), isEmpty);
    expect(rawEventIds('user-a'), isEmpty);

    // Other users are untouched.
    expect(store.getSummary('user-b').totalListenedMs, 7000);
  });

  test('summary hasSpotifyImport tracks raw spotify events per user', () {
    // No events at all.
    expect(store.getSummary('user-a').hasSpotifyImport, isFalse);

    seedMixedHistory();

    // Mixed Spotify + normal events.
    expect(store.getSummary('user-a').hasSpotifyImport, isTrue);

    // Per-user isolation: user-b holds only normal events.
    expect(store.getSummary('user-b').hasSpotifyImport, isFalse);

    // Once resetUserBySource removes the Spotify rows, the flag clears.
    store.resetUserBySource('user-a', 'spotify:');
    expect(store.getSummary('user-a').hasSpotifyImport, isFalse);

    // A normal-only history never sets the flag.
    store.applyEvents('user-c', 'device-7', [
      event(eventId: 'c-live', songId: 'song-c', listenedMs: 1000),
    ]);
    expect(store.getSummary('user-c').hasSpotifyImport, isFalse);
  });
}
