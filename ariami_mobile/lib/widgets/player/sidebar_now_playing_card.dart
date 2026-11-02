import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../utils/artwork_url.dart';
import '../../services/color_extraction_service.dart';
import '../../utils/constants.dart';
import '../common/adaptive_marquee_text.dart';
import '../common/cached_artwork.dart';
import 'progress_fill.dart';

/// Vertical now-playing card docked at the bottom of the navigation sidebar
/// on wide (tablet) layouts: artwork on top, song info, progress, and
/// controls below, on the same progress band as the mini player. The horizontal [MiniPlayer] bar stays the
/// phone treatment; squeezed into the sidebar it clipped its text and icons.
class SidebarNowPlayingCard extends StatelessWidget {
  final Song? currentSong;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final bool hasNext;
  final bool hasPrevious;

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
  });

  @override
  Widget build(BuildContext context) {
    final song = currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }
    // The bar wears the playing cover's colours whatever the app theme, so
    // it changes with every track.
    final coverColors = ColorExtractionService();

    return ListenableBuilder(
      listenable: coverColors,
      builder: (context, _) {
        final cover = coverColors.currentColors;
        final colors =
            PlayerColors.fromSeed(cover.primary, ambient: cover.ambientColors);
        return Container(
          decoration: BoxDecoration(
            color: colors.band,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: ProgressFill(fill: colors.fill)),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: _buildArtwork(context, song),
                        ),
                        const SizedBox(height: 10),
                        AdaptiveMarqueeText(
                          key: ValueKey('sidebar-title-${song.id}'),
                          text: song.title,
                          style:
                              AppTheme.heading(16, color: colors.textPrimary),
                          height: 20,
                          velocity: 20,
                        ),
                        const SizedBox(height: 2),
                        AdaptiveMarqueeText(
                          key: ValueKey('sidebar-artist-${song.id}'),
                          text: song.artist,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.textSecondary),
                          height: 16,
                          velocity: 20,
                        ),
                        Row(
                          // The sidebar already has a standing output-device
                          // entry above the card, so the card only carries the
                          // transport controls, centered.
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: colors.textPrimary,
                              disabledColor: colors.textSecondary,
                              onPressed: hasPrevious ? onSkipPrevious : null,
                              iconSize: 24,
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              color: colors.textPrimary,
                              onPressed: onPlayPause,
                              iconSize: 28,
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              color: colors.textPrimary,
                              disabledColor: colors.textSecondary,
                              onPressed: hasNext ? onSkipNext : null,
                              iconSize: 24,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtwork(BuildContext context, Song song) {
    final artwork = resolveSongArtwork(songId: song.id, albumId: song.albumId);

    return CachedArtwork(
      albumId: artwork.cacheId,
      artworkUrl: artwork.url,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      fallback: Container(
        color: context.colors.surfaceHigh,
        child: Icon(
          Icons.music_note,
          color: context.colors.textSecondary,
          size: 48,
        ),
      ),
    );
  }
}
