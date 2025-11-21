import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import '../../models/library_structure.dart';
import '../../models/album.dart';
import '../../models/song_metadata.dart';
import 'file_scanner.dart';
import 'metadata_extractor.dart';
import 'album_builder.dart';
import 'duplicate_detector.dart';

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
  Future<void> scanMusicFolder(String folderPath) async {
    if (_isScanning) {
      print('[LibraryManager] Scan already in progress');
      return;
    }

    _isScanning = true;
    print('[LibraryManager] Starting library scan: $folderPath');

    try {
      // Step 1: Scan for audio files
      print('[LibraryManager] Step 1: Scanning for audio files...');
      final audioFiles = await _collectAudioFiles(folderPath);
      print('[LibraryManager] Found ${audioFiles.length} audio files');

      // Step 2: Extract metadata
      print('[LibraryManager] Step 2: Extracting metadata...');
      final extractor = MetadataExtractor();
      final songs = <SongMetadata>[];
      for (final filePath in audioFiles) {
        try {
          final metadata = await extractor.extractMetadata(filePath);
          songs.add(metadata);
        } catch (e) {
          print('[LibraryManager] Failed to extract metadata from $filePath: $e');
        }
      }
      print('[LibraryManager] Extracted metadata for ${songs.length} songs');

      // Step 3: Detect and filter duplicates
      print('[LibraryManager] Step 3: Detecting duplicates...');
      final duplicateDetector = DuplicateDetector();
      final duplicateGroups = await duplicateDetector.detectDuplicates(songs);
      final uniqueSongs = duplicateDetector.filterDuplicates(songs, duplicateGroups);
      print('[LibraryManager] ${uniqueSongs.length} unique songs after duplicate filtering');

      // Step 4: Build album structure
      print('[LibraryManager] Step 4: Building album structure...');
      final albumBuilder = AlbumBuilder();
      _library = albumBuilder.buildLibrary(uniqueSongs);
      _lastScanTime = DateTime.now();

      print('[LibraryManager] Library scan complete!');
      print('[LibraryManager] Albums: ${_library!.totalAlbums}');
      print('[LibraryManager] Standalone songs: ${_library!.standaloneSongs.length}');
      print('[LibraryManager] Total songs: ${_library!.totalSongs}');

      // Debug: Check which albums have artwork
      print('[LibraryManager] ========== ARTWORK DEBUG ==========');
      for (final album in _library!.albums.values) {
        print('[LibraryManager] Album: ${album.title}');
        print('[LibraryManager]   artworkPath: ${album.artworkPath}');
        print('[LibraryManager]   Has artwork: ${album.artworkPath != null}');
      }
      print('[LibraryManager] ===================================');

      // Clean up the metadata extractor's audio player
      await extractor.dispose();
      print('[LibraryManager] Metadata extractor disposed');

      // Notify listeners that scan is complete
      _notifyScanComplete();
    } catch (e, stackTrace) {
      print('[LibraryManager] ERROR during scan: $e');
      print('[LibraryManager] Stack trace: $stackTrace');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// Manually collect audio files from directory
  Future<List<String>> _collectAudioFiles(String folderPath) async {
    final files = <String>[];
    final rootDir = Directory(folderPath);

    if (!await rootDir.exists()) return files;

    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (FileScanner.supportedExtensions.contains(ext)) {
          files.add(entity.path);
        }
      }
    }

    return files;
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
  Map<String, dynamic>? getAlbumDetail(String albumId, String baseUrl) {
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

    final songsJson = album.sortedSongs
        .map((song) => _songToApiJson(song, baseUrl, albumId))
        .toList();

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

  /// Get album artwork by album ID
  List<int>? getAlbumArtwork(String albumId) {
    print('[LibraryManager] ========== GET ALBUM ARTWORK ==========');
    print('[LibraryManager] Album ID: $albumId');

    if (_library == null) {
      print('[LibraryManager] ERROR: Library is null');
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      print('[LibraryManager] ERROR: Album not found');
      return null;
    }

    print('[LibraryManager] Album found: ${album.title}');
    print('[LibraryManager] Artwork path: ${album.artworkPath}');

    if (album.artworkPath == null) {
      print('[LibraryManager] ERROR: No artworkPath for this album');
      return null;
    }

    // Find the song with artwork
    print('[LibraryManager] Searching ${album.songs.length} songs for artwork...');
    for (final song in album.songs) {
      print('[LibraryManager]   Checking song: ${song.title}');
      print('[LibraryManager]     File path: ${song.filePath}');
      print('[LibraryManager]     Has albumArt: ${song.albumArt != null}');
      print('[LibraryManager]     AlbumArt size: ${song.albumArt?.length ?? 0} bytes');

      if (song.filePath == album.artworkPath && song.albumArt != null) {
        print('[LibraryManager] ✅ FOUND ARTWORK! Size: ${song.albumArt!.length} bytes');
        print('[LibraryManager] =======================================');
        return song.albumArt;
      }
    }

    print('[LibraryManager] ERROR: No song matched artworkPath');
    print('[LibraryManager] =======================================');
    return null;
  }

  /// Clear library data
  void clear() {
    _library = null;
    _lastScanTime = null;
    print('[LibraryManager] Library cleared');
  }
}
