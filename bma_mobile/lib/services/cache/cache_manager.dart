import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../database/cache_database.dart';
import '../../models/cache_entry.dart';

/// Manages caching of artwork and songs with LRU eviction
class CacheManager {
  // Singleton pattern
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  late CacheDatabase _database;
  late Dio _dio;

  bool _initialized = false;
  String? _artworkCachePath;
  String? _songCachePath;

  // Track ongoing cache operations to avoid duplicates
  final Set<String> _pendingArtwork = {};
  final Set<String> _pendingSongs = {};

  // Stream controller for cache updates
  final StreamController<void> _cacheUpdateController =
      StreamController<void>.broadcast();

  /// Stream notifying when cache is updated
  Stream<void> get cacheUpdateStream => _cacheUpdateController.stream;

  /// Check if initialized
  bool get isInitialized => _initialized;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize the cache manager
  Future<void> initialize() async {
    if (_initialized) return;

    // Setup database
    _database = await CacheDatabase.create();

    // Setup HTTP client
    _dio = Dio();

    // Get cache directories
    final appDir = await getApplicationDocumentsDirectory();
    _artworkCachePath = '${appDir.path}/cache/artwork';
    _songCachePath = '${appDir.path}/cache/songs';

    // Create directories
    await Directory(_artworkCachePath!).create(recursive: true);
    await Directory(_songCachePath!).create(recursive: true);

    // Verify cache files exist, clean up orphaned entries
    await _cleanupOrphanedEntries();

    _initialized = true;
    print('[CacheManager] Initialized');
    print('[CacheManager] Artwork cache: $_artworkCachePath');
    print('[CacheManager] Song cache: $_songCachePath');
  }

  /// Ensure initialization
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  // ============================================================================
  // ARTWORK CACHING
  // ============================================================================

