/// Turns ranked listening data into weighted discovery seeds.
///
/// Every client reaches this from a different stats shape — account
/// snapshots, server period rollups, mobile's local store — so callers map
/// their rows to [TasteSeedEntry] and the weighting rule itself lives here
/// once.
library;

import 'dart:math' as math;

import '../stats/credited_artist_splitter.dart';
import 'music_recommendation_models.dart';

/// One ranked taste row: an artist, or a track when [title] is set.
class TasteSeedEntry {
  const TasteSeedEntry.artist(
    this.artist,
    this.listenedMs, {
    this.lastPlayedMs,
  }) : title = null;

  const TasteSeedEntry.track({
    required this.artist,
    required String this.title,
    required this.listenedMs,
    this.lastPlayedMs,
  });

  final String artist;
  final String? title;
  final int listenedMs;
  final int? lastPlayedMs;
}

/// The lowest weight any surviving seed gets, so the tail of a deep selection
/// still influences ranking instead of being rounded away.
const double _minimumSeedWeight = 0.35;
const double _recencyHalfLifeDays = 90;
const double _recencyFloor = 0.25;
final CreditedArtistSplitter _seedArtistSplitter = CreditedArtistSplitter();

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
  int maxTracksPerArtist = 2,
  DateTime? now,
}) {
  final nowMs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  return <MusicRecommendationSeed>[
    ..._weighted(artists, depth, track: false, nowMs: nowMs),
    ..._weighted(
      tracks,
      depth,
      track: true,
      maxPerArtist: maxTracksPerArtist,
      nowMs: nowMs,
    ),
  ];
}

List<MusicRecommendationSeed> _weighted(
  Iterable<TasteSeedEntry> source,
  int depth, {
  required bool track,
  int? maxPerArtist,
  required int nowMs,
}) {
  if (depth <= 0) return const <MusicRecommendationSeed>[];
  final scored = <({TasteSeedEntry entry, double score})>[
    for (final entry in source)
      if (entry.artist.trim().isNotEmpty &&
          (!track || (entry.title?.trim().isNotEmpty ?? false)))
        (entry: entry, score: _effectiveScore(entry, nowMs)),
  ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : b.entry.listenedMs.compareTo(a.entry.listenedMs);
    });
  if (scored.isEmpty) return const <MusicRecommendationSeed>[];

  final chosen = <({TasteSeedEntry entry, double score})>[];
  final perArtistCounts = <String, int>{};
  for (final item in scored) {
    if (chosen.length >= depth) break;
    if (track && maxPerArtist != null && maxPerArtist > 0) {
      final artistKey = _primaryArtistKey(item.entry.artist);
      final count = perArtistCounts[artistKey] ?? 0;
      if (count >= maxPerArtist) continue;
      perArtistCounts[artistKey] = count + 1;
    }
    chosen.add(item);
  }
  if (chosen.isEmpty) return const <MusicRecommendationSeed>[];

  // Guard the divisor: a zero-time top row would otherwise make every weight
  // NaN and silently drop the whole list at scoring time.
  final strongest = chosen.first.score < 1 ? 1.0 : chosen.first.score;
  return <MusicRecommendationSeed>[
    for (final item in chosen)
      if (track)
        MusicRecommendationSeed.track(
          artist: item.entry.artist.trim(),
          title: item.entry.title!.trim(),
          weight: _weight(item.score, strongest),
        )
      else
        MusicRecommendationSeed.artist(
          item.entry.artist.trim(),
          weight: _weight(item.score, strongest),
        ),
  ];
}

double _effectiveScore(TasteSeedEntry entry, int nowMs) {
  final lastPlayedMs = entry.lastPlayedMs;
  if (lastPlayedMs == null) return entry.listenedMs.toDouble();
  final ageDays =
      math.max(0.0, (nowMs - lastPlayedMs) / Duration.millisecondsPerDay);
  final decay = _recencyFloor +
      (1 - _recencyFloor) * math.pow(0.5, ageDays / _recencyHalfLifeDays);
  return entry.listenedMs * decay;
}

String _primaryArtistKey(String rawArtist) {
  final credits = _seedArtistSplitter.split(rawArtist);
  return credits.isNotEmpty ? credits.first.key : normalizeArtistKey(rawArtist);
}

double _weight(double score, double strongest) =>
    (_minimumSeedWeight + (1 - _minimumSeedWeight) * score / strongest)
        .clamp(_minimumSeedWeight, 1);
