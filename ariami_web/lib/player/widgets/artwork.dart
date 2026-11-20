import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/player_models.dart';
import '../services/player_api_client.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork_image_provider.dart';

/// An album/track artwork tile that authenticates image requests against the
/// server (artwork endpoints accept the session bearer token) and shows a
/// graceful fallback when artwork is missing or fails to load.
class Artwork extends StatefulWidget {
  const Artwork({
    super.key,
    required this.client,
    this.albumId,
    this.songId,
    this.size = 48,
    this.borderRadius = PlayerTheme.coverRadius,
    this.thumbnail = true,
    this.iconScale = 0.5,
    this.placeholderIcon = Icons.music_note_rounded,
    this.deferDuringScroll = false,
  });

  final PlayerApiClient? client;
  final String? albumId;
  final String? songId;
  final double size;
  final double borderRadius;
  final bool thumbnail;
  final double iconScale;

  /// Glyph drawn when there is no artwork to show. Artist tiles pass a person
  /// so a coverless artist doesn't read as a song.
  final IconData placeholderIcon;

  /// When true and this tile lives inside a fast-flinging [Scrollable], the
  /// cover isn't decoded — the placeholder is shown instead, and the real image
  /// is loaded once scrolling slows. Keeps long, fast list scrolls smooth by
  /// not decoding covers the user is blowing straight past. Opt-in so grids and
  /// the now-playing art (which aren't in a fling) are unaffected.
  final bool deferDuringScroll;

  static ImageProvider thumbnailOf(Track track, PlayerApiClient client) =>
      ArtworkImageProvider(
        track.albumId != null
            ? client.albumArtworkUrl(track.albumId!, thumbnail: true)
            : client.songArtworkUrl(track.id, thumbnail: true),
        headers: client.artworkHeaders,
      );

  /// A disk-cached server image (custom playlist/artist photo) decoded at
  /// [cacheWidth] physical pixels. Unlike `Image.network`, it survives
  /// relaunches, so remote/Tailscale libraries don't refetch every photo.
  static ImageProvider cachedImage(
    String url,
    PlayerApiClient client, {
    required int cacheWidth,
  }) =>
      ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        ArtworkImageProvider(
          ArtworkImageProvider.sizedUrl(url, cacheWidth),
          headers: client.artworkHeaders,
        ),
      );

  @override
  State<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<Artwork> {
  ArtworkCancelToken _cancelToken = ArtworkCancelToken();
  String? _lastUrl;

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  /// Small tiles use the precomputed thumbnail, mid-sized cards the 640px
  /// variant, and only large views fetch the original artwork.
  String? _url(int cacheWidth) {
    final c = widget.client;
    if (c == null) return null;
    final thumbnail = widget.thumbnail;
    final medium = !thumbnail && cacheWidth <= 640;
    final albumId = widget.albumId;
    if (albumId != null && albumId.isNotEmpty) {
      return c.albumArtworkUrl(albumId, thumbnail: thumbnail, medium: medium);
    }
    final songId = widget.songId;
    if (songId != null && songId.isNotEmpty) {
      return c.songArtworkUrl(songId, thumbnail: thumbnail, medium: medium);
    }
    return null;
  }

  /// Target decode width in physical pixels, capped so we never decode a huge
  /// cover into a tiny tile. Only the width is constrained so the decoder keeps
  /// the artwork's real aspect ratio (passing both width and height squares the
  /// bitmap and distorts non-square covers).
  int _cacheWidth(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    // Small covers and mosaic cells are especially sensitive to looking soft:
    // their exact-size decode leaves no spare pixels for Retina compositing,
    // fractional positioning, hover scaling, or window resizing. Decode those
    // at 2× their physical display width and larger artwork at 1.25×, then let
    // Flutter downsample with high-quality filtering below.
    final oversample = widget.thumbnail ? 2.0 : 1.25;
    return (widget.size * dpr * oversample).clamp(96, 2048).round();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final cacheWidth = _cacheWidth(context);
    final url = _url(cacheWidth);

    if (url == null || ArtworkImageProvider.isKnownMissing(url)) {
      return _placeholder(context, radius);
    }

    if (_lastUrl != null && _lastUrl != url) {
      _cancelToken.cancel();
      _cancelToken = ArtworkCancelToken();
    }
    _lastUrl = url;

    // While the enclosing list is flinging fast, skip the decode and paint the
    // placeholder; re-check next frame (scheduleFrameCallback also requests a
    // frame, so we keep polling until the fling slows and this returns false).
    if (widget.deferDuringScroll &&
        Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return _placeholder(context, radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Solid backing so a transparent cover or any sub-pixel gap at the
            // rounded edges never reveals a different colour behind it.
            ColoredBox(color: context.colors.surfaceHigh),
            Image(
              // A disk-backed provider so covers persist across launches and
              // paint immediately on the next start instead of being re-fetched
              // from the server every time. [ResizeImage] keeps the cheap
              // down-decode we previously got from `Image.network`'s cacheWidth.
              image: ResizeImage.resizeIfNeeded(
                cacheWidth,
                null,
                ArtworkImageProvider(
                  url,
                  headers: widget.client?.artworkHeaders,
                  cancelToken: _cancelToken,
                ),
              ),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
              errorBuilder: (context, __, ___) =>
                  _fallbackAfterError(context, radius),
              frameBuilder: (context, child, frame, wasSyncLoaded) {
                // Fade each cover in over the dark backing as it decodes, so
                // grids and the now-playing art settle in smoothly instead of
                // popping.
                return AnimatedOpacity(
                  opacity: (wasSyncLoaded || frame != null) ? 1.0 : 0.0,
                  duration: Motion.medium,
                  curve: Motion.standard,
                  child: child,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackAfterError(BuildContext context, BorderRadius radius) {
    final songId = widget.songId;
    if (widget.albumId != null && songId != null && songId.isNotEmpty) {
      return Artwork(
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
    return _placeholder(context, radius);
  }

  Widget _placeholder(BuildContext context, BorderRadius radius) {
    final colors = context.colors;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceHover, colors.surfaceHigh],
        ),
      ),
      child: Icon(
        widget.placeholderIcon,
        size: widget.size * widget.iconScale,
        color: colors.textPrimary.withValues(alpha: 0.3),
      ),
    );
  }
}
