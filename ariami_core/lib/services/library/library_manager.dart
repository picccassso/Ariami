import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';
import 'package:ariami_core/services/library/metadata_cache.dart';

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

  /// Cache for lazily extracted album artwork (LRU, max 50 albums ~25MB)
  final LruCache<String, List<int>?> _artworkCache = LruCache(50);

  /// Cache for lazily extracted song durations (LRU, max 2000 songs ~16KB)
  final LruCache<String, int?> _durationCache = LruCache(2000);

  /// Cache for lazily extracted song artwork for standalone songs (LRU, max 100 ~50MB)
  final LruCache<String, List<int>?> _songArtworkCache = LruCache(100);

  /// Metadata extractor instance for lazy extraction
  final MetadataExtractor _metadataExtractor = MetadataExtractor();

  /// Callbacks to notify when library scan completes
  final List<void Function()> _onScanCompleteCallbacks = [];

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

  /// Get the last scan timestamp
  DateTime? get lastScanTime => _lastScanTime;

  /// Check if currently scanning
  bool get isScanning => _isScanning;

  /// Set the path for persistent metadata cache
  ///
  /// Call this before scanning to enable cache. Path should be in a
  /// writable config directory (e.g., ~/.ariami_cli/ or app data).
  void setCachePath(String cachePath) {
    _metadataCache = MetadataCache(cachePath);
    print('[LibraryManager] Metadata cache path set: $cachePath');
  }

  /// Force clear the metadata cache (for "Force Rescan" feature)
  Future<void> clearMetadataCache() async {
    if (_metadataCache != null) {
      await _metadataCache!.clear();
      print('[LibraryManager] Metadata cache cleared');
    }
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
    print('[LibraryManager] Starting library scan (background isolate): $folderPath');

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

        // Save updated cache
        if (_metadataCache != null && result.updatedCache != null) {
          _metadataCache!.importFromIsolate(result.updatedCache!);
          await _metadataCache!.save();
          print('[LibraryManager] Cache stats: ${result.cacheHits} hits, ${result.cacheMisses} extractions');
        }

        print('[LibraryManager] Library scan complete!');
        print('[LibraryManager] Albums: ${_library!.totalAlbums}');
        print('[LibraryManager] Standalone songs: ${_library!.standaloneSongs.length}');
        print('[LibraryManager] Folder playlists: ${_library!.totalPlaylists}');
        print('[LibraryManager] Total songs: ${_library!.totalSongs}');

        // Notify listeners that scan is complete
        _notifyScanComplete();
      } else {
        print('[LibraryManager] Scan returned null - possible error in isolate');
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
    final playlistsJson = _library!.folderPlaylists
        .map((playlist) => playlist.toJson())
        .toList();

    return {
      'albums': albumsJson,
      'songs': songsJson,
      'playlists': playlistsJson,
      'lastUpdated': _lastScanTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Convert Album to API JSON format
  Map<String, dynamic> _albumToApiJson(Album album, String baseUrl) {
    return {
      'id': album.id,
      'title': album.title,
      'artist': album.artist,
      'coverArt': album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null,
      'songCount': album.songCount,
      'duration': album.totalDuration.inSeconds,
    };
  }

  /// Convert SongMetadata to API JSON format
  Map<String, dynamic> _songToApiJson(SongMetadata song, String baseUrl, String? albumId) {
    // Generate unique song ID from file path
    final songId = _generateSongId(song.filePath);

    return {
      'id': songId,
      'title': song.title ?? _getFilenameWithoutExtension(song.filePath),
      'artist': song.artist ?? 'Unknown Artist',
      'albumId': albumId,
      'duration': song.duration ?? 0,
      'trackNumber': song.trackNumber,
    };
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
  Future<Map<String, dynamic>?> getAlbumDetail(String albumId, String baseUrl) async {
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
      print('[LibraryManager] Available album IDs: ${_library!.albums.keys.toList()}');
      return null;
    }

    print('[LibraryManager] Found album: ${album.title} by ${album.artist}');
    print('[LibraryManager] Album artworkPath: ${album.artworkPath}');
    print('[LibraryManager] Album has artwork: ${album.artworkPath != null}');

    final coverArtUrl = album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null;
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
  Future<Map<String, dynamic>> _songToApiJsonWithDuration(SongMetadata song, String baseUrl, String? albumId) async {
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

  /// Get album artwork by album ID (lazy extraction with caching)
  Future<List<int>?> getAlbumArtwork(String albumId) async {
    // Check cache first
    if (_artworkCache.containsKey(albumId)) {
      return _artworkCache[albumId];
    }

    if (_library == null) {
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      return null;
    }

    // Try to extract artwork from the first song in the album
    for (final song in album.songs) {
      final artwork = await _metadataExtractor.extractArtwork(song.filePath);
      if (artwork != null) {
        // Cache and return
        _artworkCache[albumId] = artwork;
        return artwork;
      }
    }

    // No artwork found, cache null to avoid repeated extraction attempts
    _artworkCache[albumId] = null;
    return null;
  }

  /// Get song duration by song ID (lazy extraction with caching)
  Future<int?> getSongDuration(String songId) async {
    // Check cache first
    if (_durationCache.containsKey(songId)) {
      return _durationCache[songId];
    }

    // Find the song file path
    final filePath = getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    // Extract duration
    final duration = await _metadataExtractor.extractDuration(filePath);
    _durationCache[songId] = duration;
    return duration;
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
    _library = null;
    _lastScanTime = null;
    _artworkCache.clear();
    _durationCache.clear();
    _songArtworkCache.clear();
    print('[LibraryManager] Library cleared');
  }
}
