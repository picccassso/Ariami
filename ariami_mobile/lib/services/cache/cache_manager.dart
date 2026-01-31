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

  // Concurrency limiter for artwork downloads
  // Increased from 3 to 6 since thumbnails are ~100x smaller (~2.8KB vs 304KB)
  // This allows faster loading of playlists with many items
  static const int _maxConcurrentArtworkDownloads = 6;
  // No queue limit - Completers are lightweight (~48 bytes each)
  // A library with 500 albums only uses ~24KB for the queue
  int _activeArtworkDownloads = 0;
  final List<Completer<void>> _artworkDownloadQueue = [];

  // In-memory cache of artwork paths for instant synchronous lookups
  final Map<String, String> _artworkPathCache = {};

  // In-memory tracking of cache size to avoid repeated DB queries
  int _cachedTotalSize = 0;
  bool _cacheSizeInitialized = false;

  // Debounce timer for storage limit enforcement
  // Instead of checking after every download, batch checks every 2 seconds
  Timer? _enforceLimitTimer;
  bool _enforceLimitPending = false;

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

    // Pre-populate memory cache with all artwork paths for instant sync lookups
    await _prePopulateArtworkPathCache();

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
  // ARTWORK DOWNLOAD CONCURRENCY CONTROL
  // ============================================================================

  /// Acquire a download slot, waiting if at max concurrency.
  /// All requests are queued - no rejections. Completers are lightweight.
  Future<bool> _acquireArtworkSlot() async {
    if (_activeArtworkDownloads < _maxConcurrentArtworkDownloads) {
      _activeArtworkDownloads++;
      return true;
    }
    // At max concurrency - queue and wait (no limit on queue size)
    final completer = Completer<void>();
    _artworkDownloadQueue.add(completer);
    await completer.future;
    return true;
  }

  /// Release a download slot, unblocking the next queued request
  void _releaseArtworkSlot() {
    if (_artworkDownloadQueue.isNotEmpty) {
      // Hand the slot to the next waiter
      final next = _artworkDownloadQueue.removeAt(0);
      next.complete();
    } else {
      _activeArtworkDownloads--;
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

    // Check memory cache first (instant, no DB query needed)
    // This is usually already checked by CachedArtwork widget, but double-check here
    if (_artworkPathCache.containsKey(albumId)) {
      return _artworkPathCache[albumId];
    }

    // Check if already being cached by another request
    if (_pendingArtwork.contains(albumId)) {
      return null;
    }

    _pendingArtwork.add(albumId);

    // Wait for a download slot (limits concurrent network requests)
    final acquired = await _acquireArtworkSlot();
    if (!acquired) {
      _pendingArtwork.remove(albumId);
      return null;
    }

    try {
      final filePath = '$_artworkCachePath/$albumId.jpg';

      // Download artwork
      // Timeout reduced to 15s - thumbnails are ~2.8KB, even full images are <500KB
      // On slow connections, if 15s isn't enough, network is likely too slow for streaming
      await _dio.download(
        artworkUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
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

      // Save entry and schedule debounced limit check
      await _database.upsertCacheEntry(entry);
      _scheduleEnforceStorageLimit(size);

      _cacheUpdateController.add(null);

      // Store in memory cache for future instant lookups
      _artworkPathCache[albumId] = filePath;

      print('[CacheManager] Cached artwork: $albumId (${entry.getFormattedSize()})');
      return filePath;
    } catch (e) {
      print('[CacheManager] Failed to cache artwork $albumId: $e');
      return null;
    } finally {
      _pendingArtwork.remove(albumId);
      _releaseArtworkSlot();
    }
  }

  /// Get cached artwork path if exists
  Future<String?> getArtworkPath(String albumId) async {
    // Check memory cache first (instant)
    if (_artworkPathCache.containsKey(albumId)) {
      return _artworkPathCache[albumId];
    }

    await _ensureInitialized();

    final entry = await _database.getCacheEntry(albumId, CacheType.artwork);
    if (entry != null && await File(entry.path).exists()) {
      // Touch to update last accessed time
      await _database.touchCacheEntry(albumId, CacheType.artwork);
      // Store in memory cache for future instant lookups
      _artworkPathCache[albumId] = entry.path;
      return entry.path;
    }
    return null;
  }

  /// Get cached artwork path synchronously from memory cache
  /// Returns null if not in memory (may still be on disk)
  String? getArtworkPathSync(String albumId) {
    return _artworkPathCache[albumId];
  }

  /// Get cached artwork path with fallback key support
  /// Tries primaryKey first, then fallbackKey if provided
  /// Checks memory cache first (instant), then disk cache for both keys
  /// Returns the path from whichever key is found first, or null if neither exists
  Future<String?> getArtworkPathWithFallback(String primaryKey, String? fallbackKey) async {
    // 1. Check memory cache for primary key (instant)
    if (_artworkPathCache.containsKey(primaryKey)) {
      return _artworkPathCache[primaryKey];
    }

    // 2. Check memory cache for fallback key (instant)
    if (fallbackKey != null && _artworkPathCache.containsKey(fallbackKey)) {
      return _artworkPathCache[fallbackKey];
    }

    await _ensureInitialized();

    // 3. Check disk cache for primary key
    final primaryEntry = await _database.getCacheEntry(primaryKey, CacheType.artwork);
    if (primaryEntry != null && await File(primaryEntry.path).exists()) {
      await _database.touchCacheEntry(primaryKey, CacheType.artwork);
      _artworkPathCache[primaryKey] = primaryEntry.path;
      return primaryEntry.path;
    }

    // 4. Check disk cache for fallback key
    if (fallbackKey != null) {
      final fallbackEntry = await _database.getCacheEntry(fallbackKey, CacheType.artwork);
      if (fallbackEntry != null && await File(fallbackEntry.path).exists()) {
        await _database.touchCacheEntry(fallbackKey, CacheType.artwork);
        _artworkPathCache[fallbackKey] = fallbackEntry.path;
        return fallbackEntry.path;
      }
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

      // Save entry and schedule debounced limit check
      await _database.upsertCacheEntry(entry);
      _scheduleEnforceStorageLimit(size);

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

  /// Get all cached song IDs in a single batch query
  /// Much faster than calling isSongCached() for each song individually
  Future<Set<String>> getCachedSongIds() async {
    await _ensureInitialized();
    final entries = await _database.getEntriesByType(CacheType.song);
    final cachedIds = <String>{};
    for (final entry in entries) {
      if (await File(entry.path).exists()) {
        cachedIds.add(entry.id);
      }
    }
    return cachedIds;
  }

  // ============================================================================
  // LRU EVICTION
  // ============================================================================

  /// Schedule a debounced storage limit check
  /// Instead of checking after every download (500 DB queries!), batch them
  void _scheduleEnforceStorageLimit(int addedBytes) {
    // Track added bytes in memory
    _cachedTotalSize += addedBytes;

    // If already pending, don't schedule another
    if (_enforceLimitPending) return;

    _enforceLimitPending = true;

    // Debounce: wait 2 seconds of inactivity before actually checking
    _enforceLimitTimer?.cancel();
    _enforceLimitTimer = Timer(const Duration(seconds: 2), () async {
      _enforceLimitPending = false;
      await _enforceStorageLimitActual();
    });
  }

  /// Actually enforce storage limit using LRU eviction
  /// Only called after debounce timer fires
  Future<void> _enforceStorageLimitActual() async {
    final limitBytes = _database.getCacheLimitBytes();

    // Initialize in-memory size tracking if needed
    if (!_cacheSizeInitialized) {
      _cachedTotalSize = await _database.getTotalCacheSize();
      _cacheSizeInitialized = true;
    }

    if (_cachedTotalSize <= limitBytes) return;

    print('[CacheManager] Cache limit exceeded: ${_formatBytes(_cachedTotalSize)} / ${_formatBytes(limitBytes)}');
    print('[CacheManager] Starting LRU eviction...');

    // Get entries sorted by last accessed (oldest first)
    final entries = await _database.getEntriesForEviction();

    for (final entry in entries) {
      if (_cachedTotalSize <= limitBytes) break;

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
      _cachedTotalSize -= entry.size;
    }

    print('[CacheManager] Eviction complete. New size: ${_formatBytes(_cachedTotalSize)}');
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

    // Clear memory cache
    _artworkPathCache.clear();

    _cacheUpdateController.add(null);
    print('[CacheManager] All cache cleared');
  }

  /// Clear artwork cache only
  Future<void> clearArtworkCache() async {
    await _ensureInitialized();

    await _clearDirectory(_artworkCachePath!);
    await _database.clearEntriesByType(CacheType.artwork);

    // Clear memory cache
    _artworkPathCache.clear();

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

  /// Pre-populate the in-memory artwork path cache from database
  /// This ensures getArtworkPathSync() returns instantly on subsequent app opens
  Future<void> _prePopulateArtworkPathCache() async {
    final entries = await _database.getEntriesByType(CacheType.artwork);
    int populated = 0;
    for (final entry in entries) {
      if (await File(entry.path).exists()) {
        _artworkPathCache[entry.id] = entry.path;
        populated++;
      }
    }
    if (populated > 0) {
      print('[CacheManager] Pre-populated $populated artwork paths into memory cache');
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
    // User-initiated, run immediately (not debounced)
    await _enforceStorageLimitActual();
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
    _enforceLimitTimer?.cancel();
    _cacheUpdateController.close();
  }
}







