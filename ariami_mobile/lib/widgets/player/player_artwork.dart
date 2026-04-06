import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/playback_queue.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/cast/chrome_cast_service.dart';
import '../common/cached_artwork.dart';

/// Large album artwork with swipe gestures for track skipping and cast volume.
class PlayerArtwork extends StatefulWidget {
  final PlaybackQueue queue;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const PlayerArtwork({
    super.key,
    required this.queue,
    required this.currentIndex,
    required this.onPageChanged,
  });

  @override
  State<PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<PlayerArtwork> {
  final ChromeCastService _castService = ChromeCastService();
  late PageController _pageController;

  Timer? _hintTimer;
  Timer? _hudTimer;
  bool _wasConnected = false;
  bool _showCastHint = false;
  bool _showVolumeHud = false;
  double _volumeHudValue = 0.0;
  
  late int _visualIndex;

  @override
  void initState() {
    super.initState();
    _visualIndex = widget.currentIndex;
    _pageController = PageController(
      initialPage: widget.currentIndex,
      viewportFraction: 0.9,
    );
    _castService.initialize();
    _wasConnected = _castService.isConnected;
    _castService.addListener(_handleCastStateChanged);
  }

  @override
  void didUpdateWidget(covariant PlayerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queue != oldWidget.queue) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(widget.currentIndex);
      }
      _visualIndex = widget.currentIndex;
    } else if (widget.currentIndex != oldWidget.currentIndex) {
      if (widget.currentIndex != _visualIndex) {
        if (_pageController.hasClients && _pageController.page?.round() != widget.currentIndex) {
          _pageController.animateToPage(
            widget.currentIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
      _visualIndex = widget.currentIndex;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _hintTimer?.cancel();
    _hudTimer?.cancel();
    _castService.removeListener(_handleCastStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart:
          _castService.isConnected ? _handleVolumeDragStart : null,
      onVerticalDragUpdate:
          _castService.isConnected ? _handleVolumeDragUpdate : null,
      onVerticalDragEnd: _castService.isConnected ? _handleVolumeDragEnd : null,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification) {
            if (_visualIndex != widget.currentIndex) {
              widget.onPageChanged(_visualIndex);
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            _visualIndex = index;
          },
          itemCount: widget.queue.length,
          itemBuilder: (context, index) {
            final song = widget.queue.songs[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: _buildArtworkContainer(context, song, index),
            );
          },
        ),
      ),
    );
  }

  Widget _buildArtworkContainer(BuildContext context, Song song, int index) {
    final isCurrent = index == widget.currentIndex;
    Widget child = Container(
      constraints: const BoxConstraints(
        maxWidth: 350,
        maxHeight: 350,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildArtwork(context, song),
              if (isCurrent)
                IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildOverlay(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Center(
      child: Hero(
        tag: isCurrent ? 'album_art_${song.id}' : 'album_art_${song.id}_$index',
        child: child,
      ),
    );
  }

  void _handleCastStateChanged() {
    final isConnected = _castService.isConnected;

    if (isConnected && !_wasConnected) {
      _showHint();
    } else if (!isConnected) {
      _hintTimer?.cancel();
      _hudTimer?.cancel();
      if (mounted && (_showCastHint || _showVolumeHud)) {
        setState(() {
          _showCastHint = false;
          _showVolumeHud = false;
        });
      }
    }

    _wasConnected = isConnected;
  }

  void _showHint() {
    _hintTimer?.cancel();
    _hudTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _showCastHint = true;
      _showVolumeHud = false;
    });

    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showCastHint = false;
      });
    });
  }

  void _handleVolumeDragStart(DragStartDetails details) {
    _hintTimer?.cancel();
    _hudTimer?.cancel();
    final startingVolume =
        _showVolumeHud ? _volumeHudValue : _castService.deviceVolume;

    setState(() {
      _showCastHint = false;
      _showVolumeHud = true;
      _volumeHudValue = startingVolume;
    });
  }

  void _handleVolumeDragUpdate(DragUpdateDetails details) {
    final nextVolume =
        (_volumeHudValue - (details.delta.dy / 280)).clamp(0.0, 1.0);

    setState(() {
      _volumeHudValue = nextVolume.toDouble();
    });

    _castService.setDeviceVolume(_volumeHudValue);
  }

  void _handleVolumeDragEnd(DragEndDetails details) {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showVolumeHud = false;
      });
    });
  }

  Widget? _buildOverlay(BuildContext context) {
    if (_showVolumeHud) {
      final volumePercent = (_volumeHudValue * 100).round();
      return Align(
        key: const ValueKey('cast-volume-hud'),
        alignment: Alignment.center,
        child: _buildOverlayPill(
          context,
          icon: _volumeHudValue == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          text: 'Cast volume $volumePercent%',
        ),
      );
    }

    if (_showCastHint) {
      return Align(
        key: const ValueKey('cast-volume-hint'),
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: _buildOverlayPill(
            context,
            icon: Icons.swipe_vertical_rounded,
            text: 'Slide up and down the cover art to control volume',
          ),
        ),
      );
    }

    return null;
  }

  Widget _buildOverlayPill(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.96),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build artwork image or placeholder using CachedArtwork.
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

    return AspectRatio(
      aspectRatio: 1.0,
      child: CachedArtwork(
        albumId: cacheId,
        artworkUrl: artworkUrl,
        fit: BoxFit.cover,
        width: 350,
        height: 350,
        fallback: _buildPlaceholder(context),
        fallbackIcon: Icons.music_note,
        fallbackIconSize: 120,
      ),
    );
  }

  /// Build placeholder artwork.
  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 350,
      height: 350,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 120,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
