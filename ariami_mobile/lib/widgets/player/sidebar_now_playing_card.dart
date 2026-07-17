import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/color_extraction_service.dart';
import '../../utils/constants.dart';
import '../common/adaptive_marquee_text.dart';
import '../common/cached_artwork.dart';

/// Vertical now-playing card docked at the bottom of the navigation sidebar
/// on wide (tablet) layouts: artwork on top, song info, progress, and
/// controls below — Spotify-style. The horizontal [MiniPlayer] bar stays the
/// phone treatment; squeezed into the sidebar it clipped its text and icons.
class SidebarNowPlayingCard extends StatefulWidget {
  final Song? currentSong;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final bool hasNext;
  final bool hasPrevious;
  final Duration position;
  final Duration duration;

  const SidebarNowPlayingCard({
    super.key,
    required this.currentSong,
    required this.isPlaying,
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
  State<SidebarNowPlayingCard> createState() => _SidebarNowPlayingCardState();
}

class _SidebarNowPlayingCardState extends State<SidebarNowPlayingCard> {
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
    final song = widget.currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }

    final colors = _colorService.currentColors;

    return Theme(
      data: AppTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: colors.primary,
      ),
      child: Builder(
        builder: (themedContext) => Container(
          margin: const EdgeInsets.all(8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(themedContext).colorScheme.surfaceContainerHighest,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary.withValues(alpha: 0.9),
                colors.secondary.withValues(alpha: 0.95),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: _buildArtwork(themedContext, song),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdaptiveMarqueeText(
                          key: ValueKey('sidebar-title-${song.id}'),
                          text: song.title,
                          style: Theme.of(themedContext)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                          height: 20,
                          velocity: 20,
                        ),
                        const SizedBox(height: 2),
                        AdaptiveMarqueeText(
                          key: ValueKey('sidebar-artist-${song.id}'),
                          text: song.artist,
                          style: Theme.of(themedContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                          height: 16,
                          velocity: 20,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      // The sidebar already has a standing output-device
                      // entry above the card, so the card only carries the
                      // transport controls, centered.
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white.withValues(alpha: 0.3),
                          onPressed:
                              widget.hasPrevious ? widget.onSkipPrevious : null,
                          iconSize: 24,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: Icon(
                            widget.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          color: Colors.white,
                          onPressed: widget.onPlayPause,
                          iconSize: 28,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white.withValues(alpha: 0.3),
                          onPressed: widget.hasNext ? widget.onSkipNext : null,
                          iconSize: 24,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    value: widget.duration.inMilliseconds > 0
                        ? widget.position.inMilliseconds /
                            widget.duration.inMilliseconds
                        : 0.0,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context, Song song) {
    final connectionService = ConnectionService();

    String? artworkUrl;
    String cacheId;
    if (song.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    return CachedArtwork(
      albumId: cacheId,
      artworkUrl: artworkUrl,
      fit: BoxFit.cover,
      fallback: Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Icon(
          Icons.music_note,
          color: Theme.of(context).colorScheme.primary,
          size: 48,
        ),
      ),
    );
  }
}
