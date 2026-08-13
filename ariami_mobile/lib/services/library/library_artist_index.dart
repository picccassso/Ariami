import 'package:ariami_core/services/stats/credited_artist_splitter.dart';

import '../../models/api_models.dart';

/// Artist lookups derived from the in-memory catalog.
///
/// Artists are plain display strings (there is no artist entity anywhere in
/// the catalog), so lookups group by normalized name. Albums, songs and
/// playlists are each indexed under every credited artist key (plus the
/// normalized full string), so a song credited "A, B" belongs to both A and B
/// and an album tagged "A & B" appears under both artists' pages — the same
/// derivation the listening-stats layer uses. Normalization also absorbs the
/// tag differences real libraries carry: case, trailing/duplicate whitespace,
/// invisible characters and unicode dash variants.
class LibraryArtistIndex {
  const LibraryArtistIndex({
    required this.albumsByArtist,
    required this.tracksByArtistKey,
    required this.playlistsByArtistKey,
  });

  /// Normalized credited-artist key -> their albums, title-sorted.
  final Map<String, List<AlbumModel>> albumsByArtist;

  /// Normalized credited-artist key -> songs credited to them, library order.
  final Map<String, List<SongModel>> tracksByArtistKey;

  /// Normalized credited-artist key -> playlists containing their songs,
  /// library order.
  final Map<String, List<PlaylistModel>> playlistsByArtistKey;

  static const LibraryArtistIndex empty = LibraryArtistIndex(
    albumsByArtist: <String, List<AlbumModel>>{},
    tracksByArtistKey: <String, List<SongModel>>{},
    playlistsByArtistKey: <String, List<PlaylistModel>>{},
  );

  /// Builds the index once per catalog shape. Callers memoize on the identity
  /// of the source lists (see LibraryController._artistIndex).
  factory LibraryArtistIndex.build({
    required List<AlbumModel> albums,
    required List<SongModel> songs,
    required List<PlaylistModel> playlists,
  }) {
    final splitter = CreditedArtistSplitter();

    final albumsByArtist = <String, List<AlbumModel>>{};
    for (final album in albums) {
      for (final key in keysFor(splitter, album.artist)) {
        albumsByArtist.putIfAbsent(key, () => <AlbumModel>[]).add(album);
      }
    }
    for (final entry in albumsByArtist.values) {
      entry.sort((a, b) => a.title.compareTo(b.title));
    }

    final albumsById = {for (final album in albums) album.id: album};

    final tracksByArtistKey = <String, List<SongModel>>{};
    final keysBySongId = <String, Set<String>>{};
    for (final track in songs) {
      final keys = keysForTrack(track, splitter, albumsById: albumsById);
      keysBySongId[track.id] = keys;
      for (final key in keys) {
        tracksByArtistKey.putIfAbsent(key, () => <SongModel>[]).add(track);
      }
    }

    final playlistsByArtistKey = <String, List<PlaylistModel>>{};
    for (final playlist in playlists) {
      final keys = <String>{};
      for (final songId in playlist.songIds) {
        keys.addAll(keysBySongId[songId] ?? const <String>{});
      }
      for (final key in keys) {
        playlistsByArtistKey
            .putIfAbsent(key, () => <PlaylistModel>[])
            .add(playlist);
      }
    }

    return LibraryArtistIndex(
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
  ///
  /// Unlike the desktop Track, [SongModel] has no albumArtist field, so the
  /// album artist is derived from the album catalog via [albumsById].
  static Set<String> keysForTrack(
    SongModel track,
    CreditedArtistSplitter splitter, {
    required Map<String, AlbumModel> albumsById,
  }) {
    final keys = keysFor(splitter, track.artist);
    final album = track.albumId == null ? null : albumsById[track.albumId!];
    final albumArtist = album?.artist.trim();
    if (albumArtist != null && albumArtist.isNotEmpty) {
      keys.add(normalizeArtistKey(albumArtist));
    }
    return keys;
  }
}
