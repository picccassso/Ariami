import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/cast/chrome_cast_service.dart';
import '../common/cached_artwork.dart';

/// Large album artwork with swipe gestures for track skipping and cast volume.
class PlayerArtwork extends StatefulWidget {
  final Song song;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const PlayerArtwork({
    super.key,
    required this.song,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  State<PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<PlayerArtwork> {
  final ChromeCastService _castService = ChromeCastService();

  Timer? _hintTimer;
  Timer? _hudTimer;
  bool _wasConnected = false;
  bool _showCastHint = false;
  bool _showVolumeHud = false;
  double _volumeHudValue = 0.0;

  @override
  void initState() {
    super.initState();
    _castService.initialize();
    _wasConnected = _castService.isConnected;
    _castService.addListener(_handleCastStateChanged);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _hudTimer?.cancel();
    _castService.removeListener(_handleCastStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onVerticalDragStart:
          _castService.isConnected ? _handleVolumeDragStart : null,
      onVerticalDragUpdate:
          _castService.isConnected ? _handleVolumeDragUpdate : null,
      onVerticalDragEnd: _castService.isConnected ? _handleVolumeDragEnd : null,
      child: Center(
        child: Hero(
          tag: 'album_art_${widget.song.id}',
          child: Container(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildArtwork(context),
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
        ),
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

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null) {
      return;
    }

    if (velocity > 0) {
      widget.onSwipeRight();
    } else if (velocity < 0) {
      widget.onSwipeLeft();
    }
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
  Widget _buildArtwork(BuildContext context) {
    final connectionService = ConnectionService();

    String? artworkUrl;
    String cacheId;

    if (widget.song.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${widget.song.albumId}'
          : null;
      cacheId = widget.song.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${widget.song.id}'
          : null;
      cacheId = 'song_${widget.song.id}';
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
