import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';

class LibraryGenreSource {
  const LibraryGenreSource({
    required this.albumId,
    required this.genre,
  });

  final String albumId;
  final String? genre;
}

/// Album-level genre facets aggregated from per-track metadata.
class LibraryGenreIndex {
  const LibraryGenreIndex({
    required this.albumGenres,
    required this.genreAlbums,
    required this.genres,
  });

  final Map<String, List<String>> albumGenres;
  final Map<String, Set<String>> genreAlbums;
  final List<String> genres;

  static const empty = LibraryGenreIndex(
    albumGenres: <String, List<String>>{},
    genreAlbums: <String, Set<String>>{},
    genres: <String>[],
  );

  factory LibraryGenreIndex.build(Iterable<LibraryGenreSource> sources) {
    final tallies = <String, Map<String, int>>{};
    for (final source in sources) {
      final tags = musicGenreTags(source.genre);
      if (tags.isEmpty) continue;
      final bucket = tallies.putIfAbsent(source.albumId, () => <String, int>{});
      for (final tag in tags) {
        bucket.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final albumGenres = <String, List<String>>{};
    final genreAlbums = <String, Set<String>>{};
    for (final entry in tallies.entries) {
      final ranked = entry.value.keys.toList()
        ..sort((a, b) {
          final byCount = entry.value[b]!.compareTo(entry.value[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      albumGenres[entry.key] = ranked;
      for (final genre in ranked) {
        genreAlbums.putIfAbsent(genre, () => <String>{}).add(entry.key);
      }
    }

    final genres = genreAlbums.keys.toList()
      ..sort((a, b) {
        final byBreadth =
            genreAlbums[b]!.length.compareTo(genreAlbums[a]!.length);
        return byBreadth != 0 ? byBreadth : a.compareTo(b);
      });

    return LibraryGenreIndex(
      albumGenres: albumGenres,
      genreAlbums: genreAlbums,
      genres: genres,
    );
  }

  factory LibraryGenreIndex.merge(Iterable<LibraryGenreIndex> indexes) {
    final albumGenres = <String, List<String>>{};
    for (final index in indexes) {
      albumGenres.addAll(index.albumGenres);
    }
    final genreAlbums = <String, Set<String>>{};
    for (final entry in albumGenres.entries) {
      for (final genre in entry.value) {
        genreAlbums.putIfAbsent(genre, () => <String>{}).add(entry.key);
      }
    }
    final genres = genreAlbums.keys.toList()
      ..sort((a, b) {
        final byBreadth =
            genreAlbums[b]!.length.compareTo(genreAlbums[a]!.length);
        return byBreadth != 0 ? byBreadth : a.compareTo(b);
      });
    return LibraryGenreIndex(
      albumGenres: albumGenres,
      genreAlbums: genreAlbums,
      genres: genres,
    );
  }
}
