import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../database/cache_database.dart';
import '../../models/cache_entry.dart';
import '../api/connection_service.dart';
import '../media/media_request_scheduler.dart';

class CacheUpdateEvent {
  const CacheUpdateEvent({
    this.type,
    this.cleared = false,
  });

  final CacheType? type;
  final bool cleared;

  bool get affectsSongCache =>
      cleared || type == null || type == CacheType.song;
}

/// Manages caching of artwork and songs with LRU eviction
class CacheManager {
  // Singleton pattern
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  late CacheDatabase _database;
  late Dio _dio;
  final ConnectionService _connectionService = ConnectionService();
  final MediaRequestScheduler _mediaRequestScheduler = MediaRequestScheduler();

  bool _initialized = false;
  String? _artworkCachePath;
  String? _songCachePath;

  // Track ongoing cache operations to avoid duplicates
  final Map<String, Future<String?>> _inFlightArtworkRequests = {};
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

  // In-memory tracking of song cache size for strict song-only limit
  int _cachedSongSize = 0;
  bool _songCacheSizeInitialized = false;

  // Stream controller for cache updates
  final StreamController<CacheUpdateEvent> _cacheUpdateController =
      StreamController<CacheUpdateEvent>.broadcast();

  /// Stream notifying when cache is updated
  Stream<CacheUpdateEvent> get cacheUpdateStream =>
      _cacheUpdateController.stream;

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

