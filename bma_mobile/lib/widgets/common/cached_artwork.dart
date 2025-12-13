import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/cache/cache_manager.dart';
import '../../services/offline/offline_playback_service.dart';

/// A widget that displays album artwork with automatic caching
/// 
/// This is a drop-in replacement for Image.network that:
/// 1. Checks if artwork is already cached locally
/// 2. If cached, loads from disk
/// 3. If not cached, loads from network and caches for future use
/// 4. Shows fallback when offline and not cached
class CachedArtwork extends StatefulWidget {
  /// The album ID used for caching
  final String albumId;

  /// The network URL to fetch artwork from
  final String? artworkUrl;

  /// Width of the image
  final double? width;

  /// Height of the image
  final double? height;

  /// How to fit the image within its bounds
  final BoxFit fit;

  /// Border radius for the image
  final BorderRadius? borderRadius;

  /// Custom fallback widget when image is unavailable
  final Widget? fallback;

  /// Fallback color when no image available
  final Color? fallbackColor;

  /// Fallback icon when no image available
  final IconData fallbackIcon;

  /// Fallback icon size
  final double fallbackIconSize;

  const CachedArtwork({
    super.key,
    required this.albumId,
    this.artworkUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
    this.fallbackColor,
    this.fallbackIcon = Icons.album,
    this.fallbackIconSize = 48,
  });

  @override
  State<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<CachedArtwork> {
  final CacheManager _cacheManager = CacheManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();

  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId ||
        oldWidget.artworkUrl != widget.artworkUrl) {
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _localPath = null;
    });

    try {
      // ALWAYS check cache first - this works even when offline with no URL
      var cachedPath = await _cacheManager.getArtworkPath(widget.albumId);

      if (cachedPath != null && await File(cachedPath).exists()) {
        // Use cached version
        if (mounted) {
          setState(() {
            _localPath = cachedPath;
            _isLoading = false;
          });
        }
        return;
      }

      // No cached version - check if we have a URL to fetch from
      if (widget.artworkUrl == null || widget.artworkUrl!.isEmpty) {
        // No URL and no cache - show fallback
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      // Check if offline - don't fetch from network in offline mode
      if (_offlineService.isOffline) {
        // Offline and not cached - show fallback
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      // Not cached but have URL and online, try to cache from network
      cachedPath = await _cacheManager.cacheArtwork(
        widget.albumId,
        widget.artworkUrl!,
      );

      if (mounted) {
        if (cachedPath != null) {
          setState(() {
            _localPath = cachedPath;
            _isLoading = false;
          });
        } else {
          // Caching failed, try loading directly from network
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('[CachedArtwork] Error loading artwork for ${widget.albumId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (_isLoading) {
      // Show loading placeholder
      imageWidget = _buildPlaceholder(showLoading: true);
    } else if (_localPath != null) {
      // Show cached image
      imageWidget = Image.file(
        File(_localPath!),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback();
        },
      );
    } else if (!_hasError && widget.artworkUrl != null && !_offlineService.isOffline) {
      // Fallback to network image (caching may have failed) - only when online
      imageWidget = Image.network(
        widget.artworkUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder(showLoading: true);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback();
        },
      );
    } else {
      // Show fallback
      imageWidget = _buildFallback();
    }

    // Apply border radius if specified
    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder({bool showLoading = false}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: _getFallbackColor(),
      child: showLoading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            )
          : Icon(
              widget.fallbackIcon,
              size: widget.fallbackIconSize,
              color: Colors.white,
            ),
    );
  }

  Widget _buildFallback() {
    if (widget.fallback != null) {
      return widget.fallback!;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: _getFallbackColor(),
      child: Icon(
        widget.fallbackIcon,
        size: widget.fallbackIconSize,
        color: Colors.white,
      ),
    );
  }

  Color _getFallbackColor() {
    if (widget.fallbackColor != null) {
      return widget.fallbackColor!;
    }

    // Generate a color based on album ID for variety
    final colorIndex = widget.albumId.hashCode % 5;
    final colors = [
      Colors.blue[300]!,
      Colors.purple[300]!,
      Colors.green[300]!,
      Colors.orange[300]!,
      Colors.pink[300]!,
    ];
    return colors[colorIndex.abs()];
  }
}


