/// Turns ranked listening data into weighted discovery seeds.
///
/// Every client reaches this from a different stats shape — account
/// snapshots, server period rollups, mobile's local store — so callers map
/// their rows to [TasteSeedEntry] and the weighting rule itself lives here
/// once.
library;

import 'music_recommendation_models.dart';

/// One ranked taste row: an artist, or a track when [title] is set.
class TasteSeedEntry {
  const TasteSeedEntry.artist(this.artist, this.listenedMs) : title = null;

  const TasteSeedEntry.track({
    required this.artist,
    required String this.title,
    required this.listenedMs,
  });

  final String artist;
  final String? title;
  final int listenedMs;
}

/// The lowest weight any surviving seed gets, so the tail of a deep selection
/// still influences ranking instead of being rounded away.
const double _minimumSeedWeight = 0.35;

/// Weighted seeds for [artists] and [tracks], deepest-listened first.
///
/// Each list is ranked and weighted independently against its own strongest
/// entry, so a dominant favourite cannot flatten the other list. [depth]
/// applies per list: `depth: 3` yields at most three artist seeds and three
/// track seeds, and therefore at most six Last.fm requests.
List<MusicRecommendationSeed> buildTasteSeeds({
  Iterable<TasteSeedEntry> artists = const <TasteSeedEntry>[],
  Iterable<TasteSeedEntry> tracks = const <TasteSeedEntry>[],
  required int depth,
}) =>
    <MusicRecommendationSeed>[
      ..._weighted(artists, depth, track: false),
      ..._weighted(tracks, depth, track: true),
    ];

List<MusicRecommendationSeed> _weighted(
  Iterable<TasteSeedEntry> source,
  int depth, {
  required bool track,
}) {
  if (depth <= 0) return const <MusicRecommendationSeed>[];
  final ranked = source
      .where((entry) =>
          entry.artist.trim().isNotEmpty &&
          (!track || (entry.title?.trim().isNotEmpty ?? false)))
      .toList()
    ..sort((a, b) => b.listenedMs.compareTo(a.listenedMs));
  if (ranked.isEmpty) return const <MusicRecommendationSeed>[];
  // Guard the divisor: a zero-time top row would otherwise make every weight
  // NaN and silently drop the whole list at scoring time.
  final strongest = ranked.first.listenedMs < 1 ? 1 : ranked.first.listenedMs;
  return <MusicRecommendationSeed>[
    for (final entry in ranked.take(depth))
      if (track)
        MusicRecommendationSeed.track(
          artist: entry.artist.trim(),
          title: entry.title!.trim(),
          weight: _weight(entry.listenedMs, strongest),
        )
      else
        MusicRecommendationSeed.artist(
          entry.artist.trim(),
          weight: _weight(entry.listenedMs, strongest),
        ),
  ];
}

double _weight(int listenedMs, int strongest) =>
    (_minimumSeedWeight + (1 - _minimumSeedWeight) * listenedMs / strongest)
        .clamp(_minimumSeedWeight, 1);