    // Repair sparse metadata in the background on migrated installs without
    // blocking startup. This keeps thumbnail lookups resilient if legacy files
    // exist but metadata was only partially imported.
    unawaited(_repairArtworkMetadataFromDiskIfNeeded());
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
  Future<String?> cacheArtwork(
    String albumId,
    String artworkUrl, {
    MediaRequestPriority priority = MediaRequestPriority.background,
    MediaRequestCancellationToken? cancellationToken,
  }) async {
    return _mediaRequestScheduler.enqueueArtwork<String>(
      priority: priority,
      cancellationToken: cancellationToken,
      task: () => _cacheArtworkDirect(
        albumId,
        artworkUrl,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<String?> _cacheArtworkDirect(
    String albumId,
    String artworkUrl, {
    MediaRequestCancellationToken? cancellationToken,
  }) async {
    await _ensureInitialized();

    if (!_database.isCacheEnabled()) return null;
    if (cancellationToken?.isCancelled ?? false) return null;

    // Check memory cache first (instant, no DB query needed)
    // This is usually already checked by CachedArtwork widget, but double-check here
    if (_artworkPathCache.containsKey(albumId)) {
      return _artworkPathCache[albumId];
    }

    // Share existing in-flight request so duplicate callers receive the same
    // outcome instead of failing fast with null.
    final inFlightRequest = _inFlightArtworkRequests[albumId];
    if (inFlightRequest != null) {
      return _awaitInFlightArtworkRequest(
        inFlightRequest,
        cancellationToken: cancellationToken,
      );
    }

    final requestCompleter = Completer<String?>();
    _inFlightArtworkRequests[albumId] = requestCompleter.future;
    var acquiredSlot = false;
    String? result;

    // Wait for a download slot (limits concurrent network requests)
    try {
      acquiredSlot = await _acquireArtworkSlot();
      if (!acquiredSlot) {
        return null;
      }
      if (cancellationToken?.isCancelled ?? false) {
        return null;
      }

      final filePath = '$_artworkCachePath/$albumId.jpg';

      // Download artwork
      // Timeout reduced to 15s - thumbnails are ~2.8KB, even full images are <500KB
      // On slow connections, if 15s isn't enough, network is likely too slow for streaming
      final dioCancelToken = CancelToken();
      cancellationToken?.onCancel(() {
        if (!dioCancelToken.isCancelled) {
          dioCancelToken.cancel('artwork_request_cancelled');
        }
      });

      await _dio.download(
        artworkUrl,
        filePath,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
          headers: _connectionService.authHeaders,
        ),
        cancelToken: dioCancelToken,
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

      // Save entry (artwork is not constrained by the song cache limit)
      await _database.upsertCacheEntry(entry);

      _cacheUpdateController.add(
        const CacheUpdateEvent(type: CacheType.artwork),
      );

      // Store in memory cache for future instant lookups
      _artworkPathCache[albumId] = filePath;

      print(
          '[CacheManager] Cached artwork: $albumId (${entry.getFormattedSize()})');
      result = filePath;
      return result;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return null;
      }
      print('[CacheManager] Failed to cache artwork $albumId: $e');
      return null;
    } catch (e) {
      print('[CacheManager] Failed to cache artwork $albumId: $e');
      return null;
    } finally {
      if (!requestCompleter.isCompleted) {
        requestCompleter.complete(result);
      }
      _inFlightArtworkRequests.remove(albumId);
      if (acquiredSlot) {
        _releaseArtworkSlot();
      }
    }
  }

  Future<String?> _awaitInFlightArtworkRequest(
    Future<String?> request, {
    MediaRequestCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken == null) {
      return request;
    }
    if (cancellationToken.isCancelled) {
      return null;
    }

    final cancellationCompleter = Completer<String?>();
    cancellationToken.onCancel(() {
      if (!cancellationCompleter.isCompleted) {
        cancellationCompleter.complete(null);
      }
    });

    final result = await Future.any<String?>(
      <Future<String?>>[
        request,
        cancellationCompleter.future,
      ],
    );

    if (!cancellationCompleter.isCompleted) {
      cancellationCompleter.complete(result);
    }
    return result;
  }

  /// Store artwork from local bytes (e.g. extracted from a downloaded audio file).
  /// Does not use the network artwork download queue or concurrency slots.
  Future<String?> cacheArtworkFromBytes(
      String cacheKey, List<int> bytes) async {
    await _ensureInitialized();

    if (!_database.isCacheEnabled()) return null;
    if (bytes.isEmpty) return null;

    try {
      final filePath = '$_artworkCachePath/$cacheKey.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      final size = await file.length();

      final entry = CacheEntry(
        id: cacheKey,
        type: CacheType.artwork,
        path: filePath,
        size: size,
        lastAccessed: DateTime.now(),
      );

      await _database.upsertCacheEntry(entry);

      _cacheUpdateController.add(
        const CacheUpdateEvent(type: CacheType.artwork),
      );

      _artworkPathCache[cacheKey] = filePath;

      print(
          '[CacheManager] Cached artwork from bytes: $cacheKey (${entry.getFormattedSize()})');
      return filePath;
    } catch (e) {
      print('[CacheManager] Failed to cache artwork from bytes $cacheKey: $e');
      return null;
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
  Future<String?> getArtworkPathWithFallback(
      String primaryKey, String? fallbackKey) async {
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
    final primaryEntry =
        await _database.getCacheEntry(primaryKey, CacheType.artwork);
    if (primaryEntry != null && await File(primaryEntry.path).exists()) {
      await _database.touchCacheEntry(primaryKey, CacheType.artwork);
      _artworkPathCache[primaryKey] = primaryEntry.path;
      return primaryEntry.path;
    }

    // 4. Check disk cache for fallback key
    if (fallbackKey != null) {
      final fallbackEntry =
          await _database.getCacheEntry(fallbackKey, CacheType.artwork);
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

    await _ensureSongCacheCapacityForIncoming(incomingBytes: 0);

    _pendingSongs.add(songId);

    // Start background download (don't await)
    _downloadSongInBackground(songId, downloadUrl);

    return true;
  }

  /// Background song download
  Future<void> _downloadSongInBackground(
      String songId, String downloadUrl) async {
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
          headers: _connectionService.authHeaders,
        ),
      );

      // Get file size
      final file = File(filePath);
      final size = await file.length();
      final canStore =
          await _ensureSongCacheCapacityForIncoming(incomingBytes: size);
      if (!canStore) {
        await file.delete();
        print(
            '[CacheManager] Skipping song cache for $songId: file too large for current limit');
        return;
      }

      // Create cache entry
      final entry = CacheEntry(
        id: songId,
        type: CacheType.song,
        path: filePath,
        size: size,
        lastAccessed: DateTime.now(),
      );

      // Save entry and update song-size tracking
      await _database.upsertCacheEntry(entry);
      _cachedSongSize += size;
      _songCacheSizeInitialized = true;

      _cacheUpdateController.add(
        const CacheUpdateEvent(type: CacheType.song),
      );

      print(
          '[CacheManager] Cached song: $songId (${entry.getFormattedSize()})');
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

  Future<void> _initializeSongCacheSizeIfNeeded() async {
    if (_songCacheSizeInitialized) return;
    _cachedSongSize = await _database.getCacheSizeByType(CacheType.song);
    _songCacheSizeInitialized = true;
  }

  Future<bool> _ensureSongCacheCapacityForIncoming({
    required int incomingBytes,
  }) async {
    await _initializeSongCacheSizeIfNeeded();

    final limitBytes = _database.getCacheLimitBytes();
    if (incomingBytes > limitBytes) {
      return false;
    }
    if (_cachedSongSize + incomingBytes <= limitBytes) {
      return true;
    }

    print(
        '[CacheManager] Song cache limit exceeded: ${_formatBytes(_cachedSongSize + incomingBytes)} / ${_formatBytes(limitBytes)}');
    print('[CacheManager] Starting song-cache LRU eviction...');

    final entries = await _database.getEntriesByType(CacheType.song);
    var evictedCount = 0;

    for (final entry in entries) {
      if (_cachedSongSize + incomingBytes <= limitBytes) break;

      var canRemoveEntry = false;
      try {
        final file = File(entry.path);
        if (await file.exists()) {
          await file.delete();
          print('[CacheManager] Evicted song cache: ${entry.id}');
          canRemoveEntry = true;
        } else {
          canRemoveEntry = true;
        }
      } catch (e) {
        print('[CacheManager] Failed to delete song cache file: ${entry.path}');
      }
      if (!canRemoveEntry) {
        continue;
      }

      await _database.removeCacheEntry(entry.id, CacheType.song);
      _cachedSongSize -= entry.size;
      if (_cachedSongSize < 0) {
        _cachedSongSize = 0;
      }
      evictedCount++;
    }

    if (evictedCount > 0) {
      _cacheUpdateController.add(const CacheUpdateEvent(type: CacheType.song));
    }

    final fits = _cachedSongSize + incomingBytes <= limitBytes;
    if (!fits) {
      print(
          '[CacheManager] Unable to free enough song cache space (needed ${_formatBytes(incomingBytes)})');
    }
    return fits;
  }

  /// Actually enforce storage limit using LRU eviction
  /// Applies only to song cache entries; artwork is unmanaged by this limit.
  Future<void> _enforceStorageLimitActual() async {
    await _ensureSongCacheCapacityForIncoming(incomingBytes: 0);
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
    _cachedSongSize = 0;
    _songCacheSizeInitialized = true;

    _cacheUpdateController.add(const CacheUpdateEvent(cleared: true));
    print('[CacheManager] All cache cleared');
  }

  /// Clear artwork cache only
  Future<void> clearArtworkCache() async {
    await _ensureInitialized();

    await _clearDirectory(_artworkCachePath!);
    await _database.clearEntriesByType(CacheType.artwork);

    // Clear memory cache
    _artworkPathCache.clear();

    _cacheUpdateController.add(
      const CacheUpdateEvent(type: CacheType.artwork),
    );
    print('[CacheManager] Artwork cache cleared');
  }

  /// Clear song cache only
  Future<void> clearSongCache() async {
    await _ensureInitialized();

    await _clearDirectory(_songCachePath!);
    await _database.clearEntriesByType(CacheType.song);
    _cachedSongSize = 0;
    _songCacheSizeInitialized = true;

    _cacheUpdateController.add(
      const CacheUpdateEvent(type: CacheType.song),
    );
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
      print(
          '[CacheManager] Pre-populated $populated artwork paths into memory cache');
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
      if (_songCacheSizeInitialized && entry.type == CacheType.song) {
        _cachedSongSize -= entry.size;
        if (_cachedSongSize < 0) {
          _cachedSongSize = 0;
        }
      }
    }

    if (orphaned.isNotEmpty) {
      print('[CacheManager] Cleaned up ${orphaned.length} orphaned entries');
    }
  }

  /// Opportunistically reindex artwork files that exist on disk but are
  /// missing from the metadata database (common after interrupted migrations).
  ///
  /// Runs in the background and yields periodically to avoid startup jank.
  Future<void> _repairArtworkMetadataFromDiskIfNeeded() async {
    try {
      final artworkPath = _artworkCachePath;
      if (artworkPath == null || artworkPath.isEmpty) {
        return;
      }

      final artworkDir = Directory(artworkPath);
      if (!await artworkDir.exists()) {
        return;
      }

      final artworkFiles = <File>[];
      await for (final entity in artworkDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.jpg')) {
          artworkFiles.add(entity);
        }
      }
      if (artworkFiles.isEmpty) {
        return;
      }

      final dbArtworkCount =
          await _database.getCacheCountByType(CacheType.artwork);
      if (dbArtworkCount >= artworkFiles.length) {
        return;
      }

      final knownIds = (await _database.getEntriesByType(CacheType.artwork))
          .map((entry) => entry.id)
          .toSet();

      const batchSize = 200;
      var scanned = 0;
      var reindexed = 0;
      for (final file in artworkFiles) {
        scanned++;
        final segments = file.uri.pathSegments;
        final fileName = segments.isEmpty ? '' : segments.last;
        if (!fileName.toLowerCase().endsWith('.jpg') || fileName.length <= 4) {
          continue;
        }
        final cacheKey = fileName.substring(0, fileName.length - 4);
        if (cacheKey.isEmpty || knownIds.contains(cacheKey)) {
          continue;
        }

        try {
          final stat = await file.stat();
          final timestamp = stat.modified.millisecondsSinceEpoch > 0
              ? stat.modified
              : DateTime.now();
          final entry = CacheEntry(
            id: cacheKey,
            type: CacheType.artwork,
            path: file.path,
            size: stat.size,
            lastAccessed: timestamp,
            createdAt: timestamp,
          );
          await _database.upsertCacheEntry(entry);
          _artworkPathCache[cacheKey] = file.path;
          knownIds.add(cacheKey);
          reindexed++;
        } catch (_) {
          // Ignore unreadable files and continue repairing.
        }

        if (scanned % batchSize == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
      }

      if (reindexed > 0) {
        print(
            '[CacheManager] Reindexed $reindexed artwork metadata entries from disk');
      }
    } catch (e) {
      print('[CacheManager] Artwork metadata repair skipped: $e');
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
    try {
      _dio.close(force: true);
    } catch (_) {
      // Safe to ignore when dispose is called before initialization.
    }
    _cacheUpdateController.close();
  }

  /// Reset singleton state for deterministic test teardown.
  ///
  /// This closes open database/network resources and clears in-memory queues so
  /// widget tests can exit cleanly without lingering async handles.
  Future<void> resetForTests() async {
    for (final waiter in _artworkDownloadQueue) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _artworkDownloadQueue.clear();
    _activeArtworkDownloads = 0;

    _inFlightArtworkRequests.clear();
    _pendingSongs.clear();
    _artworkPathCache.clear();
    _cachedSongSize = 0;
    _songCacheSizeInitialized = false;

    try {
      _dio.close(force: true);
    } catch (_) {
      // Safe to ignore when reset is called before initialization.
    }

    if (_initialized) {
      await _database.close();
    }
    _initialized = false;
    _artworkCachePath = null;
    _songCachePath = null;
  }
}
