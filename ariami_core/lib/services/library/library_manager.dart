import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/scan_diagnostics.dart';
import 'package:ariami_core/models/music_availability.dart';
import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/services/catalog/catalog_change_log.dart';
import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/catalog/catalog_writer.dart';
import 'package:ariami_core/services/library/album_identity.dart';
import 'package:ariami_core/services/library/change_processor.dart';
import 'package:ariami_core/services/library/folder_watcher.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';
import 'package:ariami_core/services/library/metadata_cache.dart';
import 'package:ariami_core/services/library/playlist_decision_store.dart';

part 'library_manager/library_manager_api.part.dart';
part 'library_manager/library_manager_availability.part.dart';
part 'library_manager/library_manager_catalog.part.dart';
part 'library_manager/library_manager_catalog_artwork.part.dart';
part 'library_manager/library_manager_catalog_records.part.dart';
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

  V? operator [](K key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  void operator []=(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    _cache[key] = value;
    while (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Check if key exists without updating access order
  bool containsKey(K key) => _cache.containsKey(key);

  void clear() => _cache.clear();

  int get length => _cache.length;
}

/// Singleton service that manages the music library
/// Scans the music folder and provides library data to HTTP server
class LibraryManager {
  static final LibraryManager _instance = LibraryManager._internal();
  factory LibraryManager() => _instance;
  LibraryManager._internal();

  LibraryStructure? _library;
  DateTime? _lastScanTime;
  bool _isScanning = false;
  MusicAvailability _musicAvailability = MusicAvailability.unknown;
  String? _configuredFolderPath;
  Timer? _availabilityTimer;
  Future<void>? _storageProbe;
  String? _storageProbeFolder;
  final Set<String> _unavailableProbePaths = <String>{};
  bool _availabilityCheckInFlight = false;
  int _scanGeneration = 0;

  MusicAvailability get musicAvailability => _musicAvailability;

  /// Recheck storage and rescan after recovery. Also used by manual refresh.
  Future<void> checkMusicAvailability() => _checkMusicAvailabilityImpl();

  void stopMusicAvailabilityMonitoring() {
    _availabilityTimer?.cancel();
    _availabilityTimer = null;
    _scanGeneration++;
  }

  void resumeMusicAvailabilityMonitoring() {
    final folderPath = _configuredFolderPath;
    if (folderPath != null) _monitorMusicFolder(folderPath);
  }

  MetadataCache? _metadataCache;

  /// Persistent catalog database for v2 incremental sync.
  CatalogDatabase? _catalogDatabase;
  CatalogWriter? _catalogWriter;
  int _latestCatalogToken = 0;

  final FolderWatcher _folderWatcher = FolderWatcher();
  final ChangeProcessor _changeProcessor = ChangeProcessor();
  StreamSubscription<List<FileChange>>? _folderChangeSubscription;
  Future<void> _folderChangePipeline = Future<void>.value();
  String? _watchedFolderPath;

  /// O(1) lookup indexes for stream/ticket hot paths.
  final Map<String, SongMetadata> _songById = {};
  final Map<String, String> _songPathById = {};
  final Map<String, String?> _songAlbumIdById = {};

  /// Cache for lazily extracted album artwork (LRU, max 50 albums ~25MB)
  final LruCache<String, List<int>?> _artworkCache = LruCache(50);

  /// Cache for lazily extracted song durations (LRU, max 2000 songs ~16KB)
  final LruCache<String, int?> _durationCache = LruCache(2000);

  /// Cache for lazily extracted song artwork for standalone songs (LRU, max 100 ~50MB)
  final LruCache<String, List<int>?> _songArtworkCache = LruCache(100);

  final MetadataExtractor _metadataExtractor = MetadataExtractor();

  ArtworkService? _artworkPrecomputeService;

  final List<void Function()> _onScanCompleteCallbacks = [];

  final List<void Function()> _onDurationsReadyCallbacks = [];

  bool _durationsReady = true;

  /// Feature flags controlling catalog writes and artwork precompute.
  AriamiFeatureFlags _featureFlags = const AriamiFeatureFlags();

  ScanDiagnostics _latestScanDiagnostics = const ScanDiagnostics();

  /// Total audio files discovered and attempted by the latest full scan.
  int _latestScannedFileCount = 0;

  /// Persistent playlist-suggestion decisions (import/ignore per folder).
  PlaylistDecisionStore? _playlistDecisionStore;

  /// Folder path of the most recent successful full scan (for rescans
  /// triggered outside the setup callbacks, e.g. suggestion imports).
  String? _lastScannedFolderPath;

  LibraryStructure? get library => _library;

  /// Replaces the in-memory library in tests and rebuilds derived indexes.
  void setLibraryForTesting(LibraryStructure? library) {
    _library = library;
    _rebuildSongIndexes();
  }

  void addScanCompleteListener(void Function() callback) {
    _onScanCompleteCallbacks.add(callback);
  }

  void removeScanCompleteListener(void Function() callback) {
    _onScanCompleteCallbacks.remove(callback);
  }

  void _notifyScanComplete() {
    for (final callback in _onScanCompleteCallbacks) {
      callback();
    }
  }

  void addDurationsReadyListener(void Function() callback) {
    _onDurationsReadyCallbacks.add(callback);
  }

  DateTime? get lastScanTime => _lastScanTime;

  bool get isScanning => _isScanning;

  bool get durationsReady => _durationsReady;

  ScanDiagnostics get latestScanDiagnostics => _latestScanDiagnostics;

  int get latestScannedFileCount => _latestScannedFileCount;

  /// Playlist-suggestion decision store (null until [setCachePath]).
  PlaylistDecisionStore? get playlistDecisionStore => _playlistDecisionStore;

  /// Suggestions from the last scan that the user has not yet imported or
  /// ignored.
  ///
  /// A fresh decision hides its suggestion immediately, even though the
  /// decided folder stays in the last scan's diagnostics until a rescan.
  Future<List<PlaylistSuggestion>> pendingPlaylistSuggestions() async {
    var decidedPaths = const <String>{};
    final store = _playlistDecisionStore;
    if (store != null) {
      await store.ensureLoaded();
      decidedPaths = {
        ...store.importedFolderPaths,
        ...store.ignoredFolderPaths,
      };
    }
    return _latestScanDiagnostics.playlistSuggestions
        .where((s) => !decidedPaths.contains(path.normalize(s.folderPath)))
        .toList(growable: false);
  }

  String? get lastScannedFolderPath => _lastScannedFolderPath;

  /// Latest token written to `library_changes`.
  int get latestToken => _latestCatalogToken;

  void setFeatureFlags(AriamiFeatureFlags flags) {
    _featureFlags = flags;
  }

  bool get _shouldWriteCatalog =>
      _featureFlags.enableCatalogWrite || _featureFlags.enableV2Api;

  bool get _shouldReadCatalog =>
      _featureFlags.enableCatalogRead || _featureFlags.enableV2Api;

  bool get _shouldPrecomputeArtwork => _featureFlags.enableArtworkPrecompute;

  void _rebuildSongIndexes() {
    _songById.clear();
    _songPathById.clear();
    _songAlbumIdById.clear();

    final library = _library;
    if (library == null) return;

    for (final album in library.albums.values) {
      for (final song in album.songs) {
        final songId = generateSongId(song.filePath);
        _songById[songId] = song;
        _songPathById[songId] = song.filePath;
        _songAlbumIdById[songId] = album.id;
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = generateSongId(song.filePath);
      _songById[songId] = song;
      _songPathById[songId] = song.filePath;
      _songAlbumIdById[songId] = null;
    }
  }

  /// Creates a catalog repository instance when catalog DB is initialized.
  /// Returns null if catalog persistence is not available yet.
  CatalogRepository? createCatalogRepository() {
    if (!_shouldReadCatalog && !_shouldWriteCatalog) {
      return null;
    }

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

    final decisionsPath =
        path.join(path.dirname(cachePath), 'playlist_decisions.json');
    if (_playlistDecisionStore?.filePath != decisionsPath) {
      _playlistDecisionStore = PlaylistDecisionStore(filePath: decisionsPath);
    }
    print('[LibraryManager] Playlist decision store path set: $decisionsPath');

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

  /// Scan the music folder and build library structure
  ///
  /// This runs in a background isolate to prevent UI blocking.
  /// Progress updates are logged and the scan complete callback is fired when done.
  Future<void> scanMusicFolder(
    String folderPath, {
    void Function(String stage, String message, double percentage)? onProgress,
  }) =>
      _scanMusicFolderImpl(folderPath, onProgress: onProgress);

  Map<String, dynamic> toApiJson(String baseUrl) => _toApiJsonImpl(baseUrl);

  Future<Map<String, dynamic>?> getAlbumDetail(
          String albumId, String baseUrl) =>
      _getAlbumDetailImpl(albumId, baseUrl);

  String? getSongFilePath(String songId) => _getSongFilePathImpl(songId);

  /// Get album ID for a song by song ID.
  ///
  /// Returns:
  /// - album ID when song belongs to an album
  /// - null for standalone songs or if song is not found
  String? getSongAlbumId(String songId) => _getSongAlbumIdImpl(songId);

  Future<List<int>?> getAlbumArtwork(String albumId) =>
      _getAlbumArtworkImpl(albumId);

  Future<int?> getSongDuration(String songId) => _getSongDurationImpl(songId);

  /// Get known song duration by song ID without triggering extraction.
  ///
  /// Returns a cached or already-indexed duration when available, otherwise null.
  int? getKnownSongDuration(String songId) => _getKnownSongDurationImpl(songId);

  /// Get known song bitrate by song ID without triggering extraction.
  int? getKnownSongBitrate(String songId) => _getKnownSongBitrateImpl(songId);

  /// Get song artwork by song ID (lazy extraction with caching)
  /// Used for standalone songs that don't belong to an album
  Future<List<int>?> getSongArtwork(String songId) =>
      _getSongArtworkImpl(songId);

  void clear() => _clearImpl();
}
