import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:bma_core/models/library_structure.dart';
import 'package:bma_core/models/album.dart';
import 'package:bma_core/models/song_metadata.dart';
import 'package:bma_core/services/library/metadata_extractor.dart';
import 'package:bma_core/services/library/library_scanner_isolate.dart';

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

  /// Cache for lazily extracted album artwork
  final Map<String, List<int>?> _artworkCache = {};

  /// Cache for lazily extracted song durations (songId -> duration in seconds)
  final Map<String, int?> _durationCache = {};

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
      // Run the scan in a background isolate
      final result = await LibraryScannerIsolate.scan(
        folderPath,
        onProgress: (progress) {
          // Log progress updates from the isolate
          print('[LibraryManager] [${progress.stage}] ${progress.message} '
              '(${progress.percentage.toStringAsFixed(1)}%)');
        },
      );

      if (result != null) {
        _library = result;
        _lastScanTime = DateTime.now();

        print('[LibraryManager] Library scan complete!');
        print('[LibraryManager] Albums: ${_library!.totalAlbums}');
        print('[LibraryManager] Standalone songs: ${_library!.standaloneSongs.length}');
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

    // Convert standalone songs to API format
    final songsJson = _library!.standaloneSongs
        .map((song) => _songToApiJson(song, baseUrl, null))
        .toList();

    // Playlists are empty for now (will be implemented in Phase 7 Task 7.5)
    final playlistsJson = <Map<String, dynamic>>[];

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

  /// Clear library data
  void clear() {
    _library = null;
    _lastScanTime = null;
    _artworkCache.clear();
    _durationCache.clear();
    print('[LibraryManager] Library cleared');
  }
}
