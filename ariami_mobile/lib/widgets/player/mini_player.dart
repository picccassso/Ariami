import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../utils/artwork_url.dart';
import '../../services/color_extraction_service.dart';
import '../../utils/constants.dart';
import '../../services/playback_manager.dart';
import '../common/adaptive_marquee_text.dart';
import '../common/cached_artwork.dart';
import 'player_output_button.dart';
import 'progress_fill.dart';

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
  final PlaybackManager playbackManager;

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
    required this.playbackManager,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  static const double _kHorizontalSwipeEdgeGuard = 24.0;
  static const double _kSkipSwipeMinDistance = 60.0;
  bool _isSkipTransitioning = false;
  double _skipOffsetX = 0.0;
  bool _horizontalSwipeArmed = false;
  double _horizontalSwipeDelta = 0.0;

  void _onHorizontalSwipeStart(DragStartDetails details) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final startX = details.globalPosition.dx;
    _horizontalSwipeArmed = startX >= _kHorizontalSwipeEdgeGuard &&
        startX <= screenWidth - _kHorizontalSwipeEdgeGuard;
    _horizontalSwipeDelta = 0.0;
  }

  void _onHorizontalSwipeUpdate(DragUpdateDetails details) {
    if (!_horizontalSwipeArmed) {
      return;
    }
    _horizontalSwipeDelta += details.delta.dx;
  }

  void _onHorizontalSwipeCancel() {
    _horizontalSwipeArmed = false;
    _horizontalSwipeDelta = 0.0;
  }

  void _onHorizontalSwipeEnd(DragEndDetails details) {
    if (!_horizontalSwipeArmed) {
      _onHorizontalSwipeCancel();
      return;
    }

    final distance = _horizontalSwipeDelta.abs();
    if (distance < _kSkipSwipeMinDistance) {
      _onHorizontalSwipeCancel();
      return;
    }

    if (_horizontalSwipeDelta < 0) {
      if (widget.hasNext) {
        _animateSkipTransition(toNext: true);
      }
    } else if (_horizontalSwipeDelta > 0) {
      if (widget.hasPrevious) {
        _animateSkipTransition(toNext: false);
      }
    }

    _onHorizontalSwipeCancel();
  }

  Future<void> _animateSkipTransition({required bool toNext}) async {
    if (_isSkipTransitioning) {
      return;
    }

    setState(() {
      _isSkipTransitioning = true;
      _skipOffsetX = toNext ? -0.08 : 0.08;
    });

    if (toNext) {
      widget.onSkipNext();
    } else {
      widget.onSkipPrevious();
    }

    // Fallback reset in case playback update is delayed.
    await Future.delayed(const Duration(milliseconds: 340));
    if (!mounted || !_isSkipTransitioning) {
      return;
    }

    setState(() {
      _skipOffsetX = 0.0;
      _isSkipTransitioning = false;
    });
  }

  @override
  void didUpdateWidget(covariant MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentSong?.id != widget.currentSong?.id &&
        _isSkipTransitioning) {
      setState(() {
        _skipOffsetX = 0.0;
        _isSkipTransitioning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.currentSong == null) {
      return const SizedBox.shrink();
    }

    // The bar wears the playing cover's colours whatever the app theme, so
    // it changes with every track.
    final coverColors = ColorExtractionService();
    final song = widget.currentSong!;

    // The bar is the progress bar, as on Premium Desktop: a flat band whose
    // sleeve-tone fill sweeps across it as the song plays. Seeking stays in
    // the full player; horizontal swipes here skip.
    return ListenableBuilder(
      listenable: coverColors,
      builder: (context, _) {
        final cover = coverColors.currentColors;
        final colors =
            PlayerColors.fromSeed(cover.primary, ambient: cover.ambientColors);
        return Container(
          height: 64, // Keep exact height for layout & scroll padding tests
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
                  onTap: widget.onTap,
                  child: AnimatedSlide(
                    offset: Offset(_skipOffsetX, 0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: AnimatedOpacity(
                      opacity: _isSkipTransitioning ? 0.94 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragStart: _onHorizontalSwipeStart,
                                onHorizontalDragUpdate:
                                    _onHorizontalSwipeUpdate,
                                onHorizontalDragEnd: _onHorizontalSwipeEnd,
                                onHorizontalDragCancel:
                                    _onHorizontalSwipeCancel,
                                child: Row(
                                  children: [
                                    _buildAlbumArt(context),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AdaptiveMarqueeText(
                                            key: ValueKey(
                                              'title-${song.id}-${song.title}',
                                            ),
                                            text: song.title,
                                            style: AppTheme.heading(16,
                                                color: colors.textPrimary),
                                            height: 20,
                                            velocity: 20,
                                          ),
                                          AdaptiveMarqueeText(
                                            key: ValueKey(
                                              'artist-${song.id}-${song.artist}',
                                            ),
                                            text: song.artist,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color:
                                                        colors.textSecondary),
                                            height: 16,
                                            velocity: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            PlayerOutputButton(
                              playbackManager: widget.playbackManager,
                              showDeviceName: false,
                              connectedColor: colors.textPrimary,
                              disconnectedColor: colors.textSecondary,
                              iconSize: 22,
                            ),
                            IconButton(
                              icon: Icon(widget.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              color: colors.textPrimary,
                              onPressed: widget.onPlayPause,
                              iconSize: 28,
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildAlbumArt(BuildContext context) {
    final song = widget.currentSong;
    if (song == null) {
      return _buildPlaceholder(context);
    }

    final artwork = resolveSongArtwork(songId: song.id, albumId: song.albumId);

    return CachedArtwork(
      albumId: artwork.cacheId,
      artworkUrl: artwork.url,
      width: 44,
      height: 44,
      borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      ),
      child: Icon(
        Icons.music_note,
        color: context.colors.textSecondary,
        size: 24,
      ),
    );
  }
}
