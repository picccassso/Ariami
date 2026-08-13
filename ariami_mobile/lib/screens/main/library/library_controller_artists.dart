part of 'library_controller.dart';

/// Artist lookups over the in-memory library catalog, built on
/// [LibraryArtistIndex] and memoized while the catalog lists stay the same.
extension _LibraryControllerArtists on LibraryController {
  static final CreditedArtistSplitter _splitter = CreditedArtistSplitter();

  /// Bumped every time [PlaylistService] notifies. Its `playlists` getter
  /// returns a fresh unmodifiable wrapper per access, so wrapper identity
  /// cannot double as the rebuild signal the way album/song list identity
  /// does — the notification revision can.
  static int _playlistRevision = 0;
  static bool _playlistRevisionListenerAttached = false;

  static void _ensurePlaylistRevisionListener() {
    if (_playlistRevisionListenerAttached) return;
    _playlistRevisionListenerAttached = true;
    PlaylistService().addListener(() => _playlistRevision++);
  }

  /// Rebuilds the index only when the catalog lists are replaced. The artist
  /// page re-reads this on every rebuild, so it must not re-walk the whole
  /// library per call.
  LibraryArtistIndex get _artistIndex {
    final albums = state.albums;
    final songs = state.songs;
    final playlists = PlaylistService().playlists;
    // An uninitialized controller reports const-empty lists; short-circuit to
    // the shared empty index instead of building from them.
    if (albums.isEmpty && songs.isEmpty && playlists.isEmpty) {
      return LibraryArtistIndex.empty;
    }
    _ensurePlaylistRevisionListener();
    if (!identical(albums, _artistIndexAlbumsRef) ||
        !identical(songs, _artistIndexSongsRef) ||
        _playlistRevision != _artistIndexPlaylistRevision) {
      _artistIndexAlbumsRef = albums;
      _artistIndexSongsRef = songs;
      _artistIndexPlaylistRevision = _playlistRevision;
      _artistIndexCache = LibraryArtistIndex.build(
        albums: albums,
        songs: songs,
        playlists: playlists,
      );
    }
    return _artistIndexCache;
  }

  /// The lookup keys for [name]: its normalized full string plus each
  /// credited artist, so pages opened from a combined credit ("A, B") and
  /// from a single name resolve identically.
  Set<String> _lookupKeys(String name) =>
      LibraryArtistIndex.keysFor(_splitter, name);

  List<AlbumModel> _artistAlbums(String name) {
    final result = <AlbumModel>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(_artistIndex.albumsByArtist[key] ?? const <AlbumModel>[]);
    }
    return result.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  List<SongModel> _artistTracks(String name) {
    final result = <SongModel>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(
          _artistIndex.tracksByArtistKey[key] ?? const <SongModel>[]);
    }
    return result.toList();
  }

  /// Albums [name] is credited on without owning: the album ids of every
  /// credited track, minus the artist's own albums, resolved against the
  /// album catalog. Standalone songs and unknown ids fall away. Title-sorted.
  List<AlbumModel> _artistAppearsOn(String name) {
    final ownIds = {for (final album in _artistAlbums(name)) album.id};
    final albumIds = <String>{};
    for (final key in _lookupKeys(name)) {
      for (final track
          in _artistIndex.tracksByArtistKey[key] ?? const <SongModel>[]) {
        final albumId = track.albumId;
        if (albumId != null) albumIds.add(albumId);
      }
    }
    albumIds.removeAll(ownIds);
    final albumsById = {for (final album in state.albums) album.id: album};
    return [
      for (final id in albumIds)
        if (albumsById[id] != null) albumsById[id]!,
    ]..sort((a, b) => a.title.compareTo(b.title));
  }

  List<PlaylistModel> _playlistsWithArtist(String name) {
    final result = <PlaylistModel>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(
          _artistIndex.playlistsByArtistKey[key] ?? const <PlaylistModel>[]);
    }
    return result.toList();
  }
}
