import 'package:ariami_core/ariami_core.dart'
    show
        ListeningDailyTotal,
        ListeningEvent,
        ListeningPeriodStats,
        ListeningSongRollup;
import 'package:ariami_mobile/services/stats/period_stats_overlay_apply.dart';
import 'package:flutter_test/flutter_test.dart';

ListeningEvent _event({
  required String eventId,
  required String songId,
  required int occurredAtMs,
  int plays = 1,
  int listenedMs = 0,
  String? songTitle,
  String? songArtist,
}) {
  return ListeningEvent(
    eventId: eventId,
    songId: songId,
    listenedMs: listenedMs,
    plays: plays,
    occurredAtMs: occurredAtMs,
    tzOffsetMinutes: 0,
    songTitle: songTitle,
    songArtist: songArtist,
  );
}

int _utcMs(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

void main() {
  const from = '2026-07-10';
  const to = '2026-07-10';

  group('excludeAckedPendingEventIds', () {
    test('intersects acked ids with still-pending only', () {
      final pending = [
        _event(
          eventId: 'e-upload',
          songId: 's1',
          occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        ),
        _event(
          eventId: 'e-offline',
          songId: 's2',
          occurredAtMs: _utcMs('2026-07-10T13:00:00Z'),
        ),
      ];
      expect(
        excludeAckedPendingEventIds(
          ackedInFlightEventIds: {'e-upload', 'e-gone'},
          pending: pending,
        ),
        {'e-upload'},
      );
      expect(
        excludeAckedPendingEventIds(
          ackedInFlightEventIds: const {},
          pending: pending,
        ),
        isEmpty,
      );
    });
  });

  group('buildDisplayedPeriodStats production path', () {
    test('reconnect race: acked-in-flight excludes without undercounting offline',
        () {
      final uploaded = _event(
        eventId: 'e-upload',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        plays: 1,
        listenedMs: 40000,
        songTitle: 'Track',
        songArtist: 'A',
      );
      final offlineOnly = _event(
        eventId: 'e-offline',
        songId: 's2',
        occurredAtMs: _utcMs('2026-07-10T14:00:00Z'),
        plays: 1,
        listenedMs: 10000,
        songTitle: 'Offline',
        songArtist: 'B',
      );

      // (a) offline: nothing acked → pending shows
      var stats = buildDisplayedPeriodStats(
        base: null,
        pending: [uploaded],
        fromDay: from,
        toDay: to,
        ackedInFlightEventIds: const {},
      );
      expect(stats.totalPlays, 1);
      expect(stats.totalListenedMs, 40000);

      final freshBase = ListeningPeriodStats(
        fromDay: from,
        toDay: to,
        totalPlays: 1,
        totalListenedMs: 40000,
        songs: const [
          ListeningSongRollup(
            songId: 's1',
            playCount: 1,
            listenedMs: 40000,
            songTitle: 'Track',
            songArtist: 'A',
          ),
        ],
        artists: const [],
        albums: const [],
        days: const {
          '2026-07-10': ListeningDailyTotal(playCount: 1, listenedMs: 40000),
        },
      );

      // (b) race: fresh base has event, still in pending, but acked → not 2x
      stats = buildDisplayedPeriodStats(
        base: freshBase,
        pending: [uploaded],
        fromDay: from,
        toDay: to,
        ackedInFlightEventIds: {'e-upload'},
      );
      expect(stats.totalPlays, 1);
      expect(stats.totalListenedMs, 40000);

      // (c) never-uploaded offline event still overlays on top of base
      stats = buildDisplayedPeriodStats(
        base: freshBase,
        pending: [uploaded, offlineOnly],
        fromDay: from,
        toDay: to,
        ackedInFlightEventIds: {'e-upload'},
      );
      expect(stats.totalPlays, 2);
      expect(stats.totalListenedMs, 50000);
      expect(stats.songs.map((s) => s.songId), containsAll(['s1', 's2']));
    });
  });
}
