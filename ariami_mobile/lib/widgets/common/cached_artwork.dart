import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/api/connection_service.dart';
import '../../services/cache/cache_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/download/local_artwork_extractor.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/media/media_request_scheduler.dart';

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
  static final Set<String> _pendingExtractions = <String>{};

  final CacheManager _cacheManager = CacheManager();
  final DownloadManager _downloadManager = DownloadManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final ConnectionService _connectionService = ConnectionService();

  String? _localPath;
  String? _networkFallbackUrl;
  bool _isLoading = true;
  MediaRequestCancellationToken? _requestCancellationToken;

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
      _cancelArtworkRequest();
      _loadArtwork();
    }
  }

  @override
  void dispose() {
    _cancelArtworkRequest();
    super.dispose();
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
    final resolvedUrl = _connectionService.resolveServerUrl(widget.artworkUrl);
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    if (widget.sizeHint == ArtworkSizeHint.thumbnail) {
      final separator = resolvedUrl.contains('?') ? '&' : '?';
      return '$resolvedUrl${separator}size=thumbnail';
    }
    return resolvedUrl;
  }

  Future<void> _loadArtwork() async {
    if (!mounted) return;
    _cancelArtworkRequest();
    final requestToken = MediaRequestCancellationToken();
    _requestCancellationToken = requestToken;

    final cacheKey = _cacheKey;
    final effectiveUrl = _effectiveUrl;

    // Check memory cache FIRST (synchronous - no flash!)
    final memoryPath = _cacheManager.getArtworkPathSync(cacheKey);
    if (memoryPath != null) {
      if (mounted) {
        setState(() {
          _localPath = memoryPath;
          _isLoading = false;
          _networkFallbackUrl = null;
        });
      }
      return;
    }

    // Not in memory, need async lookup - show loading state
    setState(() {
      _isLoading = true;
      _localPath = null;
      _networkFallbackUrl = null;
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
        if (mounted &&
            _requestCancellationToken == requestToken &&
            !requestToken.isCancelled) {
          setState(() {
            _localPath = cachedPath;
            _isLoading = false;
            _networkFallbackUrl = null;
          });
        }
        return;
      }

      // Check if offline - don't fetch from network in offline mode.
      // If cache is missing, try a one-off extraction from local downloaded file.
      if (_offlineService.isOffline) {
        cachedPath = await _tryExtractFromLocalFile(requestToken: requestToken);
        if (cachedPath != null && await File(cachedPath).exists()) {
          if (mounted &&
              _requestCancellationToken == requestToken &&
              !requestToken.isCancelled) {
            setState(() {
              _localPath = cachedPath;
              _isLoading = false;
              _networkFallbackUrl = null;
            });
          }
          return;
        }

        // Offline, not cached, and no extractable local artwork - show fallback
        if (mounted &&
            _requestCancellationToken == requestToken &&
            !requestToken.isCancelled) {
          setState(() {
            _isLoading = false;
            _networkFallbackUrl = null;
          });
        }
        return;
      }

      // No cached version (neither primary nor fallback) - check if we have a URL to fetch from
      if (effectiveUrl == null) {
        // No URL and no cache - show fallback
        if (mounted &&
            _requestCancellationToken == requestToken &&
            !requestToken.isCancelled) {
          setState(() {
            _isLoading = false;
            _networkFallbackUrl = null;
          });
        }
        return;
      }

      // Not cached but have URL and online, try to cache from network
      // Pass the cache key and effective URL (with size parameter)
      // Requests are always scheduled (bounded + prioritized + cancelable).
      cachedPath = await _cacheManager.cacheArtwork(
        cacheKey,
        effectiveUrl,
        priority: _requestPriority,
        cancellationToken: requestToken,
      );
      if (cachedPath == null &&
          _requestCancellationToken == requestToken &&
          !requestToken.isCancelled) {
        cachedPath = await _retryOnlineArtworkCache(
          cacheKey: cacheKey,
          effectiveUrl: effectiveUrl,
          requestToken: requestToken,
        );
      }

      if (mounted &&
          _requestCancellationToken == requestToken &&
          !requestToken.isCancelled) {
        if (cachedPath != null) {
          setState(() {
            _localPath = cachedPath;
            _isLoading = false;
            _networkFallbackUrl = null;
          });
        } else {
          // Caching failed after retry - use direct network rendering as a
          // visual fallback instead of a terminal placeholder state.
          setState(() {
            _isLoading = false;
            _networkFallbackUrl = effectiveUrl;
          });
        }
      }
    } catch (e) {
      if (requestToken.isCancelled) {
        return;
      }
      debugPrint(
          '[CachedArtwork] Error loading artwork for ${widget.albumId}: $e');
      if (mounted && _requestCancellationToken == requestToken) {
        setState(() {
          _isLoading = false;
          _networkFallbackUrl = null;
        });
      }
    }
  }

  Future<String?> _retryOnlineArtworkCache({
    required String cacheKey,
    required String effectiveUrl,
    required MediaRequestCancellationToken requestToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (_requestCancellationToken != requestToken || requestToken.isCancelled) {
      return null;
    }
    return _cacheManager.cacheArtwork(
      cacheKey,
      effectiveUrl,
      priority: _requestPriority,
      cancellationToken: requestToken,
    );
  }

  MediaRequestPriority get _requestPriority {
    if (widget.sizeHint == ArtworkSizeHint.thumbnail) {
      return MediaRequestPriority.visibleNow;
    }
    return MediaRequestPriority.nearby;
  }

  void _cancelArtworkRequest() {
    _requestCancellationToken?.cancel();
    _requestCancellationToken = null;
  }

  Future<String?> _tryExtractFromLocalFile({
    required MediaRequestCancellationToken requestToken,
  }) async {
    final sourceKey = _normalizeSourceKey(widget.albumId);
    if (sourceKey.isEmpty) return null;

    final extractionKey = 'source:$sourceKey';
    if (_pendingExtractions.contains(extractionKey)) {
      // Another widget is extracting this same source.
      // Wait briefly and re-check cache instead of duplicating IO.
      for (var attempt = 0; attempt < 6; attempt++) {
        if (requestToken.isCancelled) return null;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final existingPath = await _cacheManager.getArtworkPathWithFallback(
          _cacheKey,
          _fallbackCacheKey,
        );
        if (existingPath != null && await File(existingPath).exists()) {
          return existingPath;
        }
      }
      return null;
    }

    _pendingExtractions.add(extractionKey);
    try {
      if (requestToken.isCancelled) return null;

      String? localSongPath;
      if (_isSongCacheKey(sourceKey)) {
        final songId = sourceKey.substring(5).trim();
        if (songId.isEmpty) return null;
        localSongPath = _downloadManager.getDownloadedSongPath(songId);
      } else {
        localSongPath = _downloadManager.getAnyDownloadedSongPathForAlbum(
          sourceKey,
        );
      }

      if (localSongPath == null || localSongPath.isEmpty) return null;
      if (!await File(localSongPath).exists()) return null;

      final bytes = await LocalArtworkExtractor.extractArtwork(localSongPath);
      if (requestToken.isCancelled || bytes == null || bytes.isEmpty) {
        return null;
      }

      return await _cacheManager.cacheArtworkFromBytes(_cacheKey, bytes);
    } catch (e) {
      debugPrint(
          '[CachedArtwork] Local artwork extraction failed for ${widget.albumId}: $e');
      return null;
    } finally {
      _pendingExtractions.remove(extractionKey);
    }
  }

  String _normalizeSourceKey(String key) {
    final normalized = key.trim();
    if (normalized.endsWith('_thumb')) {
      return normalized.substring(0, normalized.length - '_thumb'.length);
    }
    return normalized;
  }

  bool _isSongCacheKey(String key) {
    return key.startsWith('song_') && key.length > 'song_'.length;
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
    } else if (_networkFallbackUrl != null && !_offlineService.isOffline) {
      imageWidget = Image.network(
        _networkFallbackUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        headers: _connectionService.authHeaders,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
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
