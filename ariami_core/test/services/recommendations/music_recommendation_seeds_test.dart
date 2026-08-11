import 'package:ariami_core/ariami_core.dart';
import 'package:test/test.dart';

void main() {
  group('buildTasteSeeds', () {
    test('ranks by listening time and honours depth per list', () {
      final seeds = buildTasteSeeds(
        artists: <TasteSeedEntry>[
          const TasteSeedEntry.artist('Third', 1000),
          const TasteSeedEntry.artist('First', 9000),
          const TasteSeedEntry.artist('Second', 5000),
        ],
        tracks: <TasteSeedEntry>[
          const TasteSeedEntry.track(
              artist: 'Band', title: 'Quiet', listenedMs: 200),
          const TasteSeedEntry.track(
              artist: 'Band', title: 'Loud', listenedMs: 800),
        ],
        depth: 2,
      );

      // Depth applies to each list separately: two artists AND two tracks.
      expect(
        seeds.where((seed) => !seed.isTrack).map((seed) => seed.artist),
        <String>['First', 'Second'],
      );
      expect(
        seeds.where((seed) => seed.isTrack).map((seed) => seed.title),
        <String>['Loud', 'Quiet'],
      );
    });

    test('weights each list against its own strongest entry', () {
      final seeds = buildTasteSeeds(
        artists: <TasteSeedEntry>[
          const TasteSeedEntry.artist('Top', 1000),
          const TasteSeedEntry.artist('Tail', 0),
        ],
        tracks: <TasteSeedEntry>[
          // Far less listening than the artists, but still the top track, so
          // it must not be penalised for living in a smaller list.
          const TasteSeedEntry.track(
              artist: 'Band', title: 'Only', listenedMs: 5),
        ],
        depth: 5,
      );

      expect(seeds.first.weight, 1);
      expect(seeds[1].weight, 0.35);
      expect(seeds.last.weight, 1);
    });

    test('drops rows with no usable identity before spending depth', () {
      final seeds = buildTasteSeeds(
        artists: <TasteSeedEntry>[
          const TasteSeedEntry.artist('   ', 9000),
          const TasteSeedEntry.artist('Real', 100),
        ],
        tracks: <TasteSeedEntry>[
          const TasteSeedEntry.track(
              artist: 'Band', title: '  ', listenedMs: 9000),
          const TasteSeedEntry.track(
              artist: '', title: 'Orphan', listenedMs: 8000),
          const TasteSeedEntry.track(
              artist: 'Band', title: 'Keeper', listenedMs: 10),
        ],
        depth: 1,
      );

      expect(seeds.map((seed) => seed.label), <String>['Real', 'Band — Keeper']);
    });

    test('survives an all-zero list without NaN weights', () {
      final seeds = buildTasteSeeds(
        artists: <TasteSeedEntry>[
          const TasteSeedEntry.artist('Silent', 0),
          const TasteSeedEntry.artist('Also silent', 0),
        ],
        depth: 3,
      );

      expect(seeds, hasLength(2));
      for (final seed in seeds) {
        expect(seed.weight.isFinite, isTrue);
        expect(seed.weight, greaterThanOrEqualTo(0.35));
      }
    });

    test('returns nothing for empty input or non-positive depth', () {
      expect(buildTasteSeeds(depth: 5), isEmpty);
      expect(
        buildTasteSeeds(
          artists: <TasteSeedEntry>[const TasteSeedEntry.artist('Real', 10)],
          depth: 0,
        ),
        isEmpty,
      );
    });
  });

  group('StatsRange tokens', () {
    test('round-trip the un-anchored ranges the pickers offer', () {
      for (final range in MusicDiscoveryPreferences.tasteRangeChoices) {
        expect(StatsRange.tryParse(range.token), range);
      }
    });

    test('normalise an anchor to the start of its period, idempotently', () {
      // 4 March 2026 is a Wednesday; the week token anchors to its Monday.
      final anchored = StatsRange.weekOf(DateTime(2026, 3, 4));
      expect(anchored.token, 'week:2026-03-02');
      expect(StatsRange.tryParse(anchored.token)!.token, anchored.token);
      expect(
        StatsRange.tryParse(anchored.token)!.bounds(),
        anchored.bounds(),
      );
    });

    test('collapse same-period anchors but keep different periods apart', () {
      expect(
        StatsRange.monthOf(DateTime(2026, 3, 2)).token,
        StatsRange.monthOf(DateTime(2026, 3, 27)).token,
      );
      expect(
        StatsRange.weekOf(DateTime(2026, 3, 4)).token,
        isNot(StatsRange.weekOf(DateTime(2026, 3, 11)).token),
      );
    });

    test('reject malformed tokens', () {
      expect(StatsRange.tryParse(null), isNull);
      expect(StatsRange.tryParse(''), isNull);
      expect(StatsRange.tryParse('decade'), isNull);
      expect(StatsRange.tryParse('week:not-a-date'), isNull);
    });
  });
}
