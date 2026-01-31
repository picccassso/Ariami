import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../common/cached_artwork.dart';

/// Playlist list item widget
/// Displays playlist artwork, title, and song count in a list layout
class PlaylistListItem extends StatefulWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<String> albumIds;
  final bool isLikedSongs;
  final bool isImportedFromServer;
  final bool hasDownloadedSongs;

  const PlaylistListItem({
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
  State<PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends State<PlaylistListItem> {
  bool? _customImageExists;

  @override
  void initState() {
    super.initState();
    _checkCustomImage();
  }

  @override
  void didUpdateWidget(PlaylistListItem oldWidget) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Playlist Artwork
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildPlaylistArt(),
                    ),
                    
                    // Download Indicator
                    if (widget.hasDownloadedSongs)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                          ),
                          child: const Icon(
                            Icons.download_done,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Text Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                              fontSize: 16,
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
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
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
        child: const Icon(Icons.favorite_rounded, size: 24, color: Colors.white),
      );
    }

    final colorIndex = widget.playlist.name.hashCode % 5;
    final gradients = [
      [const Color(0xFF222222), const Color(0xFF000000)], // Deep Black
      [const Color(0xFF333333), const Color(0xFF111111)], // Dark Grey
      [const Color(0xFF444444), const Color(0xFF222222)], // Medium Grey
      [const Color(0xFF555555), const Color(0xFF333333)], // Lighter Grey
      [const Color(0xFF151515), const Color(0xFF050505)], // Almost Black
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
      child: const Icon(Icons.queue_music_rounded, size: 24, color: Colors.white),
    );
  }
}
