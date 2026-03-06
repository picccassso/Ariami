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

    final artworkCachePath = path.join(path.dirname(cachePath), 'artwork_cache');
    _artworkPrecomputeService = ArtworkService(
      cacheDirectory: artworkCachePath,
      maxCacheSizeMB: 256,
    );
    print('[LibraryManager] Artwork precompute cache path set: $artworkCachePath');

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

  void _markDurationsDirty() {
    _durationsReady = false;
    _durationWarmupRunning = false;
    _durationCache.clear();
  }

  /// Force clear the metadata cache (for "Force Rescan" feature)
  Future<void> clearMetadataCache() async {
    if (_metadataCache != null) {
      await _metadataCache!.clear();
      print('[LibraryManager] Metadata cache cleared');
    }
  }

  Future<void> _writeCatalogSnapshot() async {
    final library = _library;
    final catalogWriter = _catalogWriter;
    if (library == null || catalogWriter == null) {
      return;
    }

    try {
      final result = catalogWriter.writeFullSnapshot(
        library: library,
        songIdForPath: _generateSongId,
      );
      _latestCatalogToken = result.latestToken;
      print('[LibraryManager] Catalog snapshot write complete '
          '(albums: +${result.upsertedAlbumCount}/-${result.deletedAlbumCount}, '
          'songs: +${result.upsertedSongCount}/-${result.deletedSongCount}, '
          'latestToken: ${result.latestToken})');

      await _precomputeAndPersistArtworkVariantsForAlbums(
        library: library,
        albumIds: library.albums.values.where((album) => album.isValid).map(
              (album) => album.id,
            ),
      );
    } catch (e, stackTrace) {
      print('[LibraryManager] WARNING: Failed to write catalog snapshot: $e');
      print('[LibraryManager] Catalog snapshot stack trace: $stackTrace');
    }
  }

  void _startWatchingFolder(String folderPath) {
    if (_watchedFolderPath == folderPath && _folderChangeSubscription != null) {
      return;
    }

    _stopWatchingFolder();
    _folderChangeSubscription = _folderWatcher.changes.listen(
      (changes) {
        _folderChangePipeline = _folderChangePipeline
            .then((_) => _handleBatchedFileChanges(changes))
            .catchError((error, stackTrace) {
          print('[LibraryManager] WARNING: Folder change pipeline error: $error');
          print('[LibraryManager] Folder change stack trace: $stackTrace');
        });
      },
      onError: (error) {
        print('[LibraryManager] ERROR: Folder watcher stream error: $error');
      },
    );
    _folderWatcher.startWatching(folderPath);
    _watchedFolderPath = folderPath;
  }

  void _stopWatchingFolder() {
    _folderChangeSubscription?.cancel();
    _folderChangeSubscription = null;
    _folderWatcher.stopWatching();
    _watchedFolderPath = null;
  }

  Future<void> _handleBatchedFileChanges(List<FileChange> changes) async {
    final currentLibrary = _library;
    if (currentLibrary == null || changes.isEmpty) {
      return;
    }

    if (_isScanning) {
      return;
    }

    try {
      final update =
          await _changeProcessor.processChanges(changes, currentLibrary);
      if (update.isEmpty) {
        return;
      }

      final updatedLibrary = await _changeProcessor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: changes,
      );
      _library = updatedLibrary;
      _lastScanTime = DateTime.now();
      _durationsReady = false;
      _durationWarmupRunning = false;

      await _writeCatalogBatchForChanges(
        update: update,
        previousLibrary: currentLibrary,
        updatedLibrary: updatedLibrary,
      );

      print('[LibraryManager] Applied file-change batch '
          '(added: ${update.addedSongIds.length}, '
          'removed: ${update.removedSongIds.length}, '
          'modified: ${update.modifiedSongIds.length}, '
          'affectedAlbums: ${update.affectedAlbumIds.length}, '
          'latestToken: $_latestCatalogToken)');

      _notifyScanComplete();
      unawaited(_startDurationWarmup());
    } catch (e, stackTrace) {
      print('[LibraryManager] ERROR applying file-change batch: $e');
      print('[LibraryManager] File-change stack trace: $stackTrace');
    }
  }

  Future<void> _writeCatalogBatchForChanges({
    required LibraryUpdate update,
    required LibraryStructure previousLibrary,
    required LibraryStructure updatedLibrary,
  }) async {
    final catalogDatabase = _catalogDatabase;
    if (catalogDatabase == null) {
      return;
    }

    final database = catalogDatabase.database;
    final repository = CatalogRepository(database: database);
    final songRecordsById = _buildCatalogSongRecordsById(updatedLibrary);
    final albumRecordsById = _buildCatalogAlbumRecordsById(updatedLibrary);
    final previousSongAlbumIds = _buildSongAlbumIdIndex(previousLibrary);
    final updatedSongAlbumIds = _buildSongAlbumIdIndex(updatedLibrary);

    final upsertSongIds = <String>{
      ...update.addedSongIds,
      ...update.modifiedSongIds,
    }..removeWhere((songId) => !songRecordsById.containsKey(songId));
    final deletedSongIds = <String>{...update.removedSongIds};

    final affectedAlbumIds = <String>{...update.affectedAlbumIds};
    for (final songId in upsertSongIds) {
      final previousAlbumId = previousSongAlbumIds[songId];
      final updatedAlbumId = updatedSongAlbumIds[songId];
      if (previousAlbumId != null) {
        affectedAlbumIds.add(previousAlbumId);
      }
      if (updatedAlbumId != null) {
        affectedAlbumIds.add(updatedAlbumId);
      }
    }
    for (final songId in deletedSongIds) {
      final previousAlbumId = previousSongAlbumIds[songId];
      if (previousAlbumId != null) {
        affectedAlbumIds.add(previousAlbumId);
      }
    }

    final orderedUpsertSongIds = upsertSongIds.toList()..sort();
    final orderedDeletedSongIds = deletedSongIds.toList()..sort();
    final orderedAffectedAlbumIds = affectedAlbumIds.toList()..sort();

    var tokenCursor = _readLatestTokenFromDatabase(database);
    final occurredEpochMs = DateTime.now().millisecondsSinceEpoch;

    database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final songId in orderedUpsertSongIds) {
        tokenCursor += 1;
        final record = songRecordsById[songId]!;
        repository.upsertSong(
          CatalogSongRecord(
            id: record.id,
            filePath: record.filePath,
            title: record.title,
            artist: record.artist,
            albumId: record.albumId,
            durationSeconds: record.durationSeconds,
            trackNumber: record.trackNumber,
            fileSizeBytes: record.fileSizeBytes,
            modifiedEpochMs: record.modifiedEpochMs,
            artworkKey: record.artworkKey,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'song',
          entityId: songId,
          op: 'upsert',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in orderedDeletedSongIds) {
        tokenCursor += 1;
        repository.softDeleteSong(songId, tokenCursor);
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'song',
          entityId: songId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in orderedAffectedAlbumIds) {
        tokenCursor += 1;
        final record = albumRecordsById[albumId];
        if (record != null) {
          repository.upsertAlbum(
            CatalogAlbumRecord(
              id: record.id,
              title: record.title,
              artist: record.artist,
              year: record.year,
              coverArtKey: record.coverArtKey,
              songCount: record.songCount,
              durationSeconds: record.durationSeconds,
              updatedToken: tokenCursor,
              isDeleted: false,
            ),
          );
          _insertLibraryChangeEvent(
            database: database,
            entityType: 'album',
            entityId: albumId,
            op: 'upsert',
            occurredEpochMs: occurredEpochMs,
          );
        } else {
          repository.softDeleteAlbum(albumId, tokenCursor);
          _insertLibraryChangeEvent(
            database: database,
            entityType: 'album',
            entityId: albumId,
            op: 'delete',
            occurredEpochMs: occurredEpochMs,
          );
        }
      }

      database.execute('COMMIT;');
      _latestCatalogToken = tokenCursor;
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }

    await _precomputeAndPersistArtworkVariantsForAlbums(
      library: updatedLibrary,
      albumIds: orderedAffectedAlbumIds,
    );
  }

  Future<void> _precomputeAndPersistArtworkVariantsForAlbums({
    required LibraryStructure library,
    required Iterable<String> albumIds,
  }) async {
    final catalogWriter = _catalogWriter;
    final artworkService = _artworkPrecomputeService;
    if (catalogWriter == null || artworkService == null) {
      return;
    }

    final orderedAlbumIds = albumIds.toSet().toList()..sort();
    for (final albumId in orderedAlbumIds) {
      final album = library.albums[albumId];
      if (album == null || !album.isValid) {
        continue;
      }

      try {
        final source = await _extractAlbumArtworkSource(album);
        if (source == null) {
          continue;
        }

        final fullEtag = _computeArtworkEtag(source.artworkBytes);
        final fullMimeType = _detectArtworkMimeType(source.artworkBytes);
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'full',
            mimeType: fullMimeType,
            byteSize: source.artworkBytes.length,
            etag: fullEtag,
            lastModifiedEpochMs: source.lastModifiedEpochMs,
            storagePath: source.referencePath,
            updatedToken: _latestCatalogToken,
          ),
        );

        final thumbnailBytes = await artworkService.precomputeArtworkVariant(
          album.id,
          source.artworkBytes,
          ArtworkSize.thumbnail,
        );
        final expectedThumbnailPath = artworkService.getVariantStoragePath(
          album.id,
          ArtworkSize.thumbnail,
          originalReferencePath: source.referencePath,
        );
        final thumbnailFile = File(expectedThumbnailPath);
        final thumbnailExists = await thumbnailFile.exists();
        final thumbnailStoragePath =
            thumbnailExists ? thumbnailFile.path : source.referencePath;
        final thumbnailLastModified = thumbnailExists
            ? (await thumbnailFile.stat()).modified.millisecondsSinceEpoch
            : source.lastModifiedEpochMs;
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'thumb_200',
            mimeType: _detectArtworkMimeType(thumbnailBytes),
            byteSize: thumbnailBytes.length,
            etag: _computeArtworkEtag(thumbnailBytes),
            lastModifiedEpochMs: thumbnailLastModified,
            storagePath: thumbnailStoragePath,
            updatedToken: _latestCatalogToken,
          ),
        );
      } catch (e) {
        print('[LibraryManager] WARNING: Failed artwork precompute for '
            'album $albumId: $e');
      }
    }
  }

  Future<_AlbumArtworkSource?> _extractAlbumArtworkSource(Album album) async {
    if (_artworkCache.containsKey(album.id)) {
      final cachedArtwork = _artworkCache[album.id];
      if (cachedArtwork == null) {
        return null;
      }

      final sourceSong = album.songs.isNotEmpty ? album.songs.first : null;
      if (sourceSong == null) {
        return null;
      }

      return _AlbumArtworkSource(
        artworkBytes: cachedArtwork,
        referencePath: sourceSong.filePath,
        lastModifiedEpochMs:
            sourceSong.modifiedTime?.millisecondsSinceEpoch ??
                DateTime.now().millisecondsSinceEpoch,
      );
    }

    for (final song in album.songs) {
      final artwork = await _metadataExtractor.extractArtwork(song.filePath);
      if (artwork != null) {
        _artworkCache[album.id] = artwork;
        return _AlbumArtworkSource(
          artworkBytes: artwork,
          referencePath: song.filePath,
          lastModifiedEpochMs:
              song.modifiedTime?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    _artworkCache[album.id] = null;
    return null;
  }

  String _computeArtworkEtag(List<int> artworkBytes) {
    return md5.convert(artworkBytes).toString();
  }

  String _detectArtworkMimeType(List<int> artworkBytes) {
    if (artworkBytes.length >= 3 &&
        artworkBytes[0] == 0xFF &&
        artworkBytes[1] == 0xD8 &&
        artworkBytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (artworkBytes.length >= 8 &&
        artworkBytes[0] == 0x89 &&
        artworkBytes[1] == 0x50 &&
        artworkBytes[2] == 0x4E &&
        artworkBytes[3] == 0x47 &&
        artworkBytes[4] == 0x0D &&
        artworkBytes[5] == 0x0A &&
        artworkBytes[6] == 0x1A &&
        artworkBytes[7] == 0x0A) {
      return 'image/png';
    }

    if (artworkBytes.length >= 6 &&
        artworkBytes[0] == 0x47 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x38 &&
        (artworkBytes[4] == 0x37 || artworkBytes[4] == 0x39) &&
        artworkBytes[5] == 0x61) {
      return 'image/gif';
    }

    if (artworkBytes.length >= 12 &&
        artworkBytes[0] == 0x52 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x46 &&
        artworkBytes[8] == 0x57 &&
        artworkBytes[9] == 0x45 &&
        artworkBytes[10] == 0x42 &&
        artworkBytes[11] == 0x50) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  Map<String, CatalogSongRecord> _buildCatalogSongRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogSongRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        records[songId] = CatalogSongRecord(
          id: songId,
          filePath: song.filePath,
          title: song.title ?? _getFilenameWithoutExtension(song.filePath),
          artist: song.artist ?? 'Unknown Artist',
          albumId: album.id,
          durationSeconds: song.duration ?? 0,
          trackNumber: song.trackNumber,
          fileSizeBytes: song.fileSize,
          modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
          artworkKey: album.id,
          updatedToken: 0,
          isDeleted: false,
        );
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      records[songId] = CatalogSongRecord(
        id: songId,
        filePath: song.filePath,
        title: song.title ?? _getFilenameWithoutExtension(song.filePath),
        artist: song.artist ?? 'Unknown Artist',
        albumId: null,
        durationSeconds: song.duration ?? 0,
        trackNumber: song.trackNumber,
        fileSizeBytes: song.fileSize,
        modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
        artworkKey: null,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, CatalogAlbumRecord> _buildCatalogAlbumRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogAlbumRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      var durationSeconds = 0;
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationSeconds += duration;
        }
      }

      records[album.id] = CatalogAlbumRecord(
        id: album.id,
        title: album.title,
        artist: album.artist,
        year: album.year,
        coverArtKey: album.artworkPath != null ? album.id : null,
        songCount: album.songCount,
        durationSeconds: durationSeconds,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, String?> _buildSongAlbumIdIndex(LibraryStructure library) {
    final index = <String, String?>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        index[songId] = album.id;
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      index[songId] = null;
    }

    return index;
  }

  int _readLatestTokenFromDatabase(Database database) {
    final rows = database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  void _insertLibraryChangeEvent({
    required Database database,
    required String entityType,
    required String entityId,
    required String op,
    required int occurredEpochMs,
  }) {
    database.execute(
      '''
INSERT INTO library_changes (
  entity_type,
  entity_id,
  op,
  payload_json,
  occurred_epoch_ms,
  actor_user_id
) VALUES (?, ?, ?, NULL, ?, NULL);
''',
      <Object?>[
        entityType,
        entityId,
        op,
        occurredEpochMs,
      ],
    );
  }

  /// Scan the music folder and build library structure
  ///
  /// This runs in a background isolate to prevent UI blocking.
  /// Progress updates are logged and the scan complete callback is fired when done.
  Future<void> scanMusicFolder(String folderPath) async {
    if (_isScanning) {
      print('[LibraryManager] Scan already in progress');
      return;
    }

    _isScanning = true;
    print(
        '[LibraryManager] Starting library scan (background isolate): $folderPath');

    try {
      // Load existing metadata cache if available
      Map<String, Map<String, dynamic>>? cacheData;
      if (_metadataCache != null) {
        await _metadataCache!.load();
        cacheData = _metadataCache!.exportForIsolate();
        print('[LibraryManager] Loaded ${cacheData.length} cached entries');
      }

      // Run the scan in a background isolate
      final result = await LibraryScannerIsolate.scan(
        folderPath,
        onProgress: (progress) {
          // Log progress updates from the isolate
          print('[LibraryManager] [${progress.stage}] ${progress.message} '
              '(${progress.percentage.toStringAsFixed(1)}%)');
        },
        cacheData: cacheData,
      );

      if (result.library != null) {
        _library = result.library;
        _lastScanTime = DateTime.now();
        _markDurationsDirty();

        // Save updated cache
        if (_metadataCache != null && result.updatedCache != null) {
          _metadataCache!.importFromIsolate(result.updatedCache!);
          await _metadataCache!.save();
          print(
              '[LibraryManager] Cache stats: ${result.cacheHits} hits, ${result.cacheMisses} extractions');
        }

        print('[LibraryManager] Library scan complete!');
        print('[LibraryManager] Albums: ${_library!.totalAlbums}');
        print(
            '[LibraryManager] Standalone songs: ${_library!.standaloneSongs.length}');
        print('[LibraryManager] Folder playlists: ${_library!.totalPlaylists}');
        print('[LibraryManager] Total songs: ${_library!.totalSongs}');

        // Persist deterministic catalog rows + change log for v2 sync.
        await _writeCatalogSnapshot();

        // Watch for incremental filesystem changes after scan.
        _startWatchingFolder(folderPath);

        // Notify listeners that scan is complete
        _notifyScanComplete();

        // Warm up durations asynchronously (non-blocking)
        unawaited(_startDurationWarmup());
      } else {
        print(
            '[LibraryManager] Scan returned null - possible error in isolate');
      }
    } catch (e, stackTrace) {
      print('[LibraryManager] ERROR during scan: $e');
      print('[LibraryManager] Stack trace: $stackTrace');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// Convert library to API JSON format for mobile app
  Map<String, dynamic> toApiJson(String baseUrl) {
    if (_library == null) {
      return {
        'albums': [],
        'songs': [],
        'playlists': [],
        'durationsReady': _durationsReady,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }

    // Convert albums to API format
    final albumsJson = _library!.albums.values
        .where((album) => album.isValid) // Only valid albums (2+ songs)
        .map((album) => _albumToApiJson(album, baseUrl))
        .toList();

    // Convert ALL songs to API format (album songs + standalone songs)
    final songsJson = <Map<String, dynamic>>[];

    // Add songs from all valid albums
    for (final album in _library!.albums.values.where((a) => a.isValid)) {
      for (final song in album.sortedSongs) {
        songsJson.add(_songToApiJson(song, baseUrl, album.id));
      }
    }

    // Add standalone songs (not in any album)
    for (final song in _library!.standaloneSongs) {
      songsJson.add(_songToApiJson(song, baseUrl, null));
    }

    // Convert folder playlists to API format
    final playlistsJson =
        _library!.folderPlaylists.map((playlist) => playlist.toJson()).toList();

    return {
      'albums': albumsJson,
      'songs': songsJson,
      'playlists': playlistsJson,
      'durationsReady': _durationsReady,
      'lastUpdated':
          _lastScanTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Convert library to API JSON format with lazy duration extraction for songs
  Future<Map<String, dynamic>> toApiJsonWithDurations(String baseUrl) async {
    if (_library == null) {
      return {
        'albums': [],
        'songs': [],
        'playlists': [],
        'durationsReady': _durationsReady,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }

    // Convert albums to API format (unchanged)
    final albumsJson = _library!.albums.values
        .where((album) => album.isValid) // Only valid albums (2+ songs)
        .map((album) => _albumToApiJson(album, baseUrl))
        .toList();

    // Convert ALL songs to API format with lazy duration extraction
    final songsJson = <Map<String, dynamic>>[];

    // Add songs from all valid albums
    for (final album in _library!.albums.values.where((a) => a.isValid)) {
      for (final song in album.sortedSongs) {
        songsJson.add(
          await _songToApiJsonWithDuration(song, baseUrl, album.id),
        );
      }
    }

    // Add standalone songs (not in any album)
    for (final song in _library!.standaloneSongs) {
      songsJson.add(
        await _songToApiJsonWithDuration(song, baseUrl, null),
      );
    }

    // Convert folder playlists to API format
    final playlistsJson =
        _library!.folderPlaylists.map((playlist) => playlist.toJson()).toList();

    return {
      'albums': albumsJson,
      'songs': songsJson,
      'playlists': playlistsJson,
      'durationsReady': _durationsReady,
      'lastUpdated':
          _lastScanTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  void ensureDurationWarmup() {
    if (_library == null) return;
    if (_durationsReady || _durationWarmupRunning) return;
    unawaited(_startDurationWarmup());
  }

  Future<void> _startDurationWarmup() async {
    if (_library == null || _durationWarmupRunning) return;

    _durationWarmupRunning = true;
    _durationsReady = false;

    int pending = 0;
    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (_songNeedsDuration(song)) {
          pending++;
        }
      }
    }
    for (final song in _library!.standaloneSongs) {
      if (_songNeedsDuration(song)) {
        pending++;
      }
    }

    if (pending == 0) {
      _durationWarmupRunning = false;
      _durationsReady = true;
      _notifyDurationsReady();
      return;
    }

    print('[LibraryManager] Warming up durations for $pending songs...');
    int processed = 0;

    for (final album in _library!.albums.values) {
      for (var i = 0; i < album.songs.length; i++) {
        final song = album.songs[i];
        final songId = _generateSongId(song.filePath);

        final cached = _durationCache[songId];
        if (cached != null &&
            cached > 0 &&
            (song.duration == null || song.duration == 0)) {
          final updated = song.copyWith(duration: cached);
          album.songs[i] = updated;
          await _persistDuration(updated, cached);
          continue;
        }

        if (!_songNeedsDuration(song)) {
          continue;
        }

        final duration =
            await _metadataExtractor.extractDuration(song.filePath);
        _durationCache[songId] = duration;

        if (duration != null && duration > 0) {
          final updated = song.copyWith(duration: duration);
          album.songs[i] = updated;
          await _persistDuration(updated, duration);
        }

        processed++;
        if (processed % 50 == 0) {
          print(
              '[LibraryManager] Duration warm-up progress: $processed/$pending');
        }
      }
    }

    for (var i = 0; i < _library!.standaloneSongs.length; i++) {
      final song = _library!.standaloneSongs[i];
      final songId = _generateSongId(song.filePath);

      final cached = _durationCache[songId];
      if (cached != null &&
          cached > 0 &&
          (song.duration == null || song.duration == 0)) {
        final updated = song.copyWith(duration: cached);
        _library!.standaloneSongs[i] = updated;
        await _persistDuration(updated, cached);
        continue;
      }

      if (!_songNeedsDuration(song)) {
        continue;
      }

      final duration = await _metadataExtractor.extractDuration(song.filePath);
      _durationCache[songId] = duration;

      if (duration != null && duration > 0) {
        final updated = song.copyWith(duration: duration);
        _library!.standaloneSongs[i] = updated;
        await _persistDuration(updated, duration);
      }

      processed++;
      if (processed % 50 == 0) {
        print(
            '[LibraryManager] Duration warm-up progress: $processed/$pending');
      }
    }

    await _metadataCache?.save();

    _durationWarmupRunning = false;
    _durationsReady = true;
    print('[LibraryManager] Duration warm-up complete');
    _notifyDurationsReady();
  }

  bool _songNeedsDuration(SongMetadata song) {
    if (song.duration != null && song.duration! > 0) return false;
    final songId = _generateSongId(song.filePath);
    final cached = _durationCache[songId];
    return cached == null || cached == 0;
  }

  Future<void> _persistDuration(
    SongMetadata song,
    int duration, {
    bool saveNow = false,
  }) async {
    if (_metadataCache == null) return;
    final updated = song.copyWith(duration: duration);
    final mtime = song.modifiedTime?.millisecondsSinceEpoch;
    final size = song.fileSize;
    await _metadataCache!.upsert(
      song.filePath,
      updated,
      mtime: mtime,
      size: size,
    );
    if (saveNow) {
      await _metadataCache!.save();
    }
  }

  /// Convert Album to API JSON format
  Map<String, dynamic> _albumToApiJson(Album album, String baseUrl) {
    int totalDurationSeconds = 0;
    for (final song in album.songs) {
      final songId = _generateSongId(song.filePath);
      totalDurationSeconds += _resolveSongDuration(song, songId);
    }

    return {
      'id': album.id,
      'title': album.title,
      'artist': album.artist,
      'coverArt':
          album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null,
      'songCount': album.songCount,
      'duration': totalDurationSeconds,
    };
  }

  /// Convert SongMetadata to API JSON format
  Map<String, dynamic> _songToApiJson(
      SongMetadata song, String baseUrl, String? albumId) {
    // Generate unique song ID from file path
    final songId = _generateSongId(song.filePath);
    final duration = _resolveSongDuration(song, songId);

    return {
      'id': songId,
      'title': song.title ?? _getFilenameWithoutExtension(song.filePath),
      'artist': song.artist ?? 'Unknown Artist',
      'albumId': albumId,
      'duration': duration,
      'trackNumber': song.trackNumber,
    };
  }

  int _resolveSongDuration(SongMetadata song, String songId) {
    final duration = song.duration;
    if (duration != null && duration > 0) return duration;

    final cached = _durationCache[songId];
    if (cached != null && cached > 0) return cached;

    return 0;
  }

  /// Generate a unique song ID from file path
  String _generateSongId(String filePath) {
    final bytes = utf8.encode(filePath);
    final hash = md5.convert(bytes);
    return hash.toString().substring(0, 12); // First 12 chars of hash
  }

  /// Extract filename without extension
  String _getFilenameWithoutExtension(String filePath) {
    return path.basenameWithoutExtension(filePath);
  }

  /// Get detailed album information with songs
  Future<Map<String, dynamic>?> getAlbumDetail(
      String albumId, String baseUrl) async {
    print('[LibraryManager] ========== GET ALBUM DETAIL ==========');
    print('[LibraryManager] Album ID: $albumId');
    print('[LibraryManager] Base URL: $baseUrl');

    if (_library == null) {
      print('[LibraryManager] ERROR: Library is null!');
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      print('[LibraryManager] ERROR: Album not found with ID: $albumId');
      print(
          '[LibraryManager] Available album IDs: ${_library!.albums.keys.toList()}');
      return null;
    }

    print('[LibraryManager] Found album: ${album.title} by ${album.artist}');
    print('[LibraryManager] Album artworkPath: ${album.artworkPath}');
    print('[LibraryManager] Album has artwork: ${album.artworkPath != null}');

    final coverArtUrl =
        album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null;
    print('[LibraryManager] Generated coverArt URL: $coverArtUrl');

    // Build songs with lazily extracted durations
    final songsJson = <Map<String, dynamic>>[];
    for (final song in album.sortedSongs) {
      final songJson = await _songToApiJsonWithDuration(song, baseUrl, albumId);
      songsJson.add(songJson);
    }

    print('[LibraryManager] Returning ${songsJson.length} songs');
    print('[LibraryManager] =======================================');

    return {
      'id': album.id,
      'title': album.title,
      'artist': album.artist,
      'year': album.year?.toString(),
      'coverArt': coverArtUrl,
      'songs': songsJson,
    };
  }

  /// Convert SongMetadata to API JSON format with lazy duration extraction
  Future<Map<String, dynamic>> _songToApiJsonWithDuration(
      SongMetadata song, String baseUrl, String? albumId) async {
    final songId = _generateSongId(song.filePath);

    // Use cached duration or extract lazily
    int duration = song.duration ?? 0;
    if (duration == 0) {
      final extractedDuration = await getSongDuration(songId);
      duration = extractedDuration ?? 0;
    }

    return {
      'id': songId,
      'title': song.title ?? _getFilenameWithoutExtension(song.filePath),
      'artist': song.artist ?? 'Unknown Artist',
      'albumId': albumId,
      'duration': duration,
      'trackNumber': song.trackNumber,
    };
  }

  /// Get song file path by song ID
  String? getSongFilePath(String songId) {
    if (_library == null) return null;

    // Search in all albums
    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (_generateSongId(song.filePath) == songId) {
          return song.filePath;
        }
      }
    }

    // Search in standalone songs
    for (final song in _library!.standaloneSongs) {
      if (_generateSongId(song.filePath) == songId) {
        return song.filePath;
      }
    }

    return null;
  }

  /// Get album ID for a song by song ID.
  ///
  /// Returns:
  /// - album ID when song belongs to an album
  /// - null for standalone songs or if song is not found
  String? getSongAlbumId(String songId) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (_generateSongId(song.filePath) == songId) {
          return album.id;
        }
      }
    }

    return null;
  }

  /// Get album artwork by album ID (lazy extraction with caching)
  Future<List<int>?> getAlbumArtwork(String albumId) async {
    if (_library == null) {
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      return null;
    }

    final source = await _extractAlbumArtworkSource(album);
    return source?.artworkBytes;
  }

  /// Get song duration by song ID (lazy extraction with caching)
  Future<int?> getSongDuration(String songId) async {
    // Check cache first
    if (_durationCache.containsKey(songId)) {
      return _durationCache[songId];
    }

    // Check library metadata
    final existingMetadata = _findSongMetadataById(songId);
    if (existingMetadata?.duration != null && existingMetadata!.duration! > 0) {
      _durationCache[songId] = existingMetadata.duration;
      return existingMetadata.duration;
    }

    // Find the song file path
    final filePath = existingMetadata?.filePath ?? getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    // Extract duration
    final duration = await _metadataExtractor.extractDuration(filePath);
    _durationCache[songId] = duration;

    if (duration != null && duration > 0) {
      final updatedMetadata = _updateSongDurationById(songId, duration);
      if (updatedMetadata != null) {
        await _persistDuration(updatedMetadata, duration, saveNow: true);
      }
    }

    return duration;
  }

  SongMetadata? _findSongMetadataById(String songId) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (_generateSongId(song.filePath) == songId) {
          return song;
        }
      }
    }

    for (final song in _library!.standaloneSongs) {
      if (_generateSongId(song.filePath) == songId) {
        return song;
      }
    }

    return null;
  }

  SongMetadata? _updateSongDurationById(String songId, int duration) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (var i = 0; i < album.songs.length; i++) {
        final song = album.songs[i];
        if (_generateSongId(song.filePath) == songId) {
          final updated = song.copyWith(duration: duration);
          album.songs[i] = updated;
          return updated;
        }
      }
    }

    for (var i = 0; i < _library!.standaloneSongs.length; i++) {
      final song = _library!.standaloneSongs[i];
      if (_generateSongId(song.filePath) == songId) {
        final updated = song.copyWith(duration: duration);
        _library!.standaloneSongs[i] = updated;
        return updated;
      }
    }

    return null;
  }

  /// Get song artwork by song ID (lazy extraction with caching)
  /// Used for standalone songs that don't belong to an album
  Future<List<int>?> getSongArtwork(String songId) async {
    // Check cache first
    if (_songArtworkCache.containsKey(songId)) {
      return _songArtworkCache[songId];
    }

    // Find the song file path
    final filePath = getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    // Extract artwork from the song file
    final artwork = await _metadataExtractor.extractArtwork(filePath);

    // Cache and return (including null to avoid repeated extraction attempts)
    _songArtworkCache[songId] = artwork;
    return artwork;
  }

  /// Clear library data
  void clear() {
    _stopWatchingFolder();
    _library = null;
    _lastScanTime = null;
    _artworkCache.clear();
    _durationCache.clear();
    _songArtworkCache.clear();
    _durationsReady = false;
    _durationWarmupRunning = false;
    print('[LibraryManager] Library cleared');
  }
}

class _AlbumArtworkSource {
  _AlbumArtworkSource({
    required this.artworkBytes,
    required this.referencePath,
    required this.lastModifiedEpochMs,
  });

  final List<int> artworkBytes;
  final String referencePath;
  final int lastModifiedEpochMs;
}
