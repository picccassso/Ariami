import 'package:ariami_core/services/library/library_artist_index.dart';

import '../../models/api_models.dart';

/// Mobile's artist lookups; the derivation lives in [CatalogArtistIndex].
///
/// Unlike the desktop Track, [SongModel] has no albumArtist field, so the
/// album artist is derived from the album catalog.
class LibraryArtistIndex
    extends CatalogArtistIndex<AlbumModel, SongModel, PlaylistModel> {
  const LibraryArtistIndex({
    required super.albumsByArtist,
    required super.tracksByArtistKey,
    required super.playlistsByArtistKey,
  });

  static const LibraryArtistIndex empty = LibraryArtistIndex(
    albumsByArtist: <String, List<AlbumModel>>{},
    tracksByArtistKey: <String, List<SongModel>>{},
    playlistsByArtistKey: <String, List<PlaylistModel>>{},
  );

  static const keysFor = CatalogArtistIndex.keysFor;

  factory LibraryArtistIndex.build({
    required List<AlbumModel> albums,
    required List<SongModel> songs,
    required List<PlaylistModel> playlists,
  }) {
    final index =
        CatalogArtistIndex.build<AlbumModel, SongModel, PlaylistModel>(
      albums: albums,
      songs: songs,
      playlists: playlists,
      albumId: (album) => album.id,
      albumTitle: (album) => album.title,
      albumArtist: (album) => album.artist,
      trackId: (track) => track.id,
      trackArtist: (track) => track.artist,
      trackAlbumId: (track) => track.albumId,
      trackAlbumArtist: (track, album) => album?.artist,
      playlistSongIds: (playlist) => playlist.songIds,
    );
    return LibraryArtistIndex(
      albumsByArtist: index.albumsByArtist,
      tracksByArtistKey: index.tracksByArtistKey,
      playlistsByArtistKey: index.playlistsByArtistKey,
    );
  }
}
