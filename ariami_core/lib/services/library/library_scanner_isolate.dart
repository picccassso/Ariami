import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/file_scanner.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/duplicate_detector.dart';

/// Message types for isolate communication
enum ScanMessageType {
  progress,
  complete,
  error,
}

/// Progress message sent from isolate to main thread
class ScanProgressMessage {
  final ScanMessageType type;
  final String stage;
  final int current;
  final int total;
  final double percentage;
  final String? message;

  const ScanProgressMessage({
    required this.type,
    required this.stage,
    this.current = 0,
    this.total = 0,
    this.percentage = 0.0,
    this.message,
  });
}

/// Result message containing the scanned library
class ScanResultMessage {
  final ScanMessageType type;
  final LibraryStructure? library;
  final String? error;
  final DateTime scanTime;

  /// Updated cache data to save (filePath -> {mtime, size, metadata})
  final Map<String, Map<String, dynamic>>? updatedCache;

  /// Statistics about cache usage
  final int cacheHits;
  final int cacheMisses;

  const ScanResultMessage({
    required this.type,
    this.library,
    this.error,
    required this.scanTime,
    this.updatedCache,
    this.cacheHits = 0,
    this.cacheMisses = 0,
  });
}

/// Parameters passed to the isolate entry point
class ScanParams {
  final String folderPath;
  final SendPort sendPort;

  /// Existing cache data (filePath -> {mtime, size, metadata})
  /// Passed as serializable Map for isolate communication
  final Map<String, Map<String, dynamic>>? cacheData;

  const ScanParams({
    required this.folderPath,
    required this.sendPort,
    this.cacheData,
  });
}

/// Library scanner that runs in a background isolate
///
/// This prevents UI blocking during library scans by moving all
/// heavy I/O and processing to a separate isolate.
class LibraryScannerIsolate {
  /// Calculates optimal batch size based on available CPU cores
  ///
  /// Lower-power devices (fewer cores) get smaller batches to avoid
  /// overwhelming the system. Higher-core systems can process more
  /// files concurrently.
  static int _calculateBatchSize() {
    final cores = Platform.numberOfProcessors;
    if (cores <= 2) {
      return 8; // Low-power devices (Pi 3, older systems)
    } else if (cores <= 4) {
      return 15; // Mid-range (Pi 4/5, typical laptops)
    } else if (cores <= 8) {
      return 25; // Powerful desktops
    } else {
      return 35; // High-end workstations
    }
  }
  /// Spawn an isolate to scan the library and return the result
  ///
  /// Progress updates are sent via [onProgress] callback.
  /// Pass [cacheData] from MetadataCache for fast re-scans.
  /// Returns a record with the library and updated cache data.
  static Future<({LibraryStructure? library, Map<String, Map<String, dynamic>>? updatedCache, int cacheHits, int cacheMisses})> scan(
    String folderPath, {
    void Function(ScanProgressMessage)? onProgress,
    Map<String, Map<String, dynamic>>? cacheData,
  }) async {
    final receivePort = ReceivePort();

    try {
      // Spawn the isolate
      await Isolate.spawn(
        _isolateEntryPoint,
        ScanParams(
          folderPath: folderPath,
          sendPort: receivePort.sendPort,
          cacheData: cacheData,
        ),
      );

      // Listen for messages from the isolate
      LibraryStructure? result;
      Map<String, Map<String, dynamic>>? updatedCache;
      int cacheHits = 0;
      int cacheMisses = 0;
      String? errorMessage;

      await for (final message in receivePort) {
        if (message is ScanProgressMessage) {
          onProgress?.call(message);
        } else if (message is ScanResultMessage) {
          if (message.type == ScanMessageType.complete) {
            result = message.library;
            updatedCache = message.updatedCache;
            cacheHits = message.cacheHits;
            cacheMisses = message.cacheMisses;
          } else if (message.type == ScanMessageType.error) {
            errorMessage = message.error;
          }
          break; // Done - exit the loop
        }
      }

      if (errorMessage != null) {
        print('[LibraryScannerIsolate] Scan failed: $errorMessage');
        return (library: null, updatedCache: null, cacheHits: 0, cacheMisses: 0);
      }

      return (library: result, updatedCache: updatedCache, cacheHits: cacheHits, cacheMisses: cacheMisses);
    } catch (e) {
      print('[LibraryScannerIsolate] Error spawning isolate: $e');
      return (library: null, updatedCache: null, cacheHits: 0, cacheMisses: 0);
    } finally {
      receivePort.close();
    }
  }

