import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../common/cached_artwork.dart';

/// Playlist card widget
/// Displays playlist with premium styling and dynamic artwork
class PlaylistCard extends StatefulWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<String> albumIds;
  final bool isLikedSongs;
  final bool isImportedFromServer;
  final bool hasDownloadedSongs;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onLongPress,
    this.albumIds = const [],
    this.isLikedSongs = false,
    this.isImportedFromServer = false,
    this.hasDownloadedSongs = false,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool? _customImageExists;

  @override
  void initState() {
    super.initState();
    _checkCustomImage();
  }

  @override
  void didUpdateWidget(PlaylistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.customImagePath != widget.playlist.customImagePath) {
      _checkCustomImage();
    }
  }

  Future<void> _checkCustomImage() async {
    if (widget.playlist.customImagePath != null) {
      final exists = await File(widget.playlist.customImagePath!).exists();
      if (mounted) {
        setState(() {
          _customImageExists = exists;
        });
      }
    } else {
      if (mounted && _customImageExists != null) {
        setState(() {
          _customImageExists = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playlist Artwork
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _buildPlaylistArt(),
                  ),
                ),
                
                // Download indicator
                if (widget.hasDownloadedSongs)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green, // Functional green for downloads
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.download_done,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.isImportedFromServer) ...[
                        Icon(
                          Icons.cloud_done_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          widget.playlist.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.playlist.songCount} songs',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build playlist artwork - custom image, collage, or fallback
  Widget _buildPlaylistArt() {
    if (widget.playlist.customImagePath != null && _customImageExists == true) {
      return Image.file(
        File(widget.playlist.customImagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildArtworkCollage(),
      );
    }
    return _buildArtworkCollage();
  }

  /// Build album artwork collage
  Widget _buildArtworkCollage() {
    if (widget.albumIds.isEmpty) return _buildFallbackArt();

    if (widget.albumIds.length == 1) {
      return _buildArtworkImage(widget.albumIds[0]);
    } else if (widget.albumIds.length == 2 || widget.albumIds.length == 3) {
      return Row(
        children: [
          Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[0]))),
          Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[1]))),
        ],
      );
    } else {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[0]))),
                Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[1]))),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[2]))),
                Expanded(child: AspectRatio(aspectRatio: 1, child: _buildArtworkImage(widget.albumIds[3]))),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildArtworkImage(String artworkId) {
    final connectionService = ConnectionService();
    String? artworkUrl;
    if (artworkId.startsWith('song_')) {
      final songId = artworkId.substring(5);
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/$songId'
          : null;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/$artworkId'
          : null;
    }

    return CachedArtwork(
      albumId: artworkId,
      artworkUrl: artworkUrl,
      fit: BoxFit.cover,
      fallback: _buildFallbackArt(),
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  Widget _buildFallbackArt() {
    if (widget.isLikedSongs) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF444444), // Dark Grey
              Color(0xFF111111), // Black
            ],
          ),
        ),
        child: const Icon(Icons.favorite_rounded, size: 48, color: Colors.white),
      );
    }

    final colorIndex = widget.playlist.name.hashCode % 5;
    final gradients = [
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
      child: const Icon(Icons.queue_music_rounded, size: 48, color: Colors.white),
    );
  }
}

/// Create New Playlist Card
class CreatePlaylistCard extends StatelessWidget {
  final VoidCallback onTap;

  const CreatePlaylistCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              'Create Playlist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Import from Server Card
class ImportFromServerCard extends StatelessWidget {
  final int serverPlaylistCount;
  final VoidCallback onTap;

  const ImportFromServerCard({
    super.key,
    required this.serverPlaylistCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.secondary,
                    Theme.of(context).colorScheme.primary,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_download_rounded, size: 40, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$serverPlaylistCount',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import from Server',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$serverPlaylistCount new available',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
