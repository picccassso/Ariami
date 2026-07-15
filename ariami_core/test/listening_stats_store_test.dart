import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_stats_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late ListeningStatsStore store;

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
    String? albumId,
    String? album,
    String? albumArtist,
  }) {
    return ListeningEvent(
      eventId: eventId,
      songId: songId,
      playId: playId,
      listenedMs: listenedMs,
      plays: plays,
      occurredAtMs:
          occurredAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      tzOffsetMinutes: tzOffsetMinutes,
      songTitle: title,
      songArtist: artist,
      albumId: albumId,
      album: album,
      albumArtist: albumArtist,
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('listening_stats_test');
    store = ListeningStatsStore(
      databasePath: '${tempDir.path}/listening_stats.db',
    );
    store.initialize();
  });

  tearDown(() {
    store.close();
    tempDir.deleteSync(recursive: true);
  });

  test('accepts events and aggregates rollups per user', () {
    final result = store.applyEvents('user-a', 'device-1', [
      event(eventId: 'e1', listenedMs: 30000, title: 'Song', artist: 'Artist'),
      event(eventId: 'e2', plays: 1, playId: 'p1'),
      event(eventId: 'e3', listenedMs: 15000),
    ]);

    expect(result.accepted, 3);
    expect(result.duplicates, 0);

    final summary = store.getSummary('user-a');
    expect(summary.songs, hasLength(1));
    expect(summary.songs.first.listenedMs, 45000);
    expect(summary.songs.first.playCount, 1);
    expect(summary.songs.first.songTitle, 'Song');
    expect(summary.totalListenedMs, 45000);
    expect(summary.totalPlays, 1);

    // Another user's stats are isolated.
    expect(store.getSummary('user-b').songs, isEmpty);
  });

  test('re-uploading the same eventIds is idempotent', () {
    final events = [
      event(eventId: 'e1', listenedMs: 30000),
      event(eventId: 'e2', plays: 1, playId: 'p1'),
    ];

    final first = store.applyEvents('user-a', 'device-1', events);
    final second = store.applyEvents('user-a', 'device-1', events);

    expect(first.accepted, 2);
    expect(second.accepted, 0);
    expect(second.duplicates, 2);

    final summary = store.getSummary('user-a');
    expect(summary.totalListenedMs, 30000);
    expect(summary.totalPlays, 1);
  });

  test('a play-action can only ever count one play, even under fresh eventIds',
      () {
    store.applyEvents('user-a', 'device-1', [
      event(eventId: 'e1', plays: 1, playId: 'p1'),
    ]);
    // Buggy client retries the same play-action with a different eventId.
    store.applyEvents('user-a', 'device-1', [
      event(eventId: 'e2', plays: 1, playId: 'p1'),
    ]);

    expect(store.getSummary('user-a').totalPlays, 1);

    // Rollups rebuilt from the raw log agree (the log stores the retried
    // play with plays zeroed).
    store.rebuildRollups('user-a');
    expect(store.getSummary('user-a').totalPlays, 1);
  });

  test('mixes listening time from multiple devices for one account', () {
    // 20 "hours" offline on mobile, 30 online across desktop + TV.
    store.applyEvents('user-a', 'mobile-1', [
      event(eventId: 'm1', listenedMs: 20 * 60000),
    ]);
    store.applyEvents('user-a', 'desktop-1', [
      event(eventId: 'd1', listenedMs: 18 * 60000),
    ]);
    store.applyEvents('user-a', 'tv-1', [
      event(eventId: 't1', listenedMs: 12 * 60000),
    ]);

    expect(store.getSummary('user-a').totalListenedMs, 50 * 60000);
  });

  test('rejects malformed events without failing the batch', () {
    final result = store.applyEvents('user-a', 'device-1', [
      event(eventId: 'ok', listenedMs: 1000),
      event(eventId: 'zero'), // no time, no plays
      event(eventId: 'neg', listenedMs: -5),
    ]);

    expect(result.accepted, 1);
    expect(result.rejected, 2);
  });

  test('event JSON parser tolerates malformed optional fields', () {
    final parsed = ListeningEvent.tryFromJson(<String, dynamic>{
      'eventId': 'e1',
      'songId': 'song-1',
      'playId': 123,
      'listenedMs': 'not-a-number',
      'plays': <String>[],
      'occurredAtMs': false,
      'tzOffsetMinutes': 'UTC',
      'songTitle': 42,
      'songDurationMs': 'long',
    });

    expect(parsed, isNotNull);
    expect(parsed!.playId, isNull);
    expect(parsed.listenedMs, 0);
    expect(parsed.plays, 0);
    expect(parsed.tzOffsetMinutes, 0);
    expect(parsed.songTitle, isNull);
    expect(parsed.songDurationMs, isNull);
  });

  test('caps a single segment at 6h and future clocks at server now', () {
    store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'huge',
        listenedMs: 48 * 60 * 60 * 1000,
        occurredAtMs: DateTime.now()
            .toUtc()
            .add(const Duration(days: 400))
            .millisecondsSinceEpoch,
      ),
    ]);

    final summary = store.getSummary('user-a');
    expect(summary.totalListenedMs, ListeningStatsStore.maxListenedMsPerEvent);
    expect(
      summary.songs.first.lastPlayedMs,
      lessThanOrEqualTo(DateTime.now().toUtc().millisecondsSinceEpoch + 1000),
    );
  });

  test('baseline import may carry large totals and many plays', () {
    final result = store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 200 * 60 * 60 * 1000,
        plays: 4200,
      ),
    ]);

    expect(result.accepted, 1);
    final summary = store.getSummary('user-a');
    expect(summary.totalListenedMs, 200 * 60 * 60 * 1000);
    expect(summary.totalPlays, 4200);
  });

  test('re-imported baseline replaces the old totals instead of stacking', () {
    // Original baseline: 10 plays / 1h for this song on this device.
    store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 3600000,
        plays: 10,
        title: 'Song',
      ),
    ]);
    // Live listening on top of the baseline.
    store.applyEvents('user-a', 'device-1', [
      event(eventId: 'live-1', listenedMs: 60000, plays: 0),
      event(eventId: 'live-2', plays: 1, playId: 'p1'),
    ]);

    // User restores an older backup: the device's history is now 25 plays/2h.
    final result = store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 7200000,
        plays: 25,
      ),
    ]);
    expect(result.accepted, 1);

    final summary = store.getSummary('user-a');
    // New baseline + live events, the old baseline is fully replaced.
    expect(summary.totalListenedMs, 7200000 + 60000);
    expect(summary.totalPlays, 25 + 1);

    // Re-sending the identical baseline is a no-op duplicate.
    final again = store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 7200000,
        plays: 25,
      ),
    ]);
    expect(again.duplicates, 1);
    expect(store.getSummary('user-a').totalPlays, 26);

    // Rollups rebuilt from the raw log agree with the replaced baseline.
    store.rebuildRollups('user-a');
    expect(store.getSummary('user-a').totalListenedMs, 7200000 + 60000);
  });

  test('baseline events can never overwrite another user or device', () {
    store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 1000,
        plays: 1,
      ),
    ]);

    // Another user forging the same eventId is rejected outright.
    final forgedUser = store.applyEvents('user-b', 'device-9', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 999999,
        plays: 999,
      ),
    ]);
    expect(forgedUser.rejected, 1);

    // Same user from a different device also cannot rewrite it.
    final forgedDevice = store.applyEvents('user-a', 'device-2', [
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 999999,
        plays: 999,
      ),
    ]);
    expect(forgedDevice.rejected, 1);

    expect(store.getSummary('user-a').totalPlays, 1);
    expect(store.getSummary('user-b').songs, isEmpty);
  });

  test('daily rollups group by the listener local day and skip baselines', () {
    // 23:30 UTC on Jan 1st, listener at UTC+2 → their Jan 2nd.
    final lateNight = DateTime.utc(2026, 1, 1, 23, 30).millisecondsSinceEpoch;
    final now = DateTime.now().toUtc();
    final today = now.millisecondsSinceEpoch;

    store.applyEvents('user-a', 'device-1', [
      event(
        eventId: 'e1',
        listenedMs: 60000,
        occurredAtMs: lateNight,
        tzOffsetMinutes: 120,
      ),
      event(eventId: 'e2', listenedMs: 30000, occurredAtMs: today),
      event(
        eventId: 'baseline:device-1:song-1',
        listenedMs: 999000,
        plays: 3,
        occurredAtMs: today,
      ),
    ]);

    final daily = store.getDailyListenedMs('user-a', days: 400);
    expect(daily['2026-01-02'], 60000);
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // Baseline import excluded from daily activity: only the real segment.
    expect(daily[todayKey], 30000);
  });

  test('reset wipes one user and leaves others untouched', () {
    store.applyEvents('user-a', 'device-1', [
      event(eventId: 'a1', listenedMs: 1000, plays: 0),
    ]);
    store.applyEvents('user-b', 'device-2', [
      event(eventId: 'b1', listenedMs: 2000),
    ]);

    store.resetUser('user-a');

    expect(store.getSummary('user-a').songs, isEmpty);
    expect(store.getSummary('user-b').totalListenedMs, 2000);

    // After reset the same eventId can be accepted again (fresh history).
    final again = store.applyEvents('user-a', 'device-1', [
      event(eventId: 'a1', listenedMs: 1000),
    ]);
    expect(again.accepted, 1);
  });

  test('rebuildRollups reproduces rollups from the raw event log', () {
    store.applyEvents('user-a', 'device-1', [
      event(eventId: 'e1', listenedMs: 10000, title: 'T', artist: 'A'),
      event(eventId: 'e2', plays: 1, playId: 'p1'),
      event(eventId: 'e3', songId: 'song-2', listenedMs: 5000),
    ]);
    final before = store.getSummary('user-a');

    store.rebuildRollups('user-a');
    final after = store.getSummary('user-a');

    expect(after.totalListenedMs, before.totalListenedMs);
    expect(after.totalPlays, before.totalPlays);
    expect(after.songs.length, before.songs.length);
  });

  group('credited artists', () {
    const mercy = 'Kanye West, Big Sean, Pusha T, 2 Chainz';

    test('every credited artist receives the full play and full time', () {
      store.applyEvents('user-a', 'device-1', [
        event(eventId: 'e1', listenedMs: 60000, title: 'Mercy', artist: mercy),
        event(eventId: 'e2', plays: 1, playId: 'p1', artist: mercy),
      ]);

      final artists = store.getTopArtists('user-a');
      expect(artists, hasLength(4));
      expect(
        artists.map((a) => a.artistDisplay),
        containsAll(['Kanye West', 'Big Sean', 'Pusha T', '2 Chainz']),
      );
      for (final artist in artists) {
        expect(artist.playCount, 1, reason: '${artist.artistDisplay}');
        expect(artist.listenedMs, 60000, reason: '${artist.artistDisplay}');
      }

      // The raw display string on the song rollup is preserved untouched.
      final summary = store.getSummary('user-a');
      expect(summary.songs.single.songArtist, mercy);
    });

    test('protected artist names are never split', () {
      store.applyEvents('user-a', 'device-1', [
        event(
          eventId: 'e1',
          listenedMs: 30000,
          plays: 0,
          artist: 'Tyler, the Creator',
        ),
        event(eventId: 'e2', plays: 1, playId: 'p1',
            artist: 'Tyler, the Creator'),
      ]);

      final artists = store.getTopArtists('user-a');
      expect(artists, hasLength(1));
      expect(artists.single.artistDisplay, 'Tyler, the Creator');
      expect(artists.single.playCount, 1);
      expect(artists.single.listenedMs, 30000);
    });

    test('an event with no artist metadata still ingests cleanly', () {
      // Old clients send exactly this shape today; credited-artist derivation
      // must degrade gracefully, not reject or misfile the event.
      final result = store.applyEvents('user-a', 'device-1', [
        event(eventId: 'e1', listenedMs: 45000),
        event(eventId: 'e2', plays: 1, playId: 'p1'),
      ]);

      expect(result.accepted, 2);
      expect(store.getSummary('user-a').totalListenedMs, 45000);
      expect(store.getTopArtists('user-a'), isEmpty);
      expect(store.getDailyTotals('user-a').values.single.listenedMs, 45000);
    });

    test('windowed top artists only count recent local days', () {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final monthAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'old',
            listenedMs: 60000,
            occurredAtMs: monthAgo,
            artist: 'Old Favourite'),
        event(
            eventId: 'new',
            listenedMs: 30000,
            occurredAtMs: now,
            artist: 'New Obsession'),
      ]);

      final windowed = store.getTopArtists('user-a', days: 7);
      expect(windowed, hasLength(1));
      expect(windowed.single.artistDisplay, 'New Obsession');

      final allTime = store.getTopArtists('user-a');
      expect(allTime, hasLength(2));
    });
  });

  group('album rollups', () {
    test('aggregates plays and time per album', () {
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'e1',
            listenedMs: 60000,
            albumId: 'alb-1',
            album: 'MBDTF',
            albumArtist: 'Kanye West'),
        event(
            eventId: 'e2',
            plays: 1,
            playId: 'p1',
            songId: 'song-2',
            albumId: 'alb-1',
            album: 'MBDTF'),
      ]);

      final albums = store.getTopAlbums('user-a');
      expect(albums, hasLength(1));
      expect(albums.single.albumId, 'alb-1');
      expect(albums.single.album, 'MBDTF');
      expect(albums.single.albumArtist, 'Kanye West');
      expect(albums.single.playCount, 1);
      expect(albums.single.listenedMs, 60000);
    });

    test('falls back to a normalized name key when albumId is missing', () {
      store.applyEvents('user-a', 'device-1', [
        event(eventId: 'e1', listenedMs: 10000, album: 'Untagged  Album'),
        event(
            eventId: 'e2',
            songId: 'song-2',
            listenedMs: 5000,
            album: 'untagged album'),
      ]);

      final albums = store.getTopAlbums('user-a');
      expect(albums, hasLength(1));
      expect(albums.single.albumId, isNull);
      expect(albums.single.listenedMs, 15000);
    });
  });

  group('day and period queries', () {
    test('a specific local day returns totals and top items', () {
      final jan2 = DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch;
      final jan3 = DateTime.utc(2026, 1, 3, 12).millisecondsSinceEpoch;
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'e1',
            listenedMs: 60000,
            occurredAtMs: jan2,
            title: 'Mercy',
            artist: 'Kanye West, Big Sean',
            albumId: 'alb-1',
            album: 'Cruel Summer'),
        event(
            eventId: 'e2',
            plays: 1,
            playId: 'p1',
            occurredAtMs: jan2,
            artist: 'Kanye West, Big Sean',
            albumId: 'alb-1',
            album: 'Cruel Summer'),
        event(
            eventId: 'e3',
            songId: 'song-2',
            listenedMs: 30000,
            occurredAtMs: jan3,
            artist: 'Drake'),
      ]);

      final day = store.getPeriodStats('user-a',
          fromDay: '2026-01-02', toDay: '2026-01-02');
      expect(day.totalListenedMs, 60000);
      expect(day.totalPlays, 1);
      expect(day.songs.single.songId, 'song-1');
      expect(day.songs.single.songTitle, 'Mercy');
      expect(day.artists, hasLength(2));
      expect(day.albums.single.albumId, 'alb-1');
      expect(day.days.keys, ['2026-01-02']);

      // The neighbouring day only sees its own listening.
      final nextDay = store.getPeriodStats('user-a',
          fromDay: '2026-01-03', toDay: '2026-01-03');
      expect(nextDay.totalListenedMs, 30000);
      expect(nextDay.totalPlays, 0);
      expect(nextDay.songs, isEmpty);
      expect(nextDay.artists, isEmpty);
      expect(nextDay.albums, isEmpty);
    });

    test('a period aggregates across days with a per-day breakdown', () {
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'e1',
            listenedMs: 60000,
            occurredAtMs: DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch,
            artist: 'Kanye West'),
        event(
            eventId: 'e2',
            plays: 1,
            playId: 'p1',
            occurredAtMs: DateTime.utc(2026, 1, 20, 12).millisecondsSinceEpoch,
            artist: 'Kanye West'),
        event(
            eventId: 'e3',
            listenedMs: 5000,
            occurredAtMs: DateTime.utc(2026, 2, 1, 12).millisecondsSinceEpoch,
            artist: 'Kanye West'),
      ]);

      // "January 2026" is just a range query over daily rows.
      final january = store.getPeriodStats('user-a',
          fromDay: '2026-01-01', toDay: '2026-01-31');
      expect(january.totalListenedMs, 60000);
      expect(january.totalPlays, 1);
      expect(january.days.keys, ['2026-01-02', '2026-01-20']);
      expect(january.artists.single.playCount, 1);
      expect(january.artists.single.listenedMs, 60000);

      // The February event is outside the range.
      final february = store.getPeriodStats('user-a',
          fromDay: '2026-02-01', toDay: '2026-02-28');
      expect(february.totalListenedMs, 5000);
      expect(february.totalPlays, 0);
      expect(february.songs, isEmpty);
      expect(february.artists, isEmpty);
      expect(february.albums, isEmpty);
    });

    test('partial listens affect totals without creating ranked entries', () {
      final day = DateTime.utc(2026, 2, 2, 12).millisecondsSinceEpoch;
      store.applyEvents('user-a', 'device-1', [
        event(
          eventId: 'partial-time',
          songId: 'partial-song',
          listenedMs: 12000,
          occurredAtMs: day,
          title: 'Skipped Song',
          artist: 'Skipped Artist',
          albumId: 'skipped-album',
          album: 'Skipped Album',
        ),
        event(
          eventId: 'played-time',
          songId: 'played-song',
          listenedMs: 30000,
          occurredAtMs: day,
          title: 'Played Song',
          artist: 'Played Artist',
          albumId: 'played-album',
          album: 'Played Album',
        ),
        event(
          eventId: 'played-marker',
          songId: 'played-song',
          playId: 'played-action',
          plays: 1,
          occurredAtMs: day,
          title: 'Played Song',
          artist: 'Played Artist',
          albumId: 'played-album',
          album: 'Played Album',
        ),
      ]);

      final stats = store.getPeriodStats('user-a',
          fromDay: '2026-02-02', toDay: '2026-02-02');

      expect(stats.totalListenedMs, 42000);
      expect(stats.totalPlays, 1);
      expect(stats.songs.map((song) => song.songId), ['played-song']);
      expect(stats.artists.map((artist) => artist.artistDisplay),
          ['Played Artist']);
      expect(stats.albums.map((album) => album.albumId), ['played-album']);
    });

    test('local day respects tz_offset_min across midnight in both directions',
        () {
      store.applyEvents('user-a', 'device-1', [
        // 23:30 UTC Jan 1st at UTC+2 → the listener's Jan 2nd.
        event(
            eventId: 'east',
            listenedMs: 60000,
            occurredAtMs:
                DateTime.utc(2026, 1, 1, 23, 30).millisecondsSinceEpoch,
            tzOffsetMinutes: 120),
        // 00:30 UTC Jan 2nd at UTC-2 → still the listener's Jan 1st.
        event(
            eventId: 'west',
            listenedMs: 30000,
            occurredAtMs:
                DateTime.utc(2026, 1, 2, 0, 30).millisecondsSinceEpoch,
            tzOffsetMinutes: -120),
      ]);

      final jan1 = store.getPeriodStats('user-a',
          fromDay: '2026-01-01', toDay: '2026-01-01');
      expect(jan1.totalListenedMs, 30000);
      final jan2 = store.getPeriodStats('user-a',
          fromDay: '2026-01-02', toDay: '2026-01-02');
      expect(jan2.totalListenedMs, 60000);
    });

    test('baseline imports are excluded from day/period but kept all-time',
        () {
      final jan2 = DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch;
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'baseline:device-1:song-1',
            listenedMs: 3600000,
            plays: 100,
            occurredAtMs: jan2,
            artist: 'Kanye West'),
        event(
            eventId: 'live',
            listenedMs: 60000,
            occurredAtMs: jan2,
            artist: 'Kanye West'),
      ]);

      // Day/period views only see the live segment.
      final day = store.getPeriodStats('user-a',
          fromDay: '2026-01-02', toDay: '2026-01-02');
      expect(day.totalListenedMs, 60000);
      expect(day.totalPlays, 0);

      // All-time credited-artist rollups include the baseline history.
      final artist = store.getTopArtists('user-a').single;
      expect(artist.playCount, 100);
      expect(artist.listenedMs, 3600000 + 60000);
    });

    test('a replaced baseline is reflected in the derived rollups', () {
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'baseline:device-1:song-1',
            listenedMs: 3600000,
            plays: 10,
            artist: 'Kanye West'),
      ]);
      expect(store.getTopArtists('user-a').single.playCount, 10);

      // Restoring an older backup replaces the device baseline.
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'baseline:device-1:song-1',
            listenedMs: 7200000,
            plays: 25,
            artist: 'Kanye West'),
      ]);

      final artist = store.getTopArtists('user-a').single;
      expect(artist.playCount, 25);
      expect(artist.listenedMs, 7200000);
    });
  });

  group('derivation maintenance', () {
    void seedRichHistory() {
      store.applyEvents('user-a', 'device-1', [
        event(
            eventId: 'e1',
            listenedMs: 60000,
            occurredAtMs: DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch,
            title: 'Mercy',
            artist: 'Kanye West, Big Sean, Pusha T, 2 Chainz',
            albumId: 'alb-1',
            album: 'Cruel Summer'),
        event(
            eventId: 'e2',
            plays: 1,
            playId: 'p1',
            occurredAtMs: DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch,
            artist: 'Kanye West, Big Sean, Pusha T, 2 Chainz'),
        event(
            eventId: 'e3',
            songId: 'song-2',
            listenedMs: 30000,
            occurredAtMs:
                DateTime.utc(2026, 1, 3, 23, 30).millisecondsSinceEpoch,
            tzOffsetMinutes: 120,
            artist: 'Tyler, the Creator',
            album: 'Igor'),
        event(
            eventId: 'baseline:device-1:song-3',
            listenedMs: 1000000,
            plays: 42,
            artist: 'Drake'),
      ]);
    }

    Map<String, Object?> deriveSnapshot() {
      return {
        'artists': store
            .getTopArtists('user-a')
            .map((a) => a.toJson())
            .toList(),
        'albums':
            store.getTopAlbums('user-a').map((a) => a.toJson()).toList(),
        'period': store
            .getPeriodStats('user-a',
                fromDay: '2026-01-01', toDay: '2026-12-31')
            .toJson(),
      };
    }

    test('rebuildRollups reproduces all derived tables deterministically', () {
      seedRichHistory();
      final before = deriveSnapshot();

      store.rebuildRollups('user-a');
      final afterOnce = deriveSnapshot();
      store.rebuildRollups('user-a');
      final afterTwice = deriveSnapshot();

      expect(afterOnce, equals(before));
      expect(afterTwice, equals(before));
    });

    test('reset clears every derived table', () {
      seedRichHistory();
      store.resetUser('user-a');

      expect(store.getTopArtists('user-a'), isEmpty);
      expect(store.getTopAlbums('user-a'), isEmpty);
      expect(store.getDailyTotals('user-a', days: 400), isEmpty);
      final period = store.getPeriodStats('user-a',
          fromDay: '2026-01-01', toDay: '2026-12-31');
      expect(period.totalListenedMs, 0);
      expect(period.songs, isEmpty);
      expect(period.days, isEmpty);

      // Verify at the table level too: no derived rows survive.
      final raw = sqlite3.open('${tempDir.path}/listening_stats.db');
      try {
        for (final table in [
          'song_artist_credits',
          'listening_artist_rollups',
          'listening_album_rollups',
          'listening_daily_rollups',
        ]) {
          final count = raw.select(
            "SELECT COUNT(*) AS n FROM $table WHERE user_id = 'user-a'",
          ).first['n'] as int;
          expect(count, 0, reason: table);
        }
      } finally {
        raw.dispose();
      }
    });

    test('daily totals expose plays alongside listened time', () {
      store.applyEvents('user-a', 'device-1', [
        event(eventId: 'e1', listenedMs: 60000),
        event(eventId: 'e2', plays: 1, playId: 'p1'),
      ]);

      final totals = store.getDailyTotals('user-a');
      expect(totals.values.single.listenedMs, 60000);
      expect(totals.values.single.playCount, 1);
    });
  });

  group('playback source context', () {
    List<Map<String, Object?>> selectEvents(String dbPath) {
      final reader = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      try {
        return reader
            .select('SELECT event_id, source_kind, playlist_id, client_kind '
                'FROM listening_events ORDER BY event_id')
            .map((row) => <String, Object?>{
                  'event_id': row['event_id'],
                  'source_kind': row['source_kind'],
                  'playlist_id': row['playlist_id'],
                  'client_kind': row['client_kind'],
                })
            .toList();
      } finally {
        reader.dispose();
      }
    }

    test('stores optional context fields on accepted events', () {
      final result = store.applyEvents('user-a', 'device-1', [
        ListeningEvent(
          eventId: 'ctx-1',
          songId: 'song-1',
          listenedMs: 30000,
          plays: 0,
          occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          tzOffsetMinutes: 0,
          sourceKind: 'playlist',
          playlistId: 'pl-1',
          clientKind: 'desktop',
        ),
      ]);
      expect(result.accepted, 1);

      final rows = selectEvents('${tempDir.path}/listening_stats.db');
      expect(rows.single['source_kind'], 'playlist');
      expect(rows.single['playlist_id'], 'pl-1');
      expect(rows.single['client_kind'], 'desktop');
    });

    test('old-client events without context still ingest with NULL context',
        () {
      final result = store.applyEvents('user-a', 'device-1', [
        event(eventId: 'old-1', listenedMs: 30000),
        event(eventId: 'old-2', plays: 1, playId: 'p1'),
      ]);
      expect(result.accepted, 2);
      expect(result.rejected, 0);

      final rows = selectEvents('${tempDir.path}/listening_stats.db');
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row['source_kind'], isNull);
        expect(row['playlist_id'], isNull);
        expect(row['client_kind'], isNull);
      }

      // And the context-free events roll up exactly as before.
      final summary = store.getSummary('user-a');
      expect(summary.totalListenedMs, 30000);
      expect(summary.totalPlays, 1);
    });

    test('context strings are trimmed, bounded, and blank becomes NULL', () {
      store.applyEvents('user-a', 'device-1', [
        ListeningEvent(
          eventId: 'ctx-sane',
          songId: 'song-1',
          listenedMs: 1000,
          plays: 0,
          occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          tzOffsetMinutes: 0,
          sourceKind: '   ',
          playlistId: 'p' * 5000,
          clientKind: '  tv  ',
        ),
      ]);

      final rows = selectEvents('${tempDir.path}/listening_stats.db');
      expect(rows.single['source_kind'], isNull);
      expect((rows.single['playlist_id'] as String).length, 256);
      expect(rows.single['client_kind'], 'tv');
    });

    test('a pre-context database gains the columns without losing data', () {
      final path = '${tempDir.path}/pre_context.db';

      // A database created by today's code, minus the context columns.
      final raw = sqlite3.open(path);
      raw.execute('''
        CREATE TABLE listening_events (
          event_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          song_id TEXT NOT NULL,
          play_id TEXT,
          listened_ms INTEGER NOT NULL DEFAULT 0,
          plays INTEGER NOT NULL DEFAULT 0,
          occurred_at INTEGER NOT NULL,
          tz_offset_min INTEGER NOT NULL DEFAULT 0,
          received_at INTEGER NOT NULL,
          song_title TEXT,
          song_artist TEXT,
          album_id TEXT,
          album TEXT,
          album_artist TEXT
        )
      ''');
      raw.execute('''
        CREATE TABLE listening_song_rollups (
          user_id TEXT NOT NULL,
          song_id TEXT NOT NULL,
          play_count INTEGER NOT NULL DEFAULT 0,
          listened_ms INTEGER NOT NULL DEFAULT 0,
          first_played INTEGER,
          last_played INTEGER,
          song_title TEXT,
          song_artist TEXT,
          album_id TEXT,
          album TEXT,
          album_artist TEXT,
          PRIMARY KEY (user_id, song_id)
        )
      ''');
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      raw.execute('''
        INSERT INTO listening_events (
          event_id, user_id, device_id, song_id, play_id, listened_ms, plays,
          occurred_at, tz_offset_min, received_at
        ) VALUES ('legacy-1', 'user-a', 'device-1', 'song-1', 'p1', 0, 1,
                  $now, 0, $now)
      ''');
      raw.execute('''
        INSERT INTO listening_song_rollups (
          user_id, song_id, play_count, listened_ms, first_played, last_played
        ) VALUES ('user-a', 'song-1', 1, 0, $now, $now)
      ''');
      raw.dispose();

      final upgraded = ListeningStatsStore(databasePath: path);
      upgraded.initialize();
      addTearDown(upgraded.close);

      // The legacy row survives with NULL context.
      final rows = selectEvents(path);
      expect(rows.single['event_id'], 'legacy-1');
      expect(rows.single['source_kind'], isNull);

      // New context-carrying events land in the migrated table.
      final result = upgraded.applyEvents('user-a', 'device-1', [
        ListeningEvent(
          eventId: 'ctx-after-migration',
          songId: 'song-1',
          listenedMs: 5000,
          plays: 0,
          occurredAtMs: now,
          tzOffsetMinutes: 0,
          sourceKind: 'album',
          clientKind: 'mobile',
        ),
      ]);
      expect(result.accepted, 1);
      expect(upgraded.getSummary('user-a').totalPlays, 1);

      // Re-opening is idempotent — the ALTERs are guarded.
      upgraded.close();
      final reopened = ListeningStatsStore(databasePath: path);
      reopened.initialize();
      addTearDown(reopened.close);
      expect(selectEvents(path), hasLength(2));
    });
  });

  group('migration from the pre-derivation schema', () {
    test('opening an old database with data backfills all derived tables',
        () {
      final path = '${tempDir.path}/old_listening_stats.db';

      // Hand-build a v1-era database: raw events + song rollups only, no
      // derived tables and no meta/version marker.
      final raw = sqlite3.open(path);
      raw.execute('''
        CREATE TABLE listening_events (
          event_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          song_id TEXT NOT NULL,
          play_id TEXT,
          listened_ms INTEGER NOT NULL DEFAULT 0,
          plays INTEGER NOT NULL DEFAULT 0,
          occurred_at INTEGER NOT NULL,
          tz_offset_min INTEGER NOT NULL DEFAULT 0,
          received_at INTEGER NOT NULL,
          song_title TEXT,
          song_artist TEXT,
          album_id TEXT,
          album TEXT,
          album_artist TEXT
        )
      ''');
      raw.execute('''
        CREATE TABLE listening_song_rollups (
          user_id TEXT NOT NULL,
          song_id TEXT NOT NULL,
          play_count INTEGER NOT NULL DEFAULT 0,
          listened_ms INTEGER NOT NULL DEFAULT 0,
          first_played INTEGER,
          last_played INTEGER,
          song_title TEXT,
          song_artist TEXT,
          album_id TEXT,
          album TEXT,
          album_artist TEXT,
          PRIMARY KEY (user_id, song_id)
        )
      ''');
      final jan2 = DateTime.utc(2026, 1, 2, 12).millisecondsSinceEpoch;
      raw.execute('''
        INSERT INTO listening_events (
          event_id, user_id, device_id, song_id, play_id, listened_ms, plays,
          occurred_at, tz_offset_min, received_at,
          song_title, song_artist, album_id, album, album_artist
        ) VALUES
          ('e1', 'user-a', 'device-1', 'song-1', NULL, 60000, 0, $jan2, 0,
           $jan2, 'Mercy', 'Kanye West, Big Sean, Pusha T, 2 Chainz',
           'alb-1', 'Cruel Summer', 'Kanye West'),
          ('e2', 'user-a', 'device-1', 'song-1', 'p1', 0, 1, $jan2, 0,
           $jan2, 'Mercy', 'Kanye West, Big Sean, Pusha T, 2 Chainz',
           'alb-1', 'Cruel Summer', 'Kanye West'),
          ('baseline:device-1:song-2', 'user-a', 'device-1', 'song-2', NULL,
           500000, 12, $jan2, 0, $jan2, NULL, 'Drake', NULL, NULL, NULL)
      ''');
      raw.execute('''
        INSERT INTO listening_song_rollups (
          user_id, song_id, play_count, listened_ms, first_played,
          last_played, song_title, song_artist, album_id, album, album_artist
        ) VALUES
          ('user-a', 'song-1', 1, 60000, $jan2, $jan2, 'Mercy',
           'Kanye West, Big Sean, Pusha T, 2 Chainz', 'alb-1',
           'Cruel Summer', 'Kanye West'),
          ('user-a', 'song-2', 12, 500000, $jan2, $jan2, NULL, 'Drake',
           NULL, NULL, NULL)
      ''');
      raw.dispose();

      final upgraded = ListeningStatsStore(databasePath: path);
      upgraded.initialize();
      addTearDown(upgraded.close);

      // Existing data is intact.
      final summary = upgraded.getSummary('user-a');
      expect(summary.totalPlays, 13);
      expect(summary.totalListenedMs, 560000);

      // Derived tables were backfilled from the raw log.
      final artists = upgraded.getTopArtists('user-a');
      expect(
        artists.map((a) => a.artistDisplay),
        containsAll(
            ['Kanye West', 'Big Sean', 'Pusha T', '2 Chainz', 'Drake']),
      );
      expect(upgraded.getTopAlbums('user-a').single.albumId, 'alb-1');
      final day = upgraded.getPeriodStats('user-a',
          fromDay: '2026-01-02', toDay: '2026-01-02');
      expect(day.totalListenedMs, 60000); // baseline excluded
      expect(day.totalPlays, 1);

      // Re-opening does not re-run the backfill (version marker persists)
      // and converges to the same state.
      upgraded.close();
      final reopened = ListeningStatsStore(databasePath: path);
      reopened.initialize();
      addTearDown(reopened.close);
      expect(reopened.getTopArtists('user-a'), hasLength(5));
      expect(reopened.getSummary('user-a').totalPlays, 13);
    });
  });
}