  /// Entry point for the isolate - must be a top-level or static function
  static Future<void> _isolateEntryPoint(ScanParams params) async {
    final sendPort = params.sendPort;
    final folderPath = params.folderPath;
    final existingCache = params.cacheData ?? {};

    // Track cache statistics
    int cacheHits = 0;
    int cacheMisses = 0;

    // Build updated cache as we go
    final updatedCache = <String, Map<String, dynamic>>{};

    try {
      // Step 1: Collect audio files and detect [PLAYLIST] folders
      _sendProgress(sendPort, 'collecting', 0, 0, 0.0, 'Scanning for audio files...');

      final scanResult = await _collectAudioFiles(folderPath);
      final audioFiles = scanResult.files;
      final playlistFolders = scanResult.playlistFolders;
      final totalFiles = audioFiles.length;

      final playlistInfo = playlistFolders.isNotEmpty
          ? ', ${playlistFolders.length} playlist folder(s)'
          : '';
      _sendProgress(sendPort, 'collecting', totalFiles, totalFiles, 10.0,
          'Found $totalFiles audio files$playlistInfo');

      if (totalFiles == 0) {
        // No files found - return empty library
        final emptyLibrary = const LibraryStructure(
          albums: {},
          standaloneSongs: [],
        );
        sendPort.send(ScanResultMessage(
          type: ScanMessageType.complete,
          library: emptyLibrary,
          scanTime: DateTime.now(),
          updatedCache: updatedCache,
          cacheHits: 0,
          cacheMisses: 0,
        ));
        return;
      }

      // Step 2: Extract metadata (with cache support)
      _sendProgress(sendPort, 'metadata', 0, totalFiles, 10.0,
          'Extracting metadata...');

      final extractor = MetadataExtractor();
      final songs = <SongMetadata>[];

      final batchSize = _calculateBatchSize();
      for (var i = 0; i < totalFiles; i += batchSize) {
        final batchEnd = (i + batchSize < totalFiles) ? i + batchSize : totalFiles;
        final batch = audioFiles.sublist(i, batchEnd);

        // Process batch in parallel (with cache check)
        final results = await Future.wait(
          batch.map((filePath) => _extractOrUseCached(
            extractor,
            filePath,
            existingCache,
          )),
        );

        // Collect successful results and update cache
        for (final result in results) {
          if (result != null) {
            songs.add(result.metadata);
            // Store in updated cache
            updatedCache[result.metadata.filePath] = {
              'mtime': result.mtime,
              'size': result.size,
              'metadata': result.metadata.toJson(),
            };
            if (result.fromCache) {
              cacheHits++;
            } else {
              cacheMisses++;
            }
          }
        }

        // Calculate progress (10% to 70% for metadata extraction)
        final metadataProgress = 10.0 + (batchEnd / totalFiles) * 60.0;
        final cacheInfo = existingCache.isNotEmpty
            ? ' (cache: $cacheHits hits, $cacheMisses misses)'
            : '';
        _sendProgress(sendPort, 'metadata', batchEnd, totalFiles, metadataProgress,
            'Processed $batchEnd/$totalFiles files$cacheInfo');
      }

      await extractor.dispose();

      // Step 3: Detect duplicates
      _sendProgress(sendPort, 'duplicates', 0, songs.length, 70.0,
          'Detecting duplicates...');

      final duplicateDetector = DuplicateDetector();
      final duplicateGroups = await duplicateDetector.detectDuplicates(songs);
      final uniqueSongs = duplicateDetector.filterDuplicates(songs, duplicateGroups);

      _sendProgress(sendPort, 'duplicates', uniqueSongs.length, songs.length, 85.0,
          '${uniqueSongs.length} unique songs after filtering');

      // Step 4: Build albums
      _sendProgress(sendPort, 'albums', 0, uniqueSongs.length, 85.0,
          'Building album structure...');

      final albumBuilder = AlbumBuilder();
      final baseLibrary = albumBuilder.buildLibrary(uniqueSongs);

      // Step 5: Build folder playlists
      final folderPlaylistsList = <FolderPlaylist>[];
      for (final entry in playlistFolders.entries) {
        final folderPath = entry.key;
        final filePaths = entry.value;

        // Skip empty playlist folders
        if (filePaths.isEmpty) continue;

        // Convert file paths to song IDs
        final songIds = filePaths.map((fp) => _generateSongId(fp)).toList();

        final playlist = FolderPlaylist(
          id: FolderPlaylist.generateId(folderPath),
          name: FolderPlaylist.extractName(path.basename(folderPath)),
          folderPath: folderPath,
          songIds: songIds,
        );
        folderPlaylistsList.add(playlist);
      }

      // Create final library with playlists
      final library = LibraryStructure(
        albums: baseLibrary.albums,
        standaloneSongs: baseLibrary.standaloneSongs,
        folderPlaylists: folderPlaylistsList,
      );

      final cacheStats = existingCache.isNotEmpty
          ? ' (cache: $cacheHits hits, $cacheMisses extractions)'
          : '';
      final playlistStats = folderPlaylistsList.isNotEmpty
          ? ', ${folderPlaylistsList.length} playlists'
          : '';
      _sendProgress(sendPort, 'complete', library.totalSongs, library.totalSongs, 100.0,
          'Scan complete: ${library.totalAlbums} albums, ${library.totalSongs} songs$playlistStats$cacheStats');

      // Send the result with updated cache
      sendPort.send(ScanResultMessage(
        type: ScanMessageType.complete,
        library: library,
        scanTime: DateTime.now(),
        updatedCache: updatedCache,
        cacheHits: cacheHits,
        cacheMisses: cacheMisses,
      ));
    } catch (e, stackTrace) {
      print('[LibraryScannerIsolate] ERROR in isolate: $e');
      print('[LibraryScannerIsolate] Stack trace: $stackTrace');

      sendPort.send(ScanResultMessage(
        type: ScanMessageType.error,
        error: e.toString(),
        scanTime: DateTime.now(),
      ));
    }
  }

