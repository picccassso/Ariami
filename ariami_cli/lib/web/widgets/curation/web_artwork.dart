import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

/// Authenticated image provider for server artwork on Flutter Web, throttling
/// concurrent requests and keeping an in-memory LRU byte cache.
@immutable
class WebArtworkImageProvider extends ImageProvider<WebArtworkImageProvider> {
  const WebArtworkImageProvider(
    this.url, {
    required this.client,
    this.scale = 1.0,
  });

  final String url;
  final WebApiClient client;
  final double scale;

  static const int _maxConcurrentNetworkFetches = 4;
  static int _activeNetworkFetches = 0;
  static final Queue<Completer<void>> _fetchWaiters = Queue<Completer<void>>();

  static const int _maxMemoryCacheEntries = 500;
  static final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();

  static Future<void> _acquireFetchSlot() {
    if (_activeNetworkFetches < _maxConcurrentNetworkFetches) {
      _activeNetworkFetches++;
      return SynchronousFuture<void>(null);
    }
    final waiter = Completer<void>();
    _fetchWaiters.add(waiter);
    return waiter.future;
  }

  static void _releaseFetchSlot() {
    if (_fetchWaiters.isNotEmpty) {
      _fetchWaiters.removeFirst().complete();
    } else {
      _activeNetworkFetches--;
    }
  }

  static Uint8List? _readCache(String key) {
    final cached = _memoryCache.remove(key);
    if (cached != null) {
      _memoryCache[key] = cached;
    }
    return cached;
  }

  static void _writeCache(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    if (_memoryCache.length >= _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bytes;
  }

  @override
  Future<WebArtworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<WebArtworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    WebArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    WebArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _loadBytes(key);
    if (bytes.isEmpty) {
      throw StateError('Artwork response was empty: ${key.url}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _loadBytes(WebArtworkImageProvider key) async {
    final cached = _readCache(key.url);
    if (cached != null) return cached;

    await _acquireFetchSlot();
    final Uint8List bytes;
    try {
      bytes = await key.client.getArtworkBytes(key.url);
    } finally {
      _releaseFetchSlot();
    }
    if (bytes.isNotEmpty) {
      _writeCache(key.url, bytes);
    }
    return bytes;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebArtworkImageProvider &&
        other.url == url &&
        other.scale == scale &&
        other.client == client;
  }

  @override
  int get hashCode => Object.hash(url, scale, client);

  @override
  String toString() => 'WebArtworkImageProvider("$url", scale: $scale)';
}

/// Album or song thumbnail backed by [WebArtworkImageProvider], with automatic
/// fallback from album art to song art and a styled icon placeholder.
class WebArtwork extends StatefulWidget {
  const WebArtwork({
    super.key,
    required this.client,
    this.albumId,
    this.songId,
    this.size = 48,
    this.borderRadius = AppTheme.radiusSmall,
    this.thumbnail = true,
    this.iconScale = 0.5,
    this.placeholderIcon = Icons.music_note_rounded,
    this.deferDuringScroll = false,
  });

  final WebApiClient? client;
  final String? albumId;
  final String? songId;
  final double size;
  final double borderRadius;
  final bool thumbnail;
  final double iconScale;
  final IconData placeholderIcon;
  final bool deferDuringScroll;

  @override
  State<WebArtwork> createState() => _WebArtworkState();
}

class _WebArtworkState extends State<WebArtwork> {
  String? get _url {
    final client = widget.client;
    if (client == null) return null;
    final albumId = widget.albumId;
    if (albumId != null && albumId.isNotEmpty) {
      return client.albumArtworkUrl(albumId, thumbnail: widget.thumbnail);
    }
    final songId = widget.songId;
    if (songId != null && songId.isNotEmpty) {
      return client.songArtworkUrl(songId, thumbnail: widget.thumbnail);
    }
    return null;
  }

  int _cacheWidth(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final oversample = widget.thumbnail ? 2.0 : 1.25;
    return (widget.size * dpr * oversample).clamp(96, 2048).round();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final url = _url;

    if (url == null || widget.client == null) {
      return _placeholder(radius);
    }

    if (widget.deferDuringScroll &&
        Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return _placeholder(radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppTheme.surfaceRaised),
            Image(
              image: ResizeImage.resizeIfNeeded(
                _cacheWidth(context),
                null,
                WebArtworkImageProvider(url, client: widget.client!),
              ),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _fallbackAfterError(radius),
              frameBuilder: (_, child, frame, wasSyncLoaded) {
                return AnimatedOpacity(
                  opacity: (wasSyncLoaded || frame != null) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: child,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackAfterError(BorderRadius radius) {
    final songId = widget.songId;
    if (widget.albumId != null && songId != null && songId.isNotEmpty) {
      return WebArtwork(
        client: widget.client,
        songId: songId,
        size: widget.size,
        borderRadius: widget.borderRadius,
        thumbnail: widget.thumbnail,
        iconScale: widget.iconScale,
        placeholderIcon: widget.placeholderIcon,
        deferDuringScroll: widget.deferDuringScroll,
      );
    }
    return _placeholder(radius);
  }

  Widget _placeholder(BorderRadius radius) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceHover, AppTheme.surfaceRaised],
        ),
      ),
      child: Icon(
        widget.placeholderIcon,
        size: widget.size * widget.iconScale,
        color: AppTheme.textPrimary.withValues(alpha: 0.3),
      ),
    );
  }
}
