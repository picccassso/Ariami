import '../stats/credited_artist_splitter.dart';

/// Artist lookups derived from the in-memory catalog, generic over the app's
/// album [A], track [T] and playlist [P] models.
///
/// Artists are plain display strings (there is no artist entity anywhere in
/// the catalog), so lookups group by normalized name. Albums, songs and
/// playlists are each indexed under every credited artist key (plus the
/// normalized full string), so a song credited "A, B" belongs to both A and B
/// and an album tagged "A & B" appears under both artists' pages — the same
/// derivation the listening-stats layer uses. Normalization also absorbs the
/// tag differences real libraries carry: case, trailing/duplicate whitespace,
/// invisible characters and unicode dash variants.
class CatalogArtistIndex<A, T, P> {
  const CatalogArtistIndex({
    required this.albumsByArtist,
    required this.tracksByArtistKey,
    required this.playlistsByArtistKey,
  });

  /// Normalized credited-artist key -> their albums, title-sorted.
  final Map<String, List<A>> albumsByArtist;

  /// Normalized credited-artist key -> songs credited to them, library order.
  final Map<String, List<T>> tracksByArtistKey;

  /// Normalized credited-artist key -> playlists containing their songs,
  /// library order.
  final Map<String, List<P>> playlistsByArtistKey;

  /// Builds the index once per catalog shape. Callers memoize on the identity
  /// of the source lists. [trackAlbumArtist] receives the track's album from
  /// the catalog (null when unknown) for models that carry no album artist.
  static CatalogArtistIndex<A, T, P> build<A, T, P>({
    required List<A> albums,
    required List<T> songs,
    required List<P> playlists,
    required String Function(A album) albumId,
    required String Function(A album) albumTitle,
    required String Function(A album) albumArtist,
    required String Function(T track) trackId,
    required String Function(T track) trackArtist,
    required String? Function(T track) trackAlbumId,
    required String? Function(T track, A? album) trackAlbumArtist,
    required List<String> Function(P playlist) playlistSongIds,
    CreditedArtistSplitter? splitter,
  }) {
    splitter ??= CreditedArtistSplitter();

    final albumsByArtist = <String, List<A>>{};
    for (final album in albums) {
      for (final key in keysFor(splitter, albumArtist(album))) {
        albumsByArtist.putIfAbsent(key, () => <A>[]).add(album);
      }
    }
    for (final entry in albumsByArtist.values) {
      entry.sort((a, b) => albumTitle(a).compareTo(albumTitle(b)));
    }

    final albumsById = {for (final album in albums) albumId(album): album};

    final tracksByArtistKey = <String, List<T>>{};
    final keysBySongId = <String, Set<String>>{};
    for (final track in songs) {
      final id = trackAlbumId(track);
      final keys = keysForTrack(
        splitter,
        trackArtist(track),
        trackAlbumArtist(track, id == null ? null : albumsById[id]),
      );
      keysBySongId[trackId(track)] = keys;
      for (final key in keys) {
        tracksByArtistKey.putIfAbsent(key, () => <T>[]).add(track);
      }
    }

    final playlistsByArtistKey = <String, List<P>>{};
    for (final playlist in playlists) {
      final keys = <String>{};
      for (final songId in playlistSongIds(playlist)) {
        keys.addAll(keysBySongId[songId] ?? const <String>{});
      }
      for (final key in keys) {
        playlistsByArtistKey.putIfAbsent(key, () => <P>[]).add(playlist);
      }
    }

    return CatalogArtistIndex(
      albumsByArtist: albumsByArtist,
      tracksByArtistKey: tracksByArtistKey,
      playlistsByArtistKey: playlistsByArtistKey,
    );
  }

  /// The normalized keys an artist display string counts toward: the full
  /// string plus every credited artist within it.
  static Set<String> keysFor(CreditedArtistSplitter splitter, String raw) {
    final keys = <String>{normalizeArtistKey(raw)};
    for (final credit in splitter.split(raw)) {
      keys.add(credit.key);
    }
    return keys;
  }

  /// The normalized keys a track counts toward: its credited artists plus its
  /// album artist (which survives even when the credit string is untagged).
  static Set<String> keysForTrack(
    CreditedArtistSplitter splitter,
    String artist,
    String? albumArtist,
  ) {
    final keys = keysFor(splitter, artist);
    final trimmed = albumArtist?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      keys.add(normalizeArtistKey(trimmed));
    }
    return keys;
  }
}
