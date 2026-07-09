import 'package:ariami_core/ariami_core.dart' show ListeningArtistRollup;
import 'package:ariami_mobile/services/stats/period_stats_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A realistic period payload from a Pass-1 server: one multi-artist play of
/// "Mercy" whose combined string is split into credited artists server-side.
Map<String, dynamic> _mercyPeriodResponse() => <String, dynamic>{
      'from': '2026-07-01',
      'to': '2026-07-09',
      'totalPlays': 1,
      'totalListenedMs': 330000,
      'songs': [
        {
          'songId': 'song-mercy',
          'playCount': 1,
          'listenedMs': 330000,
          'songTitle': 'Mercy',
          'songArtist': 'Kanye West, Big Sean, Pusha T, 2 Chainz',
          'albumId': 'album-cruel-summer',
          'album': 'Cruel Summer',
          'albumArtist': 'Kanye West',
        },
      ],
      'artists': [
        {'artistKey': 'kanye west', 'artistDisplay': 'Kanye West', 'playCount': 1, 'listenedMs': 330000},
        {'artistKey': 'big sean', 'artistDisplay': 'Big Sean', 'playCount': 1, 'listenedMs': 330000},
        {'artistKey': 'pusha t', 'artistDisplay': 'Pusha T', 'playCount': 1, 'listenedMs': 330000},
        {'artistKey': '2 chainz', 'artistDisplay': '2 Chainz', 'playCount': 1, 'listenedMs': 330000},
      ],
      'albums': [
        {
          'albumKey': 'album-cruel-summer',
          'albumId': 'album-cruel-summer',
          'album': 'Cruel Summer',
          'albumArtist': 'Kanye West',
          'playCount': 1,
          'listenedMs': 330000,
        },
      ],
      'days': {
        '2026-07-09': {'playCount': 1, 'listenedMs': 330000},
      },
      'generatedAtMs': 1751970000000,
    };

