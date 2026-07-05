import 'dart:io';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_stats_store.dart';
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
}
