import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';

/// Presentation helpers for the aggregated genre tags exposed by
/// `LibraryController.albumGenres`. Tags are stored normalized (lowercase), so
/// everything user-facing goes through [musicDiscoveryTagLabel] for casing.

/// A compact one-line label such as `Rock` or `Rock +2`, or null when the item
/// carries no usable genre tag. Callers hide their genre affordance on null
/// rather than showing an "Unknown" placeholder — a library with thin tags
/// would otherwise read as broken.
String? genreSummary(List<String> genres) {
  if (genres.isEmpty) return null;
  final primary = musicDiscoveryTagLabel(genres.first);
  return genres.length == 1 ? primary : '$primary +${genres.length - 1}';
}

/// The full list, for tooltips and detail headers: `Jazz · Rock · Funk`.
String? genreDetail(List<String> genres) {
  if (genres.isEmpty) return null;
  return genres.map(musicDiscoveryTagLabel).join(' · ');
}

/// The facets a filter bar shows. A well-tagged library yields a long tail of
/// one-album genres, and rendering all of them pushes the albums themselves
/// off screen — so collapsed shows only the widest [limit].
///
/// The active facet is always included: selecting a genre from the expanded
/// list and then collapsing must not strand the filter with no way to clear
/// it from the bar.
List<String> visibleGenreFacets(
  List<String> genres,
  String? selected, {
  required int limit,
  required bool expanded,
}) {
  if (expanded || genres.length <= limit) return genres;
  final head = genres.take(limit).toList();
  if (selected != null && !head.contains(selected)) head.add(selected);
  return head;
}
