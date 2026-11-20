part of '../library_controller.dart';

/// Lightweight, locally derived artist metadata for library navigation.
///
/// The server does not expose artist entities, so this summary deliberately
/// contains only data that can be derived reliably from the catalog —
/// including the cover that stands in for an artist portrait when no custom
/// artist image has been synced.
@immutable
class LibraryArtistSummary {
  const LibraryArtistSummary({
    required this.name,
    required this.albumCount,
    this.artworkAlbumId,
    this.artworkSongId,
  });

  final String name;
  final int albumCount;

  /// First known cover for the artist: one of their own albums, then an album
  /// they appear on. Null when no related album advertises artwork.
  final String? artworkAlbumId;

  /// Song-artwork fallback when the chosen album is missing or fails to load.
  final String? artworkSongId;
}

/// Desktop's artist lookups, plus the sidebar's [artists] summaries; the
/// credited-artist derivation lives in [CatalogArtistIndex].
class LibraryArtistIndex
    extends CatalogArtistIndex<Album, Track, PlaylistSummary> {
  const LibraryArtistIndex({
    required super.albumsByArtist,
    required super.tracksByArtistKey,
    required super.playlistsByArtistKey,
    required this.artists,
  });

  final List<LibraryArtistSummary> artists;

  static const empty = LibraryArtistIndex(
    albumsByArtist: <String, List<Album>>{},
    tracksByArtistKey: <String, List<Track>>{},
    playlistsByArtistKey: <String, List<PlaylistSummary>>{},
    artists: <LibraryArtistSummary>[],
  );

  static const keysFor = CatalogArtistIndex.keysFor;

  /// Builds the index once per catalog shape. Callers memoize on the identity
  /// of the source lists (see [_artistIndex]).
  factory LibraryArtistIndex.build({
    required List<Album> albums,
    required List<Track> songs,
    required List<PlaylistSummary> playlists,
  }) {
    final splitter = CreditedArtistSplitter();
    final base = CatalogArtistIndex.build<Album, Track, PlaylistSummary>(
      albums: albums,
      songs: songs,
      playlists: playlists,
      albumId: (album) => album.id,
      albumTitle: (album) => album.title,
      albumArtist: (album) => album.artist,
      trackId: (track) => track.id,
      trackArtist: (track) => track.artist,
      trackAlbumId: (track) => track.albumId,
      trackAlbumArtist: (track, _) => track.albumArtist,
      playlistSongIds: (playlist) => playlist.songIds,
      splitter: splitter,
    );
    final albumsByArtist = base.albumsByArtist;
    final tracksByArtistKey = base.tracksByArtistKey;

    // Album credits are walked first so their spelling wins when a track
    // credit for the same artist is tagged differently.
    final artistsByKey = <String, String>{};
    final albumsById = {for (final album in albums) album.id: album};
    void addArtists(String? rawArtist) {
      for (final credit in splitter.split(rawArtist)) {
        artistsByKey.putIfAbsent(credit.key, () => credit.display);
      }
    }

    for (final album in albums) {
      addArtists(album.artist);
    }
    for (final track in songs) {
      addArtists(track.artist);
      addArtists(track.albumArtist);
    }
    final artists = [
      for (final entry in artistsByKey.entries)
        _summaryFor(
          display: entry.value,
          artistAlbums: albumsByArtist[entry.key],
          artistTracks: tracksByArtistKey[entry.key],
          albumsById: albumsById,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return LibraryArtistIndex(
      albumsByArtist: albumsByArtist,
      tracksByArtistKey: tracksByArtistKey,
      playlistsByArtistKey: base.playlistsByArtistKey,
      artists: artists,
    );
  }

  /// Builds one artist's summary, resolving the first album known to have art,
  /// then retaining a credited song as a runtime fallback.
  static LibraryArtistSummary _summaryFor({
    required String display,
    required List<Album>? artistAlbums,
    required List<Track>? artistTracks,
    required Map<String, Album> albumsById,
  }) {
    final albums = artistAlbums ?? const <Album>[];
    final tracks = artistTracks ?? const <Track>[];
    final fallbackSongId = tracks.isEmpty ? null : tracks.first.id;
    for (final album in albums) {
      if (album.coverArtPath?.trim().isNotEmpty == true) {
        return LibraryArtistSummary(
          name: display,
          albumCount: albums.length,
          artworkAlbumId: album.id,
          artworkSongId: fallbackSongId,
        );
      }
    }
    // Guests can borrow a known cover from an album they appear on.
    for (final track in tracks) {
      final albumId = track.albumId;
      final album = albumId == null ? null : albumsById[albumId];
      if (album?.coverArtPath?.trim().isNotEmpty == true) {
        return LibraryArtistSummary(
          name: display,
          albumCount: albums.length,
          artworkAlbumId: albumId,
          artworkSongId: fallbackSongId,
        );
      }
    }
    return LibraryArtistSummary(
      name: display,
      albumCount: albums.length,
      artworkSongId: fallbackSongId,
    );
  }
}

extension _LibraryControllerArtists on LibraryController {
  static final CreditedArtistSplitter _splitter = CreditedArtistSplitter();

  /// Rebuilds the index only when the catalog lists are replaced. The artist
  /// page re-reads this on every rebuild, so it must not re-walk the whole
  /// library per call.
  LibraryArtistIndex get _artistIndex {
    if (!identical(_artistIndexSongsRef, songs) ||
        !identical(_artistIndexAlbumsRef, albums) ||
        !identical(_artistIndexPlaylistsRef, playlists)) {
      _artistIndexSongsRef = songs;
      _artistIndexAlbumsRef = albums;
      _artistIndexPlaylistsRef = playlists;
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

  List<LibraryArtistSummary> _searchArtists(String query) {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) return const <LibraryArtistSummary>[];
    return LibrarySearchEngine.rank(
      parsed,
      _artistIndex.artists,
      (artist) => [SearchField(artist.name, isPrimary: true)],
      limit: 40,
    );
  }

  List<Album> _artistAlbums(String name) {
    final result = <Album>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(_artistIndex.albumsByArtist[key] ?? const <Album>[]);
    }
    return result.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  List<Track> _artistTracks(String name) {
    final result = <Track>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(_artistIndex.tracksByArtistKey[key] ?? const <Track>[]);
    }
    return result.toList();
  }

  /// Albums [name] is credited on without owning: the album ids of every
  /// credited track, minus the artist's own albums, resolved against the
  /// album catalog. Standalone songs and unknown ids fall away. Title-sorted.
  List<Album> _artistAppearsOn(String name) {
    final ownIds = {for (final album in _artistAlbums(name)) album.id};
    final albumIds = <String>{};
    for (final key in _lookupKeys(name)) {
      for (final track
          in _artistIndex.tracksByArtistKey[key] ?? const <Track>[]) {
        final albumId = track.albumId;
        if (albumId != null) albumIds.add(albumId);
      }
    }
    albumIds.removeAll(ownIds);
    final albumsById = {for (final album in albums) album.id: album};
    return [
      for (final id in albumIds)
        if (albumsById[id] != null) albumsById[id]!,
    ]..sort((a, b) => a.title.compareTo(b.title));
  }

  List<PlaylistSummary> _playlistsWithArtist(String name) {
    final result = <PlaylistSummary>{};
    for (final key in _lookupKeys(name)) {
      result.addAll(
          _artistIndex.playlistsByArtistKey[key] ?? const <PlaylistSummary>[]);
    }
    return result.toList();
  }

  void _applyArtistImageVersions(Map<String, int> imageVersions) {
    _artistImageVersions
      ..clear()
      ..addAll(imageVersions);
  }

  Future<void> _refreshArtistImages() async {
    final client = _client;
    if (client == null) return;
    final versions = await client.fetchArtistImages();
    if (!identical(client, _client)) return;
    _applyArtistImageVersions(versions);
    _notifyListeners();
  }

  Future<void> _setArtistImage(
    String artistName, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    final client = _client;
    if (client == null) {
      throw PlayerApiException('NOT_CONNECTED', 'Not connected to a server.');
    }
    final updatedAt = await client.putArtistImage(
      artistName,
      bytes: bytes,
      contentType: contentType,
    );
    final key = normalizeArtistKey(artistName);
    _artistImageVersions[key] =
        updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    _notifyListeners();
  }

  Future<void> _removeArtistImage(String artistName) async {
    final client = _client;
    if (client == null) {
      throw PlayerApiException('NOT_CONNECTED', 'Not connected to a server.');
    }
    await client.deleteArtistImage(artistName);
    final key = normalizeArtistKey(artistName);
    _artistImageVersions.remove(key);
    _notifyListeners();
  }
}
