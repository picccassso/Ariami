import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';

String? genreSummary(List<String> genres) {
  if (genres.isEmpty) return null;
  final primary = musicDiscoveryTagLabel(genres.first);
  return genres.length == 1 ? primary : '$primary +${genres.length - 1}';
}

String? genreDetail(List<String> genres) {
  if (genres.isEmpty) return null;
  return genres.map(musicDiscoveryTagLabel).join(' · ');
}

List<String> visibleGenreFacets(
  List<String> genres,
  String? selected, {
  required int limit,
  required bool expanded,
}) {
  if (expanded || genres.length <= limit) return genres;
  final visible = genres.take(limit).toList();
  if (selected != null && !visible.contains(selected)) visible.add(selected);
  return visible;
}
