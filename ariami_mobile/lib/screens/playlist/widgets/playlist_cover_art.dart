import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/api_models.dart';
import '../../../services/cache/cache_manager.dart';
import '../../../services/playlist_service.dart';

/// Small square playlist cover: custom image when set, otherwise a collage of
/// the first member songs' artwork, otherwise a colored placeholder. The
/// Liked Songs playlist always shows its heart tile.
///
/// Artwork is read from the in-memory artwork cache that the library views
/// have already loaded; uncovered songs fall back to a colored tile.
class PlaylistCoverArt extends StatelessWidget {
  final PlaylistModel playlist;

  /// Explicit artwork cache ids; used when the playlist's songs are known but
  /// the model does not carry a songAlbumIds map (e.g. server playlists).
  final List<String>? artworkIds;
  final double size;
  final BorderRadius borderRadius;

  const PlaylistCoverArt({
    super.key,
    required this.playlist,
    this.artworkIds,
    this.size = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  /// First unique artwork cache ids for songs: album songs use their albumId,
  /// standalone songs the "song_"-prefixed cache id.
  static List<String> artworkIdsForSongs(List<SongModel> songs) {
    final ids = <String>{};
    for (final song in songs) {
      final albumId = song.albumId;
      ids.add(albumId == null || albumId.isEmpty ? 'song_${song.id}' : albumId);
      if (ids.length >= 4) break;
    }
    return ids.toList();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: _cover(),
      ),
    );
  }

  Widget _cover() {
    if (playlist.id == PlaylistService.likedSongsId) return _likedSongsTile();

    final path = playlist.customImagePath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _collage(),
      );
    }
    return _collage();
  }

  Widget _likedSongsTile() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.pink[400]!, Colors.red[700]!],
        ),
      ),
      child: const Icon(
        Icons.favorite,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _collage() {
    final artworkIds = _artworkIds();
    if (artworkIds.isEmpty) return _fallbackTile();
    if (artworkIds.length == 1) return _tile(artworkIds[0]);
    if (artworkIds.length == 2 || artworkIds.length == 3) {
      return Row(
        children: [
          Expanded(
              child:
                  AspectRatio(aspectRatio: 1, child: _tile(artworkIds[0]))),
          Expanded(
              child:
                  AspectRatio(aspectRatio: 1, child: _tile(artworkIds[1]))),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                  child: AspectRatio(
                      aspectRatio: 1, child: _tile(artworkIds[0]))),
              Expanded(
                  child: AspectRatio(
                      aspectRatio: 1, child: _tile(artworkIds[1]))),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                  child: AspectRatio(
                      aspectRatio: 1, child: _tile(artworkIds[2]))),
              Expanded(
                  child: AspectRatio(
                      aspectRatio: 1, child: _tile(artworkIds[3]))),
            ],
          ),
        ),
      ],
    );
  }

  /// First unique artwork cache ids for the playlist's songs.
  List<String> _artworkIds() {
    final explicit = artworkIds;
    if (explicit != null) return explicit.take(4).toList();
    final ids = <String>{};
    for (final songId in playlist.songIds) {
      final albumId = playlist.songAlbumIds[songId];
      ids.add(albumId == null || albumId.isEmpty ? 'song_$songId' : albumId);
      if (ids.length >= 4) break;
    }
    return ids.toList();
  }

  Widget _tile(String artworkId) {
    final cacheManager = CacheManager();
    final path = cacheManager.getArtworkPathSync('${artworkId}_thumb') ??
        cacheManager.getArtworkPathSync(artworkId);
    if (path == null) return _fallbackTile();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallbackTile(),
    );
  }

  Widget _fallbackTile() {
    return Container(
      color: _fallbackColor(),
      child: const Icon(
        Icons.queue_music,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Color _fallbackColor() {
    const colors = [
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.pink,
    ];
    return colors[playlist.name.hashCode.abs() % colors.length][400]!;
  }
}
