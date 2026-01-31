import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/color_extraction_service.dart';
import '../common/cached_artwork.dart';

/// Mini player widget that appears at the bottom during playback
class MiniPlayer extends StatefulWidget {
  final Song? currentSong;
  final bool isPlaying;
  final bool isVisible;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final bool hasNext;
  final bool hasPrevious;
  final Duration position;
  final Duration duration;

  const MiniPlayer({
    super.key,
    required this.currentSong,
    required this.isPlaying,
    required this.isVisible,
    required this.onTap,
    required this.onPlayPause,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.hasNext,
    required this.hasPrevious,
    required this.position,
    required this.duration,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final ColorExtractionService _colorService = ColorExtractionService();

  @override
  void initState() {
    super.initState();
    _colorService.addListener(_onColorsChanged);
  }

  @override
  void dispose() {
    _colorService.removeListener(_onColorsChanged);
    super.dispose();
  }

  void _onColorsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.currentSong == null) {
      return const SizedBox.shrink();
    }

    final colors = _colorService.currentColors;
    
    // Floating style with margins
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        height: 72, // Taller for better touch targets
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), // More rounded
          color: Theme.of(context).colorScheme.surfaceContainerHighest, // Fallback
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withOpacity(0.9),
              colors.secondary.withOpacity(0.95), // Less transparent for visibility
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(
                children: [
                  // Content Row
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Row(
                        children: [
                          // Album artwork with rotation or shadow? Keep simple for mini.
                          _buildAlbumArt(context),
            
                          const SizedBox(width: 12),
            
                          // Song info
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.currentSong!.title,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white, // Always white on gradient
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  widget.currentSong!.artist,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
            
                          // Controls
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded),
                                color: Colors.white,
                                onPressed: widget.hasPrevious ? widget.onSkipPrevious : null,
                                disabledColor: Colors.white24,
                              ),
                              
                              // Play/Pause with Circle
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                  color: Colors.white,
                                  onPressed: widget.onPlayPause,
                                  iconSize: 28,
                                ),
                              ),
                              
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded),
                                color: Colors.white,
                                onPressed: widget.hasNext ? widget.onSkipNext : null,
                                disabledColor: Colors.white24,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Progress Indicator at bottom edge
                  LinearProgressIndicator(
                    value: widget.duration.inMilliseconds > 0
                        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
                        : 0.0,
                    minHeight: 3,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white, // Clean white progress
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build album artwork widget using CachedArtwork
  Widget _buildAlbumArt(BuildContext context) {
    final connectionService = ConnectionService();

    if (widget.currentSong == null) {
      return _buildPlaceholder(context);
    }

    // Determine artwork URL based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (widget.currentSong!.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${widget.currentSong!.albumId}'
          : null;
      cacheId = widget.currentSong!.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${widget.currentSong!.id}'
          : null;
      cacheId = 'song_${widget.currentSong!.id}';
    }

    return CachedArtwork(
      albumId: cacheId,
      artworkUrl: artworkUrl,
      width: 45,
      height: 45,
      borderRadius: BorderRadius.circular(4),
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  /// Build placeholder artwork
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: Theme.of(context).colorScheme.primary,
        size: 24,
      ),
    );
  }
}
