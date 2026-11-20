part of '../library_controller.dart';

extension _LibraryControllerBrowsing on LibraryController {
  /// Returns album detail, caching the result. Offline (or when the fetch
  /// fails) the detail is synthesized from the flat song list instead, so
  /// album pages still open while the server is unreachable.
  Future<AlbumDetail> _albumDetail(String albumId) async {
    final cached = _albumDetailCache[albumId];
    if (cached != null) return cached;
    final client = _client;
    if (client != null) {
      try {
        final detail = await client.fetchAlbumDetail(albumId);
        _albumDetailCache[albumId] = detail;
        return detail;
      } catch (_) {
        // Fall through to the local synthesis below.
      }
    }
    // Deliberately not cached: a later successful fetch should replace it.
    final synthesized = _synthesizeAlbumDetail(albumId);
    if (synthesized != null) return synthesized;
    throw PlayerApiException(
      'NOT_CONNECTED',
      'This album is not available offline.',
    );
  }

  AlbumDetail? _synthesizeAlbumDetail(String albumId) {
    final tracks = _songs.where((s) => s.albumId == albumId).toList()
      ..sort((a, b) =>
          (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30));
    if (tracks.isEmpty) return null;
    final albumIndex = _albums.indexWhere((a) => a.id == albumId);
    final album = albumIndex >= 0 ? _albums[albumIndex] : null;
    return AlbumDetail(
      id: albumId,
      title: album?.title ?? tracks.first.albumTitle ?? 'Unknown Album',
      artist: album?.artist ?? tracks.first.artist,
      coverArtPath: album?.coverArtPath,
      tracks: tracks,
    );
  }

  /// Resolves the tracks for a playlist, in playlist order, from the flat song
  /// list. Result is cached so repeated rebuilds don't re-resolve every time.
  List<Track> _playlistTracks(PlaylistSummary playlist) {
    if (playlist.songIds.isEmpty) return const <Track>[];

    final cached = _playlistTracksCache[playlist.id];
    if (cached != null &&
        identical(cached.ids, playlist.songIds) &&
        identical(cached.songs, _songs)) {
      return cached.result;
    }

    // Resolve in playlist order. We append matches while walking songIds, so
    // the result is already ordered — no sort needed. Most servers include
    // playlist songs in /v2/songs, so unresolved ids are rare and just dropped.
    final byId = _songsById;
    final resolved = <Track>[];
    for (final id in playlist.songIds) {
      final t = byId[id];
      if (t != null) resolved.add(t);
    }

    _playlistTracksCache[playlist.id] =
        (ids: playlist.songIds, songs: _songs, result: resolved);
    return resolved;
  }

  /// Returns up to [max] tracks from the start of a playlist, used to build a
  /// 2×2 cover-art mosaic (mirrors the mobile app's playlist thumbnails).
  List<Track> _playlistCoverTracks(PlaylistSummary playlist, {int max = 4}) {
    if (playlist.songIds.isEmpty) return const <Track>[];
    final byId = _songsById;
    final out = <Track>[];
    for (final id in playlist.songIds) {
      final track = byId[id];
      if (track == null) continue;
      out.add(track);
      if (out.length >= max) break;
    }
    return out;
  }

  static const int _searchSongLimit = 60;
  static const int _searchAlbumLimit = 40;
  static const int _searchPlaylistLimit = 20;

  void _warmSearchWorkers() {
    if (_disposed || !hasContent) return;
    _syncWorkerSlot(_curatedSearchSlot, includeFullCatalog: false);
    if (_fullSearchSlot.worker != null) {
      if (_curationFilter.isPassThrough) {
        _fullSearchSlot.dispose();
      } else {
        _syncWorkerSlot(_fullSearchSlot, includeFullCatalog: true);
      }
    }
  }

  void _syncWorkerSlot(
    _SearchWorkerSlot slot, {
    required bool includeFullCatalog,
  }) {
    final targetAlbums = includeFullCatalog ? _albums : albums;
    final targetSongs = includeFullCatalog ? _songs : songs;
    final targetPlaylists = includeFullCatalog ? _playlists : playlists;
    if (identical(slot.albumsRef, targetAlbums) &&
        identical(slot.songsRef, targetSongs) &&
        identical(slot.playlistsRef, targetPlaylists)) {
      return;
    }
    final worker = slot.worker ??= LibrarySearchWorker();
    slot.albumsRef = targetAlbums;
    slot.songsRef = targetSongs;
    slot.playlistsRef = targetPlaylists;
    slot.pendingSync = worker.setCatalog(
      songs: [
        for (final s in targetSongs)
          SearchableSongEntry(
            id: s.id,
            title: s.title,
            artist: s.artist,
            albumId: s.albumId,
            albumTitle: s.albumTitle,
            albumArtist: s.albumArtist,
            lyrics: s.lyrics,
          ),
      ],
      albums: [
        for (final a in targetAlbums)
          SearchableAlbumEntry(id: a.id, title: a.title, artist: a.artist),
      ],
      playlists: [
        for (final p in targetPlaylists)
          SearchablePlaylistEntry(id: p.id, name: p.name),
      ],
    );
  }

