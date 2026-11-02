import 'package:flutter/material.dart';
import '../../services/api/connection_service.dart';
import '../common/cached_artwork.dart';
import '../common/sleeve_header.dart';
import '../../utils/image_decode.dart';

class AlbumArtworkHeader extends StatelessWidget {
  final String? coverArt;
  final String albumTitle;
  final String? albumId;

  const AlbumArtworkHeader({
    super.key,
    this.coverArt,
    required this.albumTitle,
    this.albumId,
  });

  @override
  Widget build(BuildContext context) => SleeveHeader(cover: _buildArtwork());

  Widget _buildArtwork({BoxFit fit = BoxFit.cover}) {
    final connectionService = ConnectionService();
    final authHeaders = connectionService.authHeaders;
    final resolvedCoverArt = connectionService.resolveServerUrl(coverArt);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : null;

        // If we have an albumId, use CachedArtwork for automatic caching
        // CachedArtwork checks cache first, so it works even without a URL (offline mode)
        if (albumId != null) {
          return CachedArtwork(
            albumId: albumId!,
            artworkUrl: resolvedCoverArt,
            fit: fit,
            width: w,
            height: h,
            fallback: _buildFallbackArt(),
          );
        }

        if (resolvedCoverArt != null && resolvedCoverArt.isNotEmpty) {
          return Image(
            image: resizedForDisplay(
              context,
              NetworkImage(resolvedCoverArt, headers: authHeaders),
              w ?? h,
            ),
            width: w,
            height: h,
            fit: fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackArt();
            },
          );
        }

        return _buildFallbackArt();
      },
    );
  }

  Widget _buildFallbackArt() {
    final colorIndex = albumTitle.hashCode % 5;
    final colors = [
      Colors.grey[900]!,
      Colors.grey[800]!,
      Colors.grey[700]!,
      Colors.grey[600]!,
      Colors.grey[850]!,
    ];

    return Container(
      color: colors[colorIndex],
      child: const Center(
        child: Icon(
          Icons.album,
          size: 64,
          color: Colors.white,
        ),
      ),
    );
  }
}
