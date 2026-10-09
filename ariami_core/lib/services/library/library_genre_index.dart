import '../recommendations/music_recommendation_models.dart';

/// One track's contribution to the genre facets. App track models can
/// implement this directly; tracks without an album are skipped.
class LibraryGenreSource {
  const LibraryGenreSource({
    required this.albumId,
    required this.genre,
  });

  final String? albumId;
  final String? genre;
}

/// Album-level genre facets aggregated from per-track metadata.
///
/// Genre is a per-track tag, so album-level genre is aggregated rather than
/// stored: an album whose tracks carry different tags keeps all of them, which
/// is the common case for compilations and for the "instrumental rock, metal"
/// style of library where one record spans several labels.
class LibraryGenreIndex {
  const LibraryGenreIndex({
    required this.albumGenres,
    required this.genreAlbums,
    required this.genres,
  });

  /// Album id -> its genres, most-tagged first.
  final Map<String, List<String>> albumGenres;

  /// Genre -> the album ids carrying it.
  final Map<String, Set<String>> genreAlbums;

  /// Every genre in the library, widest first, then alphabetical.
  final List<String> genres;

  static const empty = LibraryGenreIndex(
    albumGenres: <String, List<String>>{},
    genreAlbums: <String, Set<String>>{},
    genres: <String>[],
  );

  factory LibraryGenreIndex.build(Iterable<LibraryGenreSource> sources) {
    final tallies = <String, Map<String, int>>{};
    for (final source in sources) {
      final albumId = source.albumId;
      if (albumId == null) continue;
      final tags = musicGenreTags(source.genre);
      if (tags.isEmpty) continue;
      final bucket = tallies.putIfAbsent(albumId, () => <String, int>{});
      for (final tag in tags) {
        bucket.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final albumGenres = <String, List<String>>{};
    for (final entry in tallies.entries) {
      // Alphabetical tie-break keeps the label stable across rebuilds instead
      // of flipping with map iteration order.
      albumGenres[entry.key] = entry.value.keys.toList()
        ..sort((a, b) {
          final byCount = entry.value[b]!.compareTo(entry.value[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
    }
    return LibraryGenreIndex._fromAlbumGenres(albumGenres);
  }

  factory LibraryGenreIndex.merge(Iterable<LibraryGenreIndex> indexes) {
    final albumGenres = <String, List<String>>{};
    for (final index in indexes) {
      albumGenres.addAll(index.albumGenres);
    }
    return LibraryGenreIndex._fromAlbumGenres(albumGenres);
  }

  factory LibraryGenreIndex._fromAlbumGenres(
    Map<String, List<String>> albumGenres,
  ) {
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
