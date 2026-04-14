import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/cast/chrome_cast_service.dart';
import '../../services/color_extraction_service.dart';
import '../../utils/constants.dart';
import '../../services/playback_manager.dart';
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
  final ColorExtractionService _colorService = ColorExtractionService();
  final ChromeCastService _castService = ChromeCastService();

  @override
  void initState() {
    super.initState();
    _colorService.addListener(_onColorsChanged);
    _castService.addListener(_onColorsChanged);
  }

  @override
  void dispose() {
    _colorService.removeListener(_onColorsChanged);
    _castService.removeListener(_onColorsChanged);
    super.dispose();
  }

  void _onColorsChanged() {
    setState(() {});
  }

  Future<void> _onCastPressed() async {
    if (_castService.isConnected) {
      await _showConnectedActions();
    } else {
      await _showDevicePicker();
    }
  }

  Future<void> _showDevicePicker() async {
    await _castService.startDiscovery();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: AnimatedBuilder(
            animation: _castService,
            builder: (context, _) {
              final devices = _castService.devices;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text('Cast To Device', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Searching for Chromecast devices...')),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return ListTile(
                            leading: const Icon(LucideIcons.speaker),
                            title: Text(device.friendlyName),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await _connectAndSync(device);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );

    await _castService.stopDiscovery();
  }

  Future<void> _connectAndSync(GoogleCastDevice device) async {
    try {
      await widget.playbackManager.startCastingToDevice(device);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect Chromecast: $e')),
      );
    }
  }

  Future<void> _showConnectedActions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.cast),
                title: Text(_castService.connectedDeviceName ?? 'Chromecast connected'),
                subtitle: const Text('Audio is being cast from Ariami'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.cast),
                title: const Text('Disconnect'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await widget.playbackManager.stopCastingAndResumeLocal();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onHorizontalSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null) return;

    const threshold = 300.0;

    if (velocity < -threshold) {
      // Swipe left -> Next
      if (widget.hasNext) {
        widget.onSkipNext();
      }
    } else if (velocity > threshold) {
      // Swipe right -> Previous
      if (widget.hasPrevious) {
        widget.onSkipPrevious();
      }
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragEnd: _onHorizontalSwipeEnd,
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
                              ],
                            ),
                          ),
                        ),
          
                        // Controls
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Cast button (only on supported platforms)
                            if (_castService.isSupportedPlatform)
                              IconButton(
                                icon: Icon(
                                  _castService.isConnected
                                      ? Icons.cast_connected_rounded
                                      : LucideIcons.cast,
                                  color: _castService.isConnected
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                                iconSize: 22,
                                onPressed: (_castService.isConnecting ||
                                        widget.playbackManager.isCastTransitionInProgress)
                                    ? null
                                    : _onCastPressed,
                                tooltip: _castService.isConnected
                                    ? 'Disconnect Chromecast'
                                    : 'Connect Chromecast',
                              ),
                            // Play/Pause
                            IconButton(
                              icon: Icon(widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
                
                // Progress Indicator at bottom edge
                LinearProgressIndicator(
                  value: widget.duration.inMilliseconds > 0
                      ? widget.position.inMilliseconds / widget.duration.inMilliseconds
                      : 0.0,
                  minHeight: 2.5,
                  backgroundColor: Colors.white.withOpacity(0.25),
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