  /// Cache artwork from URL
  /// Returns the local file path if successful, null otherwise
  Future<String?> cacheArtwork(String albumId, String artworkUrl) async {
    await _ensureInitialized();

    if (!_database.isCacheEnabled()) return null;

    // Check if already cached
    final existing = await _database.getCacheEntry(albumId, CacheType.artwork);
    if (existing != null && await File(existing.path).exists()) {
      // Touch to update last accessed time
      await _database.touchCacheEntry(albumId, CacheType.artwork);
      return existing.path;
    }

    // Check if already being cached
    if (_pendingArtwork.contains(albumId)) {
      return null;
    }

    _pendingArtwork.add(albumId);

    try {
      final filePath = '$_artworkCachePath/$albumId.jpg';

      // Download artwork
      await _dio.download(
        artworkUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      // Get file size
      final file = File(filePath);
      final size = await file.length();

      // Create cache entry
      final entry = CacheEntry(
        id: albumId,
        type: CacheType.artwork,
        path: filePath,
        size: size,
        lastAccessed: DateTime.now(),
      );

      // Save entry and check limits
      await _database.upsertCacheEntry(entry);
      await _enforceStorageLimit();

      _cacheUpdateController.add(null);

      print('[CacheManager] Cached artwork: $albumId (${entry.getFormattedSize()})');
      return filePath;
    } catch (e) {
      print('[CacheManager] Failed to cache artwork $albumId: $e');
      return null;
    } finally {
      _pendingArtwork.remove(albumId);
    }
  }

  /// Get cached artwork path if exists
  Future<String?> getArtworkPath(String albumId) async {
    await _ensureInitialized();

    final entry = await _database.getCacheEntry(albumId, CacheType.artwork);
    if (entry != null && await File(entry.path).exists()) {
      // Touch to update last accessed time
      await _database.touchCacheEntry(albumId, CacheType.artwork);
      return entry.path;
    }
    return null;
  }

  /// Check if artwork is cached
  Future<bool> isArtworkCached(String albumId) async {
    await _ensureInitialized();
    final path = await getArtworkPath(albumId);
    return path != null;
  }

  // ============================================================================
  // SONG CACHING
  // ============================================================================

  /// Cache a song from URL (background download)
  /// Returns true if caching started, false if already cached/caching
  Future<bool> cacheSong(String songId, String downloadUrl) async {
    await _ensureInitialized();

    if (!_database.isCacheEnabled()) return false;

    // Check if already cached
    final existing = await _database.getCacheEntry(songId, CacheType.song);
    if (existing != null && await File(existing.path).exists()) {
      // Touch to update last accessed time
      await _database.touchCacheEntry(songId, CacheType.song);
      print('[CacheManager] Song already cached: $songId');
      return false;
    }

    // Check if already being cached
    if (_pendingSongs.contains(songId)) {
      print('[CacheManager] Song already being cached: $songId');
      return false;
    }

    _pendingSongs.add(songId);

    // Start background download (don't await)
    _downloadSongInBackground(songId, downloadUrl);

    return true;
  }

  /// Background song download
  Future<void> _downloadSongInBackground(String songId, String downloadUrl) async {
    try {
      final filePath = '$_songCachePath/$songId.mp3';

      print('[CacheManager] Starting background cache for song: $songId');

      // Download song
      await _dio.download(
        downloadUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      // Get file size
      final file = File(filePath);
      final size = await file.length();

      // Create cache entry
      final entry = CacheEntry(
        id: songId,
        type: CacheType.song,
        path: filePath,
        size: size,
        lastAccessed: DateTime.now(),
      );

      // Save entry and check limits
      await _database.upsertCacheEntry(entry);
      await _enforceStorageLimit();

      _cacheUpdateController.add(null);

      print('[CacheManager] Cached song: $songId (${entry.getFormattedSize()})');
    } catch (e) {
      print('[CacheManager] Failed to cache song $songId: $e');
    } finally {
      _pendingSongs.remove(songId);
    }
  }

  /// Get cached song path if exists
  Future<String?> getCachedSongPath(String songId) async {
    await _ensureInitialized();

    final entry = await _database.getCacheEntry(songId, CacheType.song);
    if (entry != null && await File(entry.path).exists()) {
      // Touch to update last accessed time
      await _database.touchCacheEntry(songId, CacheType.song);
      return entry.path;
    }
    return null;
  }

  /// Check if song is cached
  Future<bool> isSongCached(String songId) async {
    await _ensureInitialized();
    final path = await getCachedSongPath(songId);
    return path != null;
  }

  // ============================================================================
  // LRU EVICTION
  // ============================================================================

  /// Enforce storage limit using LRU eviction
  Future<void> _enforceStorageLimit() async {
    final limitBytes = _database.getCacheLimitBytes();
    var totalSize = await _database.getTotalCacheSize();

    if (totalSize <= limitBytes) return;

    print('[CacheManager] Cache limit exceeded: ${_formatBytes(totalSize)} / ${_formatBytes(limitBytes)}');
    print('[CacheManager] Starting LRU eviction...');

    // Get entries sorted by last accessed (oldest first)
    final entries = await _database.getEntriesForEviction();

    for (final entry in entries) {
      if (totalSize <= limitBytes) break;

      // Don't evict entries accessed in the last hour
      final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
      if (entry.lastAccessed.isAfter(hourAgo)) {
        continue;
      }

      // Delete file
      try {
        final file = File(entry.path);
        if (await file.exists()) {
          await file.delete();
          print('[CacheManager] Evicted: ${entry.id} (${entry.type.name})');
        }
      } catch (e) {
        print('[CacheManager] Failed to delete file: ${entry.path}');
      }

      // Remove entry
      await _database.removeCacheEntry(entry.id, entry.type);
      totalSize -= entry.size;
    }

    print('[CacheManager] Eviction complete. New size: ${_formatBytes(totalSize)}');
  }

  // ============================================================================
  // CACHE MANAGEMENT
  // ============================================================================

  /// Clear all cached content
  Future<void> clearAllCache() async {
    await _ensureInitialized();

    // Clear artwork cache
    await _clearDirectory(_artworkCachePath!);

    // Clear song cache
    await _clearDirectory(_songCachePath!);

    // Clear database entries
    await _database.clearAllCacheEntries();

    _cacheUpdateController.add(null);
    print('[CacheManager] All cache cleared');
  }

  /// Clear artwork cache only
  Future<void> clearArtworkCache() async {
    await _ensureInitialized();

    await _clearDirectory(_artworkCachePath!);
    await _database.clearEntriesByType(CacheType.artwork);

    _cacheUpdateController.add(null);
    print('[CacheManager] Artwork cache cleared');
  }

  /// Clear song cache only
  Future<void> clearSongCache() async {
    await _ensureInitialized();

    await _clearDirectory(_songCachePath!);
    await _database.clearEntriesByType(CacheType.song);

    _cacheUpdateController.add(null);
    print('[CacheManager] Song cache cleared');
  }

  /// Clear a directory's contents
  Future<void> _clearDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Remove orphaned entries (entries without matching files)
  Future<void> _cleanupOrphanedEntries() async {
    final entries = await _database.loadCacheEntries();
    final orphaned = <CacheEntry>[];

    for (final entry in entries) {
      if (!await File(entry.path).exists()) {
        orphaned.add(entry);
      }
    }

    for (final entry in orphaned) {
      await _database.removeCacheEntry(entry.id, entry.type);
    }

    if (orphaned.isNotEmpty) {
      print('[CacheManager] Cleaned up ${orphaned.length} orphaned entries');
    }
  }

  // ============================================================================
  // SETTINGS
  // ============================================================================

  /// Get cache limit in MB
  int getCacheLimit() => _database.getCacheLimit();

  /// Set cache limit in MB
  Future<void> setCacheLimit(int limitMB) async {
    await _ensureInitialized();
    await _database.setCacheLimit(limitMB);
    await _enforceStorageLimit();
  }

  /// Check if caching is enabled
  bool isCacheEnabled() => _database.isCacheEnabled();

  /// Enable or disable caching
  Future<void> setCacheEnabled(bool enabled) async {
    await _ensureInitialized();
    await _database.setCacheEnabled(enabled);
  }

  // ============================================================================
  // STATISTICS
  // ============================================================================

  /// Get total cache size in MB
  Future<double> getTotalCacheSizeMB() async {
    await _ensureInitialized();
    return await _database.getTotalCacheSizeMB();
  }

  /// Get total cache size in bytes
  Future<int> getTotalCacheSize() async {
    await _ensureInitialized();
    return await _database.getTotalCacheSize();
  }

  /// Get artwork cache size in bytes
  Future<int> getArtworkCacheSize() async {
    await _ensureInitialized();
    return await _database.getCacheSizeByType(CacheType.artwork);
  }

  /// Get song cache size in bytes
  Future<int> getSongCacheSize() async {
    await _ensureInitialized();
    return await _database.getCacheSizeByType(CacheType.song);
  }

  /// Get number of cached items
  Future<int> getCacheCount() async {
    await _ensureInitialized();
    return await _database.getCacheCount();
  }

  /// Get number of cached artworks
  Future<int> getArtworkCacheCount() async {
    await _ensureInitialized();
    return await _database.getCacheCountByType(CacheType.artwork);
  }

  /// Get number of cached songs
  Future<int> getSongCacheCount() async {
    await _ensureInitialized();
    return await _database.getCacheCountByType(CacheType.song);
  }

  // ============================================================================
  // UTILITY
  // ============================================================================

  /// Format bytes to human readable string
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Dispose resources
  void dispose() {
    _cacheUpdateController.close();
  }
}