void main() {
  final now = DateTime(2026, 7, 9, 15, 30);

  group('StatsRange bounds', () {
    test('today and specific day are single-day ranges', () {
      expect(StatsRange.today.bounds(now: now),
          (from: '2026-07-09', to: '2026-07-09'));
      expect(StatsRange.specificDay(DateTime(2026, 6, 12)).bounds(now: now),
          (from: '2026-06-12', to: '2026-06-12'));
      expect(StatsRange.today.isSingleDay, isTrue);
      expect(StatsRange.specificDay(DateTime(2026, 6, 12)).isSingleDay, isTrue);
    });

    test('week is the calendar Monday–Sunday week', () {
      // 2026-07-09 is a Thursday; its week runs Mon 6th – Sun 12th.
      expect(StatsRange.week.bounds(now: now),
          (from: '2026-07-06', to: '2026-07-12'));
      expect(StatsRange.weekOf(DateTime(2026, 7, 12)).bounds(now: now),
          (from: '2026-07-06', to: '2026-07-12'));
    });

    test('month and year are whole calendar units', () {
      expect(StatsRange.month.bounds(now: now),
          (from: '2026-07-01', to: '2026-07-31'));
      expect(StatsRange.year.bounds(now: now),
          (from: '2026-01-01', to: '2026-12-31'));
      expect(StatsRange.monthOf(DateTime(2026, 2, 15)).bounds(now: now),
          (from: '2026-02-01', to: '2026-02-28'));
    });

    test('all-time has no bounds', () {
      expect(StatsRange.all.bounds(now: now), isNull);
    });
  });

  group('StatsRange stepping', () {
    test('steps one calendar unit at a time', () {
      final day = StatsRange.specificDay(DateTime(2026, 7, 1));
      expect(day.stepped(-1).bounds(now: now),
          (from: '2026-06-30', to: '2026-06-30'));

      final week = StatsRange.weekOf(DateTime(2026, 7, 9));
      expect(week.stepped(-1).bounds(now: now),
          (from: '2026-06-29', to: '2026-07-05'));
      expect(week.stepped(1).bounds(now: now),
          (from: '2026-07-13', to: '2026-07-19'));

      final month = StatsRange.monthOf(DateTime(2026, 7, 9));
      expect(month.stepped(-1).bounds(now: now),
          (from: '2026-06-01', to: '2026-06-30'));

      final year = StatsRange.yearOf(DateTime(2026, 7, 9));
      expect(year.stepped(-1).bounds(now: now),
          (from: '2025-01-01', to: '2025-12-31'));

      expect(StatsRange.all.stepped(-1), StatsRange.all);
    });

    test('un-anchored ranges step from now', () {
      expect(StatsRange.today.stepped(-1, now: now).bounds(now: now),
          (from: '2026-07-08', to: '2026-07-08'));
    });

    test('cannot page forward past today', () {
      // Ranges containing today are blocked; older ones can advance.
      expect(StatsRange.specificDay(now).canStepForward(now: now), isFalse);
      expect(StatsRange.weekOf(now).canStepForward(now: now), isFalse);
      expect(StatsRange.monthOf(now).canStepForward(now: now), isFalse);
      expect(StatsRange.yearOf(now).canStepForward(now: now), isFalse);
      expect(StatsRange.specificDay(DateTime(2026, 7, 8))
          .canStepForward(now: now), isTrue);
      expect(StatsRange.monthOf(DateTime(2026, 6, 1))
          .canStepForward(now: now), isTrue);
      expect(StatsRange.all.canStepForward(now: now), isFalse);
    });

    test('cannot page back past the first listening day', () {
      const earliest = '2026-05-20';
      expect(
          StatsRange.specificDay(DateTime(2026, 5, 20))
              .canStepBack(earliest, now: now),
          isFalse);
      expect(
          StatsRange.specificDay(DateTime(2026, 5, 21))
              .canStepBack(earliest, now: now),
          isTrue);
      // May 2026 contains the first listen — no paging into April.
      expect(StatsRange.monthOf(DateTime(2026, 5, 1))
          .canStepBack(earliest, now: now), isFalse);
      expect(StatsRange.monthOf(DateTime(2026, 6, 1))
          .canStepBack(earliest, now: now), isTrue);
      // No history at all: nothing to page back to.
      expect(StatsRange.specificDay(now).canStepBack(null, now: now), isFalse);
    });

    test('titles read naturally', () {
      expect(StatsRange.all.title(now: now), 'All time');
      expect(StatsRange.specificDay(now).title(now: now), 'Today');
      expect(StatsRange.specificDay(DateTime(2026, 7, 8)).title(now: now),
          'Yesterday');
      expect(StatsRange.specificDay(DateTime(2026, 6, 12)).title(now: now),
          '12 Jun 2026');
      expect(StatsRange.weekOf(now).title(now: now), '6 – 12 Jul 2026');
      expect(StatsRange.weekOf(DateTime(2026, 7, 1)).title(now: now),
          '29 Jun – 5 Jul 2026');
      expect(StatsRange.monthOf(now).title(now: now), 'July 2026');
      expect(StatsRange.yearOf(now).title(now: now), '2026');
    });
  });

  group('PeriodStatsLoader endpoints', () {
    late List<String> dayCalls;
    late List<(String, String)> periodCalls;
    late PeriodStatsLoader loader;

    setUp(() {
      dayCalls = [];
      periodCalls = [];
      loader = PeriodStatsLoader(
        fetchDay: (date, limit) async {
          dayCalls.add(date);
          return _mercyPeriodResponse();
        },
        fetchPeriod: (from, to, limit) async {
          periodCalls.add((from, to));
          return _mercyPeriodResponse();
        },
        fetchArtists: (limit) async => <String, dynamic>{
          'artists': [
            {'artistKey': 'pusha t', 'artistDisplay': 'Pusha T', 'playCount': 3, 'listenedMs': 500000},
          ],
        },
      );
    });

    test('a specific day calls the day endpoint with that date', () async {
      final stats = await loader.load(
        StatsRange.specificDay(DateTime(2026, 6, 12)),
        now: now,
      );
      expect(dayCalls, ['2026-06-12']);
      expect(periodCalls, isEmpty);
      expect(stats, isNotNull);
    });

    test('today calls the day endpoint', () async {
      await loader.load(StatsRange.today, now: now);
      expect(dayCalls, ['2026-07-09']);
      expect(periodCalls, isEmpty);
    });

    test('week/month/year call the period endpoint with the range', () async {
      await loader.load(StatsRange.week, now: now);
      await loader.load(StatsRange.month, now: now);
      await loader.load(StatsRange.year, now: now);
      expect(dayCalls, isEmpty);
      expect(periodCalls, [
        ('2026-07-06', '2026-07-12'),
        ('2026-07-01', '2026-07-31'),
        ('2026-01-01', '2026-12-31'),
      ]);
    });

    test('all-time never hits the period endpoints', () async {
      final stats = await loader.load(StatsRange.all, now: now);
      expect(stats, isNull);
      expect(dayCalls, isEmpty);
      expect(periodCalls, isEmpty);
    });

    test('parses each credited artist as its own row', () async {
      final stats = await loader.load(StatsRange.month, now: now);
      expect(stats, isNotNull);
      expect(stats!.totalListenedMs, 330000);
      expect(stats.totalPlays, 1);
      expect(
        stats.artists.map((artist) => artist.artistDisplay),
        containsAll(['Kanye West', 'Big Sean', 'Pusha T', '2 Chainz']),
      );
      // Every collaborator receives the full play — credit is never split.
      for (final artist in stats.artists) {
        expect(artist.playCount, 1);
        expect(artist.listenedMs, 330000);
      }
    });

    test('loadAllTimeArtists parses credited rollups', () async {
      final artists = await loader.loadAllTimeArtists();
      expect(artists, isNotNull);
      expect(artists!.single.artistDisplay, 'Pusha T');
      expect(artists.single.playCount, 3);
    });
  });

  group('degraded servers and offline', () {
    test('an old-server style response (missing fields) does not crash',
        () async {
      final loader = PeriodStatsLoader(
        // Old servers 404 on /day and /period; simulate the weaker case of a
        // response with none of the expected fields.
        fetchDay: (date, limit) async => <String, dynamic>{'unexpected': true},
        fetchPeriod: (from, to, limit) async => <String, dynamic>{},
        fetchArtists: (limit) async => <String, dynamic>{},
      );
      final day = await loader.load(StatsRange.today, now: now);
      expect(day, isNotNull);
      expect(day!.songs, isEmpty);
      expect(day.artists, isEmpty);
      expect(day.albums, isEmpty);
      expect(day.totalPlays, 0);

      final artists = await loader.loadAllTimeArtists();
      expect(artists, isNotNull);
      expect(artists, isEmpty);
    });

    test('fetch failures (404 / offline) degrade to null', () async {
      final loader = PeriodStatsLoader(
        fetchDay: (date, limit) async => throw Exception('404'),
        fetchPeriod: (from, to, limit) async =>
            throw StateError('Not connected to a server'),
        fetchArtists: (limit) async => throw Exception('404'),
      );
      expect(await loader.load(StatsRange.today, now: now), isNull);
      expect(await loader.load(StatsRange.year, now: now), isNull);
      expect(await loader.loadAllTimeArtists(), isNull);
    });
  });

  group('display model adapters', () {
    test('credited artists recover artwork and song counts from songs',
        () async {
      final loader = PeriodStatsLoader(
        fetchDay: (date, limit) async => _mercyPeriodResponse(),
        fetchPeriod: (from, to, limit) async => _mercyPeriodResponse(),
        fetchArtists: (limit) async => <String, dynamic>{},
      );
      final stats = (await loader.load(StatsRange.today, now: now))!;
      final songs = songStatsFromRollups(stats.songs);
      final artists = artistStatsFromCredited(stats.artists, songs);

      expect(artists, hasLength(4));
      final bigSean =
          artists.singleWhere((artist) => artist.artistName == 'Big Sean');
      expect(bigSean.playCount, 1);
      expect(bigSean.totalTime, const Duration(milliseconds: 330000));
      // Matched back to the combined-string song for artwork + count.
      expect(bigSean.randomAlbumId, 'album-cruel-summer');
      expect(bigSean.uniqueSongsCount, 1);
    });

    test('an artist with no matching song keeps zero songs and no artwork',
        () {
      final artists = artistStatsFromCredited(
        [
          ListeningArtistRollup.fromJson(const {
            'artistKey': 'ghost',
            'artistDisplay': 'Ghost',
            'playCount': 2,
            'listenedMs': 1000,
          }),
        ],
        const [],
      );
      expect(artists.single.uniqueSongsCount, 0);
      expect(artists.single.randomAlbumId, isNull);
      expect(artists.single.randomSongId, isNull);
    });

    test('album rollups without a catalog id keep an empty albumId', () async {
      final loader = PeriodStatsLoader(
        fetchDay: (date, limit) async => <String, dynamic>{
          'albums': [
            {'albumKey': 'name:untagged', 'album': 'Untagged', 'playCount': 2, 'listenedMs': 60000},
          ],
        },
        fetchPeriod: (from, to, limit) async => <String, dynamic>{},
        fetchArtists: (limit) async => <String, dynamic>{},
      );
      final stats = (await loader.load(StatsRange.today, now: now))!;
      final albums = albumStatsFromRollups(stats.albums);
      expect(albums.single.albumId, isEmpty);
      expect(albums.single.albumName, 'Untagged');
      expect(albums.single.uniqueSongsCount, 0);
    });
  });
}