  /// Result from cache-aware metadata extraction
  static Future<({SongMetadata metadata, int mtime, int size, bool fromCache})?> _extractOrUseCached(
    MetadataExtractor extractor,
    String filePath,
    Map<String, Map<String, dynamic>> cache,
  ) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      final currentMtime = stat.modified.millisecondsSinceEpoch;
      final currentSize = stat.size;

      // Check cache
      final cached = cache[filePath];
      if (cached != null) {
        final cachedMtime = cached['mtime'] as int?;
        final cachedSize = cached['size'] as int?;

        // Validate cache entry
        if (cachedMtime == currentMtime && cachedSize == currentSize) {
          // Cache hit! Reconstruct metadata from cached JSON
          final metadataJson = cached['metadata'] as Map<String, dynamic>?;
          if (metadataJson != null) {
            final metadata = SongMetadata.fromJson(metadataJson);
            return (
              metadata: metadata,
              mtime: currentMtime,
              size: currentSize,
              fromCache: true,
            );
          }
        }
      }

      // Cache miss - extract metadata
      final metadata = await extractor.extractMetadataWithDuration(filePath);

      return (
        metadata: metadata,
        mtime: currentMtime,
        size: currentSize,
        fromCache: false,
      );
    } catch (e) {
      print('[LibraryScannerIsolate] Failed to process $filePath: $e');
      return null;
    }
  }

  /// Helper to send progress message
  static void _sendProgress(
    SendPort sendPort,
    String stage,
    int current,
    int total,
    double percentage,
    String message,
  ) {
    sendPort.send(ScanProgressMessage(
      type: ScanMessageType.progress,
      stage: stage,
      current: current,
      total: total,
      percentage: percentage,
      message: message,
    ));
  }

  /// Collect audio files from directory and detect [PLAYLIST] folders
  ///
  /// Returns both the list of audio files and a map of playlist folders
  /// to the files they contain.
  static Future<({List<String> files, Map<String, List<String>> playlistFolders})> _collectAudioFiles(String folderPath) async {
    final files = <String>[];
    final playlistFolders = <String, List<String>>{};
    final rootDir = Directory(folderPath);

    if (!await rootDir.exists()) {
      return (files: files, playlistFolders: playlistFolders);
    }

    // First pass: find all [PLAYLIST] folders (top-level only, not nested)
    final playlistPaths = <String>{};
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);
        if (FolderPlaylist.isPlaylistFolder(folderName)) {
          // Check this isn't nested inside another playlist folder
          final isNested = playlistPaths.any((p) => entity.path.startsWith('$p${path.separator}'));
          if (!isNested) {
            playlistPaths.add(entity.path);
            playlistFolders[entity.path] = [];
          }
        }
      }
    }

    // Second pass: collect all audio files and assign to playlists
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (FileScanner.supportedExtensions.contains(ext)) {
          files.add(entity.path);

          // Check if this file belongs to a playlist folder
          for (final playlistPath in playlistPaths) {
            if (entity.path.startsWith('$playlistPath${path.separator}')) {
              playlistFolders[playlistPath]!.add(entity.path);
              break; // A file can only belong to one playlist
            }
          }
        }
      }
    }

    return (files: files, playlistFolders: playlistFolders);
  }

  /// Generate a unique song ID from file path (must match LibraryManager)
  static String _generateSongId(String filePath) {
    final bytes = utf8.encode(filePath);
    final hash = md5.convert(bytes);
    return hash.toString().substring(0, 12);
  }
}