  /// Off-isolate search over albums, songs (with lyrics), and playlists.
  Future<LibrarySearchResults> _searchAsync(
    String query, {
    bool includeFullCatalog = false,
  }) async {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) return LibrarySearchResults.empty;
    if (!hasContent) {
      return search(query, includeFullCatalog: includeFullCatalog);
    }
    final full = includeFullCatalog && !_curationFilter.isPassThrough;
    final slot = full ? _fullSearchSlot : _curatedSearchSlot;
    _syncWorkerSlot(slot, includeFullCatalog: full);
    await slot.pendingSync;
    if (_disposed) return LibrarySearchResults.empty;
    final worker = slot.worker;
    if (worker == null) return LibrarySearchResults.empty;
    final results = await worker.search(
      query,
      songLimit: _searchSongLimit,
      albumLimit: _searchAlbumLimit,
      playlistLimit: _searchPlaylistLimit,
    );
    if (_disposed) return LibrarySearchResults.empty;
    if (results.isEmpty) return LibrarySearchResults.empty;
    final songsById = _songsById;
    final albumsById = _albumsById;
    final playlistsById = _playlistsById;
    return LibrarySearchResults(
      albums: [
        for (final id in results.albumIds)
          if (albumsById[id] case final album?) album,
      ],
      songs: [
        for (final id in results.songIds)
          if (songsById[id] case final song?) song,
      ],
      playlists: [
        for (final id in results.playlistIds)
          if (playlistsById[id] case final playlist?) playlist,
      ],
      lyricSnippets: results.lyricSnippets,
    );
  }

  /// Collection-only search (albums and playlists, skipping songs and lyrics).
  LibrarySearchResults _searchCollections(String query) {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) return LibrarySearchResults.empty;
    return LibrarySearchResults(
      albums: LibrarySearchEngine.rank(
        parsed,
        albums,
        (a) => [SearchField(a.title, isPrimary: true), SearchField(a.artist)],
        limit: _searchAlbumLimit,
      ),
      songs: const <Track>[],
      playlists: LibrarySearchEngine.rank(
        parsed,
        playlists,
        (p) => [SearchField(p.name, isPrimary: true)],
        limit: _searchPlaylistLimit,
      ),
    );
  }

  /// Local search over albums, songs and playlists via the shared core
  /// engine, so results match the mobile and TV clients (tokenized queries,
  /// tiered ranking, transliteration and keyboard-layout correction).
  LibrarySearchResults _search(
    String query, {
    bool includeFullCatalog = false,
  }) {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) return LibrarySearchResults.empty;
    final albumList = includeFullCatalog ? _albums : albums;
    final songList = includeFullCatalog ? _songs : songs;
    final playlistList = includeFullCatalog ? _playlists : playlists;
    final albumById = _albumsById;
    final rankedSongs = LibrarySearchEngine.rankWithLyrics(
      parsed,
      songList,
      idOf: (s) => s.id,
      fieldsOf: (s) {
        final album = s.albumId == null ? null : albumById[s.albumId];
        final albumTitle = s.albumTitle ?? album?.title;
        return [
          SearchField(s.title, isPrimary: true),
          SearchField(s.artist),
          if (albumTitle != null) SearchField(albumTitle),
          if (album != null) SearchField(album.artist),
        ];
      },
      lyricsOf: (s) => s.lyrics,
      limit: _searchSongLimit,
    );
    return LibrarySearchResults(
      albums: LibrarySearchEngine.rank(
        parsed,
        albumList,
        (a) => [SearchField(a.title, isPrimary: true), SearchField(a.artist)],
        limit: _searchAlbumLimit,
      ),
      songs: rankedSongs.items,
      playlists: LibrarySearchEngine.rank(
        parsed,
        playlistList,
        (p) => [SearchField(p.name, isPrimary: true)],
        limit: _searchPlaylistLimit,
      ),
      lyricSnippets: rankedSongs.lyricSnippets,
    );
  }

  /// Records a track as searched/played from search. New tracks are added to
  /// the front, capped at [recentSearchesLimit] entries; a track already in
  /// [recentSearches] stays where it is, so playing from the visible recents
  /// list doesn't reshuffle it under the user.
  Future<void> _addRecentSearch(Track track) async {
    if (_recentSearches.any((t) => t.id == track.id)) return;
    _recentSearches = <Track>[track, ..._recentSearches]
        .take(_searchSettings.recentSearchesLimit)
        .toList();
    _notifyListeners();
    await _savePreferences();
  }

  Future<void> _removeRecentSearch(String trackId) async {
    final next = _recentSearches.where((t) => t.id != trackId).toList();
    if (next.length == _recentSearches.length) return;
    _recentSearches = next;
    _notifyListeners();
    await _savePreferences();
  }

  Future<void> _clearRecentSearches() => _restoreRecentSearches(const []);

  Future<void> _restoreRecentSearches(List<Track> tracks) async {
    if (_recentSearches.isEmpty && tracks.isEmpty) return;
    _recentSearches = List<Track>.unmodifiable(
      tracks.take(_searchSettings.recentSearchesLimit),
    );
    _notifyListeners();
    await _savePreferences();
  }

  Future<List<Track>> _trimRecentSearches([int? limit]) async {
    final maxLimit = (limit ?? _searchSettings.recentSearchesLimit)
        .clamp(0, _recentSearches.length);
    if (_recentSearches.length > maxLimit) {
      _recentSearches = _recentSearches.take(maxLimit).toList();
      _notifyListeners();
      await _savePreferences();
    }
    return _recentSearches;
  }
}
