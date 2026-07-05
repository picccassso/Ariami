import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/color_extraction_service.dart';
import '../../utils/constants.dart';
import '../../services/playback_manager.dart';
import '../common/adaptive_marquee_text.dart';
import '../common/cached_artwork.dart';
import 'player_output_button.dart';

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
    required this.position,
    required this.duration,
    required this.playbackManager,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  static const double _kHorizontalSwipeEdgeGuard = 24.0;
  static const double _kSkipSwipeMinDistance = 60.0;
  final ColorExtractionService _colorService = ColorExtractionService();
  bool _isSkipTransitioning = false;
  double _skipOffsetX = 0.0;
  bool _horizontalSwipeArmed = false;
  double _horizontalSwipeDelta = 0.0;

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
      // Swipe left -> Next
      if (widget.hasNext) {
        _animateSkipTransition(toNext: true);
      }
    } else if (_horizontalSwipeDelta > 0) {
      // Swipe right -> Previous
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

    final colors = _colorService.currentColors;

    // Flush style
    return Theme(
      data: AppTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: colors.primary,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        height: 64, // Slightly shorter for flush look
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          color:
              Theme.of(context).colorScheme.surfaceContainerHighest, // Fallback
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withValues(alpha: 0.9),
              colors.secondary
                  .withValues(alpha: 0.95), // Less transparent for visibility
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
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: Column(
                children: [
                  // Content Row
                  Expanded(
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
                                  onHorizontalDragStart:
                                      _onHorizontalSwipeStart,
                                  onHorizontalDragUpdate:
                                      _onHorizontalSwipeUpdate,
                                  onHorizontalDragEnd: _onHorizontalSwipeEnd,
                                  onHorizontalDragCancel:
                                      _onHorizontalSwipeCancel,
                                  child: Row(
                                    children: [
                                      // Album artwork with rotation or shadow? Keep simple for mini.
                                      _buildAlbumArt(context),

                                      const SizedBox(width: 12),

                                      // Song info
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            AdaptiveMarqueeText(
                                              key: ValueKey(
                                                'title-${widget.currentSong!.id}-${widget.currentSong!.title}',
                                              ),
                                              text: widget.currentSong!.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                              height: 20,
                                              velocity: 20,
                                            ),
                                            AdaptiveMarqueeText(
                                              key: ValueKey(
                                                'artist-${widget.currentSong!.id}-${widget.currentSong!.artist}',
                                              ),
                                              text: widget.currentSong!.artist,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.8),
                                                  ),
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

                              // Controls
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PlayerOutputButton(
                                    playbackManager: widget.playbackManager,
                                    showDeviceName: false,
                                    connectedColor: Colors.white,
                                    disconnectedColor:
                                        Colors.white.withValues(alpha: 0.54),
                                    iconSize: 22,
                                  ),
                                  // Play/Pause
                                  IconButton(
                                    icon: Icon(widget.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                                    color: Colors.white,
                                    onPressed: widget.onPlayPause,
                                    iconSize: 28,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Progress Indicator at bottom edge
                  LinearProgressIndicator(
                    value: widget.duration.inMilliseconds > 0
                        ? widget.position.inMilliseconds /
                            widget.duration.inMilliseconds
                        : 0.0,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
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
