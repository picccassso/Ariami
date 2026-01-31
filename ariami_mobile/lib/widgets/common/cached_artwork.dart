import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/cache/cache_manager.dart';
import '../../services/offline/offline_playback_service.dart';

/// Size hint for artwork loading.
///
/// Use [thumbnail] for list views (faster loading, smaller images).
/// Use [full] for detail views (full quality).
enum ArtworkSizeHint {
  /// Small size for list views (requests thumbnail from server, ~200x200)
  thumbnail,

  /// Full size for detail views (requests original image)
  full,
}

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

  /// Size hint for loading optimization.
  ///
  /// Use [ArtworkSizeHint.thumbnail] for list views (faster, smaller images).
  /// Use [ArtworkSizeHint.full] for detail views (full quality).
  /// Defaults to [ArtworkSizeHint.full] for backward compatibility.
  final ArtworkSizeHint sizeHint;

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
    this.sizeHint = ArtworkSizeHint.full,
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
    // Check memory cache synchronously BEFORE first build to avoid flash
    final memoryPath = _cacheManager.getArtworkPathSync(_cacheKey);
    if (memoryPath != null) {
      _localPath = memoryPath;
      _isLoading = false;
    } else {
      _loadArtwork();
    }
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId ||
        oldWidget.artworkUrl != widget.artworkUrl ||
        oldWidget.sizeHint != widget.sizeHint) {
      _loadArtwork();
    }
  }

  /// Get the cache key for this artwork (includes size hint for thumbnails)
  String get _cacheKey {
    if (widget.sizeHint == ArtworkSizeHint.thumbnail) {
      return '${widget.albumId}_thumb';
    }
    return widget.albumId;
  }

  /// Get the fallback cache key (opposite size variant)
  /// Used when primary cache key is not found - allows thumbnail to fall back to full-size and vice versa
  String get _fallbackCacheKey {
    if (widget.sizeHint == ArtworkSizeHint.thumbnail) {
      // Thumbnail requested but not cached - try full-size
      return widget.albumId;
    }
    // Full-size requested but not cached - try thumbnail
    return '${widget.albumId}_thumb';
  }

  /// Get the effective URL with size parameter appended
  String? get _effectiveUrl {
    if (widget.artworkUrl == null || widget.artworkUrl!.isEmpty) {
      return null;
    }
    if (widget.sizeHint == ArtworkSizeHint.thumbnail) {
      final separator = widget.artworkUrl!.contains('?') ? '&' : '?';
      return '${widget.artworkUrl}${separator}size=thumbnail';
    }
    return widget.artworkUrl;
  }

  Future<void> _loadArtwork() async {
    if (!mounted) return;

    final cacheKey = _cacheKey;
    final effectiveUrl = _effectiveUrl;

    // Check memory cache FIRST (synchronous - no flash!)
    final memoryPath = _cacheManager.getArtworkPathSync(cacheKey);
    if (memoryPath != null) {
      if (mounted) {
        setState(() {
          _localPath = memoryPath;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // Not in memory, need async lookup - show loading state
    setState(() {
      _isLoading = true;
      _hasError = false;
      _localPath = null;
    });

    try {
      // Check disk cache with fallback - tries primary key first, then fallback key
      // This allows thumbnails to use full-size cache and vice versa when offline
      var cachedPath = await _cacheManager.getArtworkPathWithFallback(
        cacheKey,
        _fallbackCacheKey,
      );

      if (cachedPath != null && await File(cachedPath).exists()) {
        // Use cached version (either primary or fallback)
        if (mounted) {
          setState(() {
            _localPath = cachedPath;
            _isLoading = false;
          });
        }
        return;
      }

      // No cached version (neither primary nor fallback) - check if we have a URL to fetch from
      if (effectiveUrl == null) {
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
      // Pass the cache key and effective URL (with size parameter)
      cachedPath = await _cacheManager.cacheArtwork(
        cacheKey,
        effectiveUrl,
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
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback();
        },
      );
    } else if (!_hasError && _effectiveUrl != null && !_offlineService.isOffline) {
      // Fallback to network image (caching may have failed) - only when online
      imageWidget = Image.network(
        _effectiveUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
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


