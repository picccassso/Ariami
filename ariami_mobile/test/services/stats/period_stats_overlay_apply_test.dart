import 'package:ariami_core/ariami_core.dart'
    show
        ListeningDailyTotal,
        ListeningEvent,
        ListeningPeriodStats,
        ListeningSongRollup,
        StatsRange;
import 'package:ariami_mobile/services/stats/period_stats_overlay_apply.dart';
import 'package:flutter_test/flutter_test.dart';

ListeningEvent _event({
  required String eventId,
  required String songId,
  required int occurredAtMs,
  int tzOffsetMinutes = 0,
  int plays = 1,
  int listenedMs = 0,
  String? songTitle,
  String? songArtist,
  String? albumId,
  String? album,
}) {
  return ListeningEvent(
    eventId: eventId,
    songId: songId,
    listenedMs: listenedMs,
    plays: plays,
    occurredAtMs: occurredAtMs,
    tzOffsetMinutes: tzOffsetMinutes,
    songTitle: songTitle,
    songArtist: songArtist,
    albumId: albumId,
    album: album,
  );
}

int _utcMs(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

void main() {
  final now = DateTime(2026, 7, 10, 15, 0);

  group('applyPeriodStatsOverlay', () {
    test('merges cached base with pending for today/week/month', () {
      final base = ListeningPeriodStats(
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
        totalPlays: 1,
        totalListenedMs: 10000,
        songs: const [
          ListeningSongRollup(
            songId: 's1',
            playCount: 1,
            listenedMs: 10000,
            songTitle: 'Cached',
          ),
        ],
        artists: const [],
        albums: const [],
        days: const {
          '2026-07-10': ListeningDailyTotal(playCount: 1, listenedMs: 10000),
        },
      );
      final pending = [
        _event(
          eventId: 'offline-1',
          songId: 's2',
          occurredAtMs: _utcMs('2026-07-10T18:00:00Z'),
          plays: 1,
          listenedMs: 5000,
          songTitle: 'Offline Play',
          songArtist: 'Artist A',
        ),
      ];

      final todayBounds = StatsRange.specificDay(now).bounds(now: now)!;
      final today = applyPeriodStatsOverlay(
        base: base,
        pending: pending,
        fromDay: todayBounds.from,
        toDay: todayBounds.to,
      );
      expect(today.totalPlays, 2);
      expect(today.songs.map((s) => s.songId), containsAll(['s1', 's2']));

      final weekBounds = StatsRange.weekOf(now).bounds(now: now)!;
      final week = applyPeriodStatsOverlay(
        base: null,
        pending: pending,
        fromDay: weekBounds.from,
        toDay: weekBounds.to,
      );
      expect(week.totalPlays, 1);

      final monthBounds = StatsRange.monthOf(now).bounds(now: now)!;
      final month = applyPeriodStatsOverlay(
        base: null,
        pending: pending,
        fromDay: monthBounds.from,
        toDay: monthBounds.to,
      );
      expect(month.totalPlays, 1);
    });

    test('live recompute when a play is added while viewing', () {
      const from = '2026-07-10';
      const to = '2026-07-10';
      final base = ListeningPeriodStats(
        fromDay: from,
        toDay: to,
        totalPlays: 0,
        totalListenedMs: 0,
        songs: const [],
        artists: const [],
        albums: const [],
        days: const {},
      );

      var pending = <ListeningEvent>[];
      var displayed = applyPeriodStatsOverlay(
        base: base,
        pending: pending,
        fromDay: from,
        toDay: to,
      );
      expect(displayed.totalPlays, 0);
      expect(periodStatsHasContent(displayed), isFalse);

      // Simulate outbox gaining an event while the screen is open.
      pending = [
        _event(
          eventId: 'live-1',
          songId: 's1',
          occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
          plays: 1,
          listenedMs: 30000,
          songTitle: 'Live',
          songArtist: 'Solo',
        ),
      ];
      displayed = applyPeriodStatsOverlay(
        base: base,
        pending: pending,
        fromDay: from,
        toDay: to,
      );
      expect(displayed.totalPlays, 1);
      expect(displayed.songs.single.songTitle, 'Live');
      expect(periodStatsHasContent(displayed), isTrue);
    });

    test('no double-count after simulated reconnect+refetch', () {
      const from = '2026-07-10';
      const to = '2026-07-10';
      final offlineEvent = _event(
        eventId: 'e-upload',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        plays: 1,
        listenedMs: 40000,
        songTitle: 'Track',
        songArtist: 'A',
        albumId: 'alb',
        album: 'LP',
      );

      // Offline: empty base + pending outbox (nothing acked yet).
      final offline = buildDisplayedPeriodStats(
        base: null,
        pending: [offlineEvent],
        fromDay: from,
        toDay: to,
        ackedInFlightEventIds: const {},
      );
      expect(offline.totalPlays, 1);

      // After upload: outbox drained; fresh server base includes the event.
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
      final afterSync = buildDisplayedPeriodStats(
        base: freshBase,
        pending: const [], // drained
        fromDay: from,
        toDay: to,
        ackedInFlightEventIds: const {},
      );
      expect(afterSync.totalPlays, 1);
      expect(afterSync.totalListenedMs, 40000);
    });

    test('account separation: different pending sets do not leak', () {
      const from = '2026-07-10';
      const to = '2026-07-10';
      final userAPending = [
        _event(
          eventId: 'a1',
          songId: 'song-a',
          occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
          plays: 1,
          listenedMs: 1000,
          songTitle: 'User A Song',
        ),
      ];
      final userBPending = [
        _event(
          eventId: 'b1',
          songId: 'song-b',
          occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
          plays: 1,
          listenedMs: 2000,
          songTitle: 'User B Song',
        ),
      ];

      final forA = applyPeriodStatsOverlay(
        base: null,
        pending: userAPending,
        fromDay: from,
        toDay: to,
      );
      final forB = applyPeriodStatsOverlay(
        base: null,
        pending: userBPending,
        fromDay: from,
        toDay: to,
      );
      final afterClear = applyPeriodStatsOverlay(
        base: null,
        pending: const [],
        fromDay: from,
        toDay: to,
      );

      expect(forA.songs.single.songId, 'song-a');
      expect(forB.songs.single.songId, 'song-b');
      expect(afterClear.totalPlays, 0);
      expect(afterClear.songs, isEmpty);
    });

    test('multi-artist offline stays combined-string', () {
      final stats = applyPeriodStatsOverlay(
        base: null,
        pending: [
          _event(
            eventId: 'm1',
            songId: 'mercy',
            occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
            plays: 1,
            listenedMs: 330000,
            songArtist: 'Kanye West, Big Sean, Pusha T, 2 Chainz',
          ),
        ],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(stats.artists, hasLength(1));
      expect(
        stats.artists.single.artistDisplay,
        'Kanye West, Big Sean, Pusha T, 2 Chainz',
      );
    });

    test('zero-play time-only does not create ranked rows', () {
      final stats = applyPeriodStatsOverlay(
        base: null,
        pending: [
          _event(
            eventId: 't1',
            songId: 's1',
            occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
            plays: 0,
            listenedMs: 20000,
            songTitle: 'Partial',
            songArtist: 'X',
          ),
        ],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(stats.totalListenedMs, 20000);
      expect(stats.totalPlays, 0);
      expect(stats.songs, isEmpty);
      expect(periodStatsHasContent(stats), isTrue);
    });
  });

  group('periodStatsHasContent', () {
    test('false for null and empty', () {
      expect(periodStatsHasContent(null), isFalse);
      expect(
        periodStatsHasContent(
          const ListeningPeriodStats(
            fromDay: '2026-07-10',
            toDay: '2026-07-10',
            totalPlays: 0,
            totalListenedMs: 0,
            songs: [],
            artists: [],
            albums: [],
            days: {},
          ),
        ),
        isFalse,
      );
    });
  });
}
