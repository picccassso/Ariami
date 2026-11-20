part of '../library_controller.dart';

extension _LibraryControllerGenres on LibraryController {
  /// Rebuilds the index only when the underlying song list is replaced. Every
  /// album card asks for its genres during a grid build, so this must not
  /// re-walk the whole library per call.
  LibraryGenreIndex get _genres {
    final currentSongs = songs;
    if (!identical(_genreIndexRef, currentSongs)) {
      _genreIndexRef = currentSongs;
      _genreIndexCache = LibraryGenreIndex.build(currentSongs);
    }
    return _genreIndexCache;
  }

  List<String> _albumGenres(String albumId) =>
      _genres.albumGenres[albumId] ?? const <String>[];

  /// The albums matching the active genre filter, in library order. Returns
  /// [albums] untouched when no filter is set.
  ///
  /// Memoized on the album list and the facet: the albums grid re-reads this
  /// on every rebuild, and re-filtering a large library per frame is the kind
  /// of cost the sibling song/playlist caches already exist to avoid.
  List<Album> _albumsInGenre(String? genre) {
    final visibleAlbums = albums;
    if (genre == null) return visibleAlbums;
    final cached = _filteredAlbumsCache;
    if (cached != null &&
        cached.genre == genre &&
        identical(cached.albums, visibleAlbums)) {
      return cached.result;
    }
    final ids = _genres.genreAlbums[genre];
    final result = ids == null
        ? const <Album>[]
        : visibleAlbums.where((album) => ids.contains(album.id)).toList();
    _filteredAlbumsCache = (
      genre: genre,
      albums: visibleAlbums,
      result: result,
    );
    return result;
  }

  void _setGenreFilter(String? genre) {
    if (_genreFilter == genre) return;
    _genreFilter = genre;
    _notifyListeners();
  }
}
