import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/gradient_colors.dart';
import '../models/song.dart';
import 'api/connection_service.dart';
import 'cache/cache_manager.dart';

/// Service for extracting dominant colors from album artwork
/// Used to create dynamic gradient backgrounds in the player
class ColorExtractionService extends ChangeNotifier {
  // Singleton pattern
  static final ColorExtractionService _instance =
      ColorExtractionService._internal();
  factory ColorExtractionService() => _instance;
  ColorExtractionService._internal();

  final CacheManager _cacheManager = CacheManager();
  final ConnectionService _connectionService = ConnectionService();

  // Cache of extracted colors by cacheId (albumId or song_songId)
  final Map<String, GradientColors> _colorCache = {};

  // Currently active colors (for the current song)
  GradientColors _currentColors = GradientColors.fallback;
  String? _currentCacheId;

  // Track pending extractions to avoid duplicates
  final Set<String> _pendingExtractions = {};

  /// Get the current gradient colors for the player
  GradientColors get currentColors => _currentColors;

  /// Extract colors for a song (uses album artwork if available)
  Future<void> extractColorsForSong(Song? song) async {
    if (song == null) {
      _currentColors = GradientColors.fallback;
      _currentCacheId = null;
      notifyListeners();
      return;
    }

    // Determine cache ID - prefer album artwork
    final cacheId = song.albumId ?? 'song_${song.id}';

    // If same as current, no need to re-extract
    if (cacheId == _currentCacheId) {
      return;
    }

    // Check if already cached in memory
    if (_colorCache.containsKey(cacheId)) {
      _currentColors = _colorCache[cacheId]!;
      _currentCacheId = cacheId;
      notifyListeners();
      return;
    }

    // Check if extraction already in progress
    if (_pendingExtractions.contains(cacheId)) {
      return;
    }

    _pendingExtractions.add(cacheId);

    try {
      GradientColors? colors;

      // Try to extract from cached artwork file first (fastest)
      final cachedPath = await _cacheManager.getArtworkPath(
        song.albumId ?? 'song_${song.id}',
      );

      if (cachedPath != null) {
        colors = await _extractFromFile(cachedPath);
      }

      // If not cached locally, try to extract from network
      if (colors == null && _connectionService.isConnected) {
        final artworkUrl = _getArtworkUrl(song);
        if (artworkUrl != null) {
          colors = await _extractFromUrl(artworkUrl);
        }
      }

      // Use fallback if extraction failed
      colors ??= GradientColors.fallback;

      // Cache the result
      _colorCache[cacheId] = colors;

      // Update current colors if this is still the active song
      _currentColors = colors;
      _currentCacheId = cacheId;
      notifyListeners();
    } catch (e) {
      print('[ColorExtractionService] Error extracting colors: $e');
      _currentColors = GradientColors.fallback;
      _currentCacheId = cacheId;
      notifyListeners();
    } finally {
      _pendingExtractions.remove(cacheId);
    }
  }

  /// Extract colors from a local file
  Future<GradientColors?> _extractFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(file),
        size: const Size(100, 100), // Small size for performance
        maximumColorCount: 16,
      );

      return _colorsFromPalette(palette);
    } catch (e) {
      print('[ColorExtractionService] Error extracting from file: $e');
      return null;
    }
  }

  /// Extract colors from a network URL
  Future<GradientColors?> _extractFromUrl(String url) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(100, 100), // Small size for performance
        maximumColorCount: 16,
      );

      return _colorsFromPalette(palette);
    } catch (e) {
      print('[ColorExtractionService] Error extracting from URL: $e');
      return null;
    }
  }

  /// Convert palette to GradientColors
  GradientColors _colorsFromPalette(PaletteGenerator palette) {
    // Primary: prefer dominant color, fallback to vibrant
    final primary = palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        GradientColors.fallback.primary;

    // Secondary: prefer dark muted, fallback to dark vibrant or darker primary
    final secondary = palette.darkMutedColor?.color ??
        palette.darkVibrantColor?.color ??
        _darken(primary, 0.3);

    // Accent: prefer light vibrant for potential highlights
    final accent = palette.lightVibrantColor?.color ?? palette.vibrantColor?.color;

    return GradientColors(
      primary: primary,
      secondary: secondary,
      accent: accent,
    );
  }

  /// Darken a color by a factor (0.0 = no change, 1.0 = black)
  Color _darken(Color color, double factor) {
    return Color.fromARGB(
      (color.a * 255).round(),
      ((color.r * 255) * (1 - factor)).round(),
      ((color.g * 255) * (1 - factor)).round(),
      ((color.b * 255) * (1 - factor)).round(),
    );
  }

  /// Get artwork URL for a song
  String? _getArtworkUrl(Song song) {
    final serverInfo = _connectionService.serverInfo;
    if (serverInfo == null) return null;

    final baseUrl = 'http://${serverInfo.server}:${serverInfo.port}/api';

    if (song.albumId != null) {
      return '$baseUrl/artwork/${song.albumId}';
    } else {
      return '$baseUrl/song-artwork/${song.id}';
    }
  }

  /// Clear the color cache
  void clearCache() {
    _colorCache.clear();
    _currentColors = GradientColors.fallback;
    _currentCacheId = null;
    notifyListeners();
  }

  /// Reset to fallback colors (e.g., when no song is playing)
  void resetToFallback() {
    _currentColors = GradientColors.fallback;
    _currentCacheId = null;
    notifyListeners();
  }
}
