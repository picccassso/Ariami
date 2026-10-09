import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/api/connection_service.dart';
import '../../utils/image_decode.dart';
import '../common/cached_artwork.dart';

/// Playlist cover: custom image if present, otherwise a 1-4 album collage,
/// otherwise a gradient fallback. [decodeWidth] is the logical width used to
/// downscale the custom image; when null the available width is used.
class PlaylistArtwork extends StatelessWidget {
  final String playlistName;
  final String? customImagePath;
  final bool customImageExists;
  final List<String> albumIds;
  final bool isLikedSongs;
  final double iconSize;
  final double? decodeWidth;

  const PlaylistArtwork({
    super.key,
    required this.playlistName,
    required this.customImagePath,
    required this.customImageExists,
    required this.albumIds,
    required this.isLikedSongs,
    required this.iconSize,
    this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final path = customImagePath;
    if (path == null || !customImageExists) return _buildArtworkCollage();

    Widget image(BuildContext context, double width) => Image(
          image: resizedForDisplay(context, FileImage(File(path)), width),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildArtworkCollage(),
        );

    final fixedWidth = decodeWidth;
    if (fixedWidth != null) return image(context, fixedWidth);
    return LayoutBuilder(
      builder: (context, constraints) => image(context, constraints.maxWidth),
    );
  }

  Widget _buildArtworkCollage() {
    if (albumIds.isEmpty) return _buildFallbackArt();

    Widget tile(int i) => Expanded(
        child: AspectRatio(
            aspectRatio: 1, child: _buildArtworkImage(albumIds[i])));

    if (albumIds.length == 1) {
      return _buildArtworkImage(albumIds[0]);
    } else if (albumIds.length == 2 || albumIds.length == 3) {
      return Row(children: [tile(0), tile(1)]);
    } else {
      return Column(
        children: [
          Expanded(child: Row(children: [tile(0), tile(1)])),
          Expanded(child: Row(children: [tile(2), tile(3)])),
        ],
      );
    }
  }

  Widget _buildArtworkImage(String artworkId) {
    final request = _parseArtworkRequest(artworkId);

    Widget fallbackWidget = _buildFallbackArt();
    if (request.fallbackCacheKey != null && request.fallbackUrl != null) {
      fallbackWidget = CachedArtwork(
        albumId: request.fallbackCacheKey!,
        artworkUrl: request.fallbackUrl,
        fit: BoxFit.cover,
        fallback: _buildFallbackArt(),
        sizeHint: ArtworkSizeHint.thumbnail,
      );
    }

    return CachedArtwork(
      albumId: request.primaryCacheKey,
      artworkUrl: request.primaryUrl,
      fit: BoxFit.cover,
      fallback: fallbackWidget,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  _PlaylistArtworkRequest _parseArtworkRequest(String artworkId) {
    final apiClient = ConnectionService().apiClient;

    String? albumUrl(String albumId) =>
        apiClient != null ? '${apiClient.baseUrl}/artwork/$albumId' : null;
    String? songUrl(String songId) =>
        apiClient != null ? '${apiClient.baseUrl}/song-artwork/$songId' : null;

    if (artworkId.startsWith('a:')) {
      final splitIndex = artworkId.indexOf('|s:');
      final albumId = splitIndex == -1
          ? artworkId.substring(2)
          : artworkId.substring(2, splitIndex);
      final songId =
          splitIndex == -1 ? null : artworkId.substring(splitIndex + 3);

      return _PlaylistArtworkRequest(
        primaryCacheKey: albumId,
        primaryUrl: albumUrl(albumId),
        fallbackCacheKey:
            (songId == null || songId.isEmpty) ? null : 'song_$songId',
        fallbackUrl:
            (songId == null || songId.isEmpty) ? null : songUrl(songId),
      );
    }

    if (artworkId.startsWith('s:')) {
      final songId = artworkId.substring(2);
      return _PlaylistArtworkRequest(
        primaryCacheKey: 'song_$songId',
        primaryUrl: songUrl(songId),
      );
    }

    // Backward compatibility with legacy artwork IDs.
    if (artworkId.startsWith('song_')) {
      final songId = artworkId.substring(5);
      return _PlaylistArtworkRequest(
        primaryCacheKey: artworkId,
        primaryUrl: songUrl(songId),
      );
    }

    return _PlaylistArtworkRequest(
      primaryCacheKey: artworkId,
      primaryUrl: albumUrl(artworkId),
    );
  }

  Widget _buildFallbackArt() {
    if (isLikedSongs) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF444444), // Dark Grey
              Color(0xFF111111), // Black
            ],
          ),
        ),
        child:
            Icon(Icons.favorite_rounded, size: iconSize, color: Colors.white),
      );
    }

    final colorIndex = playlistName.hashCode % 5;
    const gradients = [
      [Color(0xFF222222), Color(0xFF000000)], // Deep Black
      [Color(0xFF333333), Color(0xFF111111)], // Dark Grey
      [Color(0xFF444444), Color(0xFF222222)], // Medium Grey
      [Color(0xFF555555), Color(0xFF333333)], // Lighter Grey
      [Color(0xFF151515), Color(0xFF050505)], // Almost Black
    ];

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients[colorIndex],
        ),
      ),
      child:
          Icon(Icons.queue_music_rounded, size: iconSize, color: Colors.white),
    );
  }
}

class _PlaylistArtworkRequest {
  const _PlaylistArtworkRequest({
    required this.primaryCacheKey,
    required this.primaryUrl,
    this.fallbackCacheKey,
    this.fallbackUrl,
  });

  final String primaryCacheKey;
  final String? primaryUrl;
  final String? fallbackCacheKey;
  final String? fallbackUrl;
}
