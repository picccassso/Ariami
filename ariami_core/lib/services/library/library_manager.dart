import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/catalog/catalog_writer.dart';
import 'package:ariami_core/services/library/change_processor.dart';
import 'package:ariami_core/services/library/folder_watcher.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';
import 'package:ariami_core/services/library/metadata_cache.dart';
import 'package:sqlite3/sqlite3.dart';

part 'library_manager/library_manager_api.part.dart';
part 'library_manager/library_manager_catalog.part.dart';
part 'library_manager/library_manager_duration.part.dart';
part 'library_manager/library_manager_scanning.part.dart';

/// Simple LRU (Least Recently Used) cache implementation
///
/// Uses LinkedHashMap with access-order to track usage.
/// Evicts least recently used entries when capacity is exceeded.
class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  LruCache(this.maxSize);

  /// Get a value from the cache, updating its access order
  V? operator [](K key) {
    if (!_cache.containsKey(key)) return null;
    // Move to end (most recently used) by removing and re-adding
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  /// Put a value in the cache, evicting oldest if necessary
  void operator []=(K key, V value) {
    // If key exists, remove it first (will be re-added at end)
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    _cache[key] = value;
    // Evict oldest entries if over capacity
    while (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Check if key exists without updating access order
  bool containsKey(K key) => _cache.containsKey(key);

  /// Clear all entries
  void clear() => _cache.clear();

  /// Current number of entries
  int get length => _cache.length;
}

/// Singleton service that manages the music library
/// Scans the music folder and provides library data to HTTP server
class LibraryManager {
  // Singleton pattern
  static final LibraryManager _instance = LibraryManager._internal();
  factory LibraryManager() => _instance;
  LibraryManager._internal();

  LibraryStructure? _library;
  DateTime? _lastScanTime;
  bool _isScanning = false;

  /// Persistent metadata cache for fast re-scans
  MetadataCache? _metadataCache;

  /// Persistent catalog database for v2 incremental sync.
  CatalogDatabase? _catalogDatabase;
  CatalogWriter? _catalogWriter;
  int _latestCatalogToken = 0;

  /// Real-time file watcher change pipeline.
  final FolderWatcher _folderWatcher = FolderWatcher();
  final ChangeProcessor _changeProcessor = ChangeProcessor();
  StreamSubscription<List<FileChange>>? _folderChangeSubscription;
  Future<void> _folderChangePipeline = Future<void>.value();
  String? _watchedFolderPath;

  /// Cache for lazily extracted album artwork (LRU, max 50 albums ~25MB)
  final LruCache<String, List<int>?> _artworkCache = LruCache(50);

  /// Cache for lazily extracted song durations (LRU, max 2000 songs ~16KB)
  final LruCache<String, int?> _durationCache = LruCache(2000);

  /// Cache for lazily extracted song artwork for standalone songs (LRU, max 100 ~50MB)
  final LruCache<String, List<int>?> _songArtworkCache = LruCache(100);

  /// Metadata extractor instance for lazy extraction
  final MetadataExtractor _metadataExtractor = MetadataExtractor();

  /// Artwork service for precomputing and caching resized variants at scan time.
  ArtworkService? _artworkPrecomputeService;

  /// Callbacks to notify when library scan completes
  final List<void Function()> _onScanCompleteCallbacks = [];

  /// Callbacks to notify when duration warm-up completes
  final List<void Function()> _onDurationsReadyCallbacks = [];

  /// Whether duration warm-up is running
  bool _durationWarmupRunning = false;

  /// Whether durations are ready for the current library snapshot
  bool _durationsReady = true;

  /// Get the current library structure
  LibraryStructure? get library => _library;

  /// Register a callback to be notified when scan completes
  void addScanCompleteListener(void Function() callback) {
    _onScanCompleteCallbacks.add(callback);
  }

  /// Remove a scan complete listener
  void removeScanCompleteListener(void Function() callback) {
    _onScanCompleteCallbacks.remove(callback);
  }

  /// Notify all listeners that scan is complete
  void _notifyScanComplete() {
    for (final callback in _onScanCompleteCallbacks) {
      callback();
    }
  }

  /// Register a callback to be notified when duration warm-up completes
  void addDurationsReadyListener(void Function() callback) {
    _onDurationsReadyCallbacks.add(callback);
  }

  /// Remove a duration warm-up listener
  void removeDurationsReadyListener(void Function() callback) {
    _onDurationsReadyCallbacks.remove(callback);
  }

  /// Notify all listeners that durations are ready
  void _notifyDurationsReady() {
    for (final callback in _onDurationsReadyCallbacks) {
      callback();
    }
  }

  /// Get the last scan timestamp
  DateTime? get lastScanTime => _lastScanTime;

  /// Check if currently scanning
  bool get isScanning => _isScanning;

  /// Whether durations are ready for the current library snapshot
  bool get durationsReady => _durationsReady;

  /// Whether duration warm-up is currently running
  bool get isDurationWarmupRunning => _durationWarmupRunning;

  /// Latest token written to `library_changes`.
  int get latestToken => _latestCatalogToken;

  /// Creates a catalog repository instance when catalog DB is initialized.
  /// Returns null if catalog persistence is not available yet.
  CatalogRepository? createCatalogRepository() {
    final catalogDatabase = _catalogDatabase;
    if (catalogDatabase == null || !catalogDatabase.isInitialized) {
      return null;
    }

    return CatalogRepository(database: catalogDatabase.database);
  }

  /// Set the path for persistent metadata cache
  ///
  /// Call this before scanning to enable cache. Path should be in a
  /// writable config directory (e.g., ~/.ariami_cli/ or app data).
  void setCachePath(String cachePath) {
    _metadataCache = MetadataCache(cachePath);
    print('[LibraryManager] Metadata cache path set: $cachePath');

    final artworkCachePath =
        path.join(path.dirname(cachePath), 'artwork_cache');
    _artworkPrecomputeService = ArtworkService(
      cacheDirectory: artworkCachePath,
      maxCacheSizeMB: 256,
    );
    print(
        '[LibraryManager] Artwork precompute cache path set: $artworkCachePath');

    final catalogPath = path.join(path.dirname(cachePath), 'catalog.db');
    try {
      _catalogDatabase?.close();
      final catalogDatabase = CatalogDatabase(databasePath: catalogPath);
      catalogDatabase.initialize();
      _catalogDatabase = catalogDatabase;
      _catalogWriter = CatalogWriter(database: catalogDatabase.database);
      _latestCatalogToken = _catalogWriter!.latestToken;
      print('[LibraryManager] Catalog database path set: $catalogPath');
      print('[LibraryManager] Catalog latest token: $_latestCatalogToken');
    } catch (e) {
      _catalogDatabase = null;
      _catalogWriter = null;
      _latestCatalogToken = 0;
      print('[LibraryManager] WARNING: Failed to initialize catalog DB: $e');
    }
  }

  /// Force clear the metadata cache (for "Force Rescan" feature)
  Future<void> clearMetadataCache() => this._clearMetadataCacheImpl();

  /// Scan the music folder and build library structure
  ///
  /// This runs in a background isolate to prevent UI blocking.
  /// Progress updates are logged and the scan complete callback is fired when done.
  Future<void> scanMusicFolder(String folderPath) =>
      this._scanMusicFolderImpl(folderPath);

  /// Convert library to API JSON format for mobile app
  Map<String, dynamic> toApiJson(String baseUrl) =>
      this._toApiJsonImpl(baseUrl);

  /// Convert library to API JSON format with lazy duration extraction for songs
  Future<Map<String, dynamic>> toApiJsonWithDurations(String baseUrl) =>
      this._toApiJsonWithDurationsImpl(baseUrl);

  void ensureDurationWarmup() => this._ensureDurationWarmupImpl();

  /// Get detailed album information with songs
  Future<Map<String, dynamic>?> getAlbumDetail(
          String albumId, String baseUrl) =>
      this._getAlbumDetailImpl(albumId, baseUrl);

  /// Get song file path by song ID
  String? getSongFilePath(String songId) => this._getSongFilePathImpl(songId);

  /// Get album ID for a song by song ID.
  ///
  /// Returns:
  /// - album ID when song belongs to an album
  /// - null for standalone songs or if song is not found
  String? getSongAlbumId(String songId) => this._getSongAlbumIdImpl(songId);

  /// Get album artwork by album ID (lazy extraction with caching)
  Future<List<int>?> getAlbumArtwork(String albumId) =>
      this._getAlbumArtworkImpl(albumId);

  /// Get song duration by song ID (lazy extraction with caching)
  Future<int?> getSongDuration(String songId) =>
      this._getSongDurationImpl(songId);

  /// Get song artwork by song ID (lazy extraction with caching)
  /// Used for standalone songs that don't belong to an album
  Future<List<int>?> getSongArtwork(String songId) =>
      this._getSongArtworkImpl(songId);

  /// Clear library data
  void clear() => this._clearImpl();
}
