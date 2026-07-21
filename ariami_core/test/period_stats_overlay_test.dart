import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/period_stats_overlay.dart';
import 'package:ariami_core/services/stats/stats_local_day.dart';
import 'package:test/test.dart';

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
  String? albumArtist,
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
    albumArtist: albumArtist,
  );
}

/// UTC ms for `yyyy-mm-ddTHH:mm:ssZ`.
int _utcMs(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

void main() {
  group('statsLocalDay', () {
    test('formats UTC day at zero offset', () {
      expect(statsLocalDay(_utcMs('2026-03-15T12:00:00Z'), 0), '2026-03-15');
    });

    test('applies positive tz offset across midnight', () {
      // 23:30 UTC + 60 min => local 00:30 next day
      expect(
        statsLocalDay(_utcMs('2026-03-15T23:30:00Z'), 60),
        '2026-03-16',
      );
    });

    test('applies negative tz offset across midnight', () {
      // 00:30 UTC - 60 min => local 23:30 previous day
      expect(
        statsLocalDay(_utcMs('2026-03-15T00:30:00Z'), -60),
        '2026-03-14',
      );
    });
  });

  group('statsAlbumKey', () {
    test('prefers albumId', () {
      expect(statsAlbumKey('alb-1', 'Whatever'), 'alb-1');
    });

    test('falls back to normalized name key', () {
      expect(statsAlbumKey(null, '  My Album  '), 'name:my album');
    });

    test('returns null when neither is usable', () {
      expect(statsAlbumKey(null, null), isNull);
      expect(statsAlbumKey('', '   '), isNull);
    });
  });

  group('overlayPeriodStatsWithPending', () {
    test('filters pending by fromDay/toDay (today/week/month ranges)', () {
      final pending = [
        _event(
          eventId: 'in-range',
          songId: 's1',
          occurredAtMs: _utcMs('2026-07-10T15:00:00Z'),
          plays: 1,
          listenedMs: 1000,
          songTitle: 'In',
        ),
        _event(
          eventId: 'before',
          songId: 's2',
          occurredAtMs: _utcMs('2026-07-01T15:00:00Z'),
          plays: 1,
          listenedMs: 2000,
          songTitle: 'Before',
        ),
        _event(
          eventId: 'after',
          songId: 's3',
          occurredAtMs: _utcMs('2026-07-20T15:00:00Z'),
          plays: 1,
          listenedMs: 3000,
          songTitle: 'After',
        ),
      ];

      final week = overlayPeriodStatsWithPending(
        pending: pending,
        fromDay: '2026-07-07',
        toDay: '2026-07-13',
      );
      expect(week.totalPlays, 1);
      expect(week.totalListenedMs, 1000);
      expect(week.songs.map((s) => s.songId), ['s1']);
      expect(week.days.keys, ['2026-07-10']);

      final month = overlayPeriodStatsWithPending(
        pending: pending,
        fromDay: '2026-07-01',
        toDay: '2026-07-31',
      );
      expect(month.totalPlays, 3);
      expect(month.songs.length, 3);

      final today = overlayPeriodStatsWithPending(
        pending: pending,
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(today.totalPlays, 1);
      expect(today.songs.single.songId, 's1');
    });

    test('midnight timezone boundary buckets to local day', () {
      // Near UTC midnight with +120 offset lands on next local day.
      final event = _event(
        eventId: 'tz',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T23:00:00Z'),
        tzOffsetMinutes: 120, // local 2026-07-11 01:00
        plays: 1,
        listenedMs: 5000,
      );

      final wrongDay = overlayPeriodStatsWithPending(
        pending: [event],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(wrongDay.totalPlays, 0);
      expect(wrongDay.songs, isEmpty);

      final rightDay = overlayPeriodStatsWithPending(
        pending: [event],
        fromDay: '2026-07-11',
        toDay: '2026-07-11',
      );
      expect(rightDay.totalPlays, 1);
      expect(rightDay.totalListenedMs, 5000);
      expect(rightDay.days['2026-07-11']?.playCount, 1);
    });

    test('zero-play time feeds totals/days but not ranked rows', () {
      final timeOnly = _event(
        eventId: 't1',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        plays: 0,
        listenedMs: 45000,
        songTitle: 'Partial',
        songArtist: 'Solo',
        albumId: 'a1',
        album: 'LP',
      );

      final stats = overlayPeriodStatsWithPending(
        pending: [timeOnly],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(stats.totalPlays, 0);
      expect(stats.totalListenedMs, 45000);
      expect(stats.days['2026-07-10']?.listenedMs, 45000);
      expect(stats.days['2026-07-10']?.playCount, 0);
      expect(stats.songs, isEmpty);
      expect(stats.artists, isEmpty);
      expect(stats.albums, isEmpty);

      // Once a play exists, time is included on the ranked row.
      final withPlay = overlayPeriodStatsWithPending(
        pending: [
          timeOnly,
          _event(
            eventId: 'p1',
            songId: 's1',
            occurredAtMs: _utcMs('2026-07-10T12:30:00Z'),
            plays: 1,
            listenedMs: 0,
            songTitle: 'Partial',
            songArtist: 'Solo',
            albumId: 'a1',
            album: 'LP',
          ),
        ],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(withPlay.totalPlays, 1);
      expect(withPlay.totalListenedMs, 45000);
      expect(withPlay.songs.single.playCount, 1);
      expect(withPlay.songs.single.listenedMs, 45000);
      expect(withPlay.artists.single.listenedMs, 45000);
      expect(withPlay.albums.single.listenedMs, 45000);
    });

    test('multi-artist track stays one combined-string artist offline', () {
      final event = _event(
        eventId: 'm1',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        plays: 1,
        listenedMs: 10000,
        songArtist: 'Kanye West, Big Sean, Pusha T',
      );

      final stats = overlayPeriodStatsWithPending(
        pending: [event],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(stats.artists, hasLength(1));
      expect(
        stats.artists.single.artistDisplay,
        'Kanye West, Big Sean, Pusha T',
      );
      expect(
        stats.artists.single.artistKey,
        'kanye west, big sean, pusha t',
      );
      expect(stats.artists.single.playCount, 1);
    });

    test('base + pending merge adds correctly without mutating base', () {
      final base = ListeningPeriodStats(
        fromDay: '2026-07-01',
        toDay: '2026-07-31',
        totalPlays: 2,
        totalListenedMs: 20000,
        songs: const [
          ListeningSongRollup(
            songId: 's1',
            playCount: 2,
            listenedMs: 20000,
            songTitle: 'Old',
            songArtist: 'A',
          ),
        ],
        artists: const [
          ListeningArtistRollup(
            artistKey: 'a',
            artistDisplay: 'A',
            playCount: 2,
            listenedMs: 20000,
          ),
        ],
        albums: const [
          ListeningAlbumRollup(
            albumKey: 'alb-1',
            albumId: 'alb-1',
            album: 'LP',
            playCount: 2,
            listenedMs: 20000,
          ),
        ],
        days: const {
          '2026-07-05': ListeningDailyTotal(playCount: 2, listenedMs: 20000),
        },
      );
      final basePlays = base.totalPlays;

      final merged = overlayPeriodStatsWithPending(
        base: base,
        pending: [
          _event(
            eventId: 'p-new',
            songId: 's1',
            occurredAtMs: _utcMs('2026-07-12T10:00:00Z'),
            plays: 1,
            listenedMs: 5000,
            songTitle: 'Old',
            songArtist: 'A',
            albumId: 'alb-1',
            album: 'LP',
          ),
          _event(
            eventId: 'p-other',
            songId: 's2',
            occurredAtMs: _utcMs('2026-07-12T11:00:00Z'),
            plays: 1,
            listenedMs: 8000,
            songTitle: 'New',
            songArtist: 'B',
            albumId: 'alb-2',
            album: 'EP',
          ),
        ],
        fromDay: '2026-07-01',
        toDay: '2026-07-31',
      );

      expect(base.totalPlays, basePlays); // base not mutated
      expect(merged.totalPlays, 4);
      expect(merged.totalListenedMs, 33000);
      expect(merged.songs.length, 2);
      final s1 = merged.songs.firstWhere((s) => s.songId == 's1');
      expect(s1.playCount, 3);
      expect(s1.listenedMs, 25000);
      expect(merged.days['2026-07-05']?.playCount, 2);
      expect(merged.days['2026-07-12']?.playCount, 2);
      expect(merged.days['2026-07-12']?.listenedMs, 13000);
    });

    test('excludeEventIds and duplicate pending ids prevent double-count', () {
      final event = _event(
        eventId: 'dup',
        songId: 's1',
        occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
        plays: 1,
        listenedMs: 1000,
      );

      final excluded = overlayPeriodStatsWithPending(
        pending: [event],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
        excludeEventIds: {'dup'},
      );
      expect(excluded.totalPlays, 0);

      final deduped = overlayPeriodStatsWithPending(
        pending: [event, event],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(deduped.totalPlays, 1);
      expect(deduped.totalListenedMs, 1000);
    });

    test('empty base + pending only works', () {
      final stats = overlayPeriodStatsWithPending(
        base: null,
        pending: [
          _event(
            eventId: 'e1',
            songId: 's1',
            occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
            plays: 1,
            listenedMs: 12000,
            songTitle: 'Solo',
            songArtist: 'Artist',
            albumId: 'a1',
            album: 'Album',
            albumArtist: 'Artist',
          ),
        ],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(stats.fromDay, '2026-07-10');
      expect(stats.toDay, '2026-07-10');
      expect(stats.totalPlays, 1);
      expect(stats.totalListenedMs, 12000);
      expect(stats.songs.single.songTitle, 'Solo');
      expect(stats.artists.single.artistDisplay, 'Artist');
      expect(stats.albums.single.album, 'Album');
      expect(stats.days['2026-07-10']?.playCount, 1);
    });

    test('baseline: events are skipped', () {
      final stats = overlayPeriodStatsWithPending(
        pending: [
          _event(
            eventId: 'baseline:device:s1',
            songId: 's1',
            occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
            plays: 50,
            listenedMs: 999999,
          ),
          _event(
            eventId: 'real',
            songId: 's2',
            occurredAtMs: _utcMs('2026-07-10T13:00:00Z'),
            plays: 1,
            listenedMs: 1000,
          ),
        ],
        fromDay: '2026-07-01',
        toDay: '2026-07-31',
      );
      expect(stats.totalPlays, 1);
      expect(stats.totalListenedMs, 1000);
      expect(stats.songs.map((s) => s.songId), ['s2']);
    });

    test('ranked lists sort by playCount desc then listenedMs desc', () {
      final stats = overlayPeriodStatsWithPending(
        pending: [
          _event(
            eventId: 'a',
            songId: 'low-plays',
            occurredAtMs: _utcMs('2026-07-10T12:00:00Z'),
            plays: 1,
            listenedMs: 90000,
          ),
          _event(
            eventId: 'b',
            songId: 'high-plays',
            occurredAtMs: _utcMs('2026-07-10T12:01:00Z'),
            plays: 3,
            listenedMs: 1000,
          ),
          _event(
            eventId: 'c',
            songId: 'tie-more-ms',
            occurredAtMs: _utcMs('2026-07-10T12:02:00Z'),
            plays: 2,
            listenedMs: 5000,
          ),
          _event(
            eventId: 'd',
            songId: 'tie-less-ms',
            occurredAtMs: _utcMs('2026-07-10T12:03:00Z'),
            plays: 2,
            listenedMs: 1000,
          ),
        ],
        fromDay: '2026-07-10',
        toDay: '2026-07-10',
      );
      expect(
        stats.songs.map((s) => s.songId).toList(),
        ['high-plays', 'tie-more-ms', 'tie-less-ms', 'low-plays'],
      );
    });
  });
}
