import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/scan_diagnostics.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/file_scanner.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart'
    show suspiciousPlaylistAlbumTagPaths;
import 'package:ariami_core/services/library/m3u_playlist_parser.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/duplicate_detector.dart';
import 'package:ariami_core/services/library/natural_path_order.dart';
import 'package:ariami_core/services/library/playlist_folder_classifier.dart';

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

  /// Bounded list of files that could not be processed during scan.
  final List<ScanFailedFile> failedFiles;

  /// Total skipped files (may exceed [failedFiles].length when bounded).
  final int skippedFileCount;

  /// Advisory likely-playlist folders detected during the scan.
  final List<PlaylistSuggestion> playlistSuggestions;

  /// Unmarked folders auto-imported as playlists (high confidence).
  final List<PlaylistSuggestion> autoImportedPlaylistFolders;

  const ScanResultMessage({
    required this.type,
    this.library,
    this.error,
    required this.scanTime,
    this.updatedCache,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.failedFiles = const [],
    this.skippedFileCount = 0,
    this.playlistSuggestions = const [],
    this.autoImportedPlaylistFolders = const [],
  });
}

/// Parameters passed to the isolate entry point
class ScanParams {
  final String folderPath;
  final SendPort sendPort;

  /// Existing cache data (filePath -> {mtime, size, metadata})
  /// Passed as serializable Map for isolate communication
  final Map<String, Map<String, dynamic>>? cacheData;

  /// Folders the user approved as playlists (suggestion "import" decisions).
  /// Treated exactly like [PLAYLIST] folders; passed as plain data because
  /// the isolate cannot read the decision store.
  final List<String> approvedPlaylistFolderPaths;

  /// Folders the user chose never to suggest again ("ignore" decisions).
  final List<String> ignoredSuggestionFolderPaths;

  const ScanParams({
    required this.folderPath,
    required this.sendPort,
    this.cacheData,
    this.approvedPlaylistFolderPaths = const [],
    this.ignoredSuggestionFolderPaths = const [],
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
  /// overwhelming the system and prevent SD card stalls on Pi devices.
  /// Higher-core systems can process more files concurrently.
  static int _calculateBatchSize() {
    final cores = Platform.numberOfProcessors;
    if (cores <= 2) {
      return 4; // Very low-power devices (Pi 3, older systems) - prevent SD card stalls
    } else if (cores <= 4) {
      return 8; // Mid-range (Pi 4/5, typical laptops)
    } else if (cores <= 8) {
      return 15; // Powerful desktops
    } else {
      return 25; // High-end workstations
    }
  }

  /// Spawn an isolate to scan the library and return the result
  ///
  /// Progress updates are sent via [onProgress] callback.
  /// Pass [cacheData] from MetadataCache for fast re-scans.
  /// Returns a record with the library and updated cache data.
  static Future<
      ({
        LibraryStructure? library,
        Map<String, Map<String, dynamic>>? updatedCache,
        int cacheHits,
        int cacheMisses,
        ScanDiagnostics scanDiagnostics,
      })> scan(
    String folderPath, {
    void Function(ScanProgressMessage)? onProgress,
    Map<String, Map<String, dynamic>>? cacheData,
    List<String> approvedPlaylistFolderPaths = const [],
    List<String> ignoredSuggestionFolderPaths = const [],
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    try {
      // Spawn the isolate. onError/onExit ports guarantee this method
      // completes even if the isolate dies without sending a result
      // (otherwise the scan would hang forever with _isScanning stuck).
      await Isolate.spawn(
        _isolateEntryPoint,
        ScanParams(
          folderPath: folderPath,
          sendPort: receivePort.sendPort,
          cacheData: cacheData,
          approvedPlaylistFolderPaths: approvedPlaylistFolderPaths,
          ignoredSuggestionFolderPaths: ignoredSuggestionFolderPaths,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );

      // Listen for messages from the isolate
      LibraryStructure? result;
      Map<String, Map<String, dynamic>>? updatedCache;
      int cacheHits = 0;
      int cacheMisses = 0;
      ScanDiagnostics scanDiagnostics = const ScanDiagnostics();
      String? errorMessage;

      final done = Completer<void>();

      errorPort.listen((message) {
        // Uncaught isolate errors arrive as [error, stackTrace].
        errorMessage ??= (message is List && message.isNotEmpty)
            ? message.first?.toString()
            : message?.toString();
        if (!done.isCompleted) done.complete();
      });

      exitPort.listen((_) {
        // Exit is enqueued after any result the isolate sent, so if we get
        // here without a result the isolate died silently.
        if (!done.isCompleted) {
          if (result == null) {
            errorMessage ??= 'Scanner isolate exited without sending a result';
          }
          done.complete();
        }
      });

      receivePort.listen((message) {
        if (message is ScanProgressMessage) {
          onProgress?.call(message);
        } else if (message is ScanResultMessage) {
          if (message.type == ScanMessageType.complete) {
            result = message.library;
            updatedCache = message.updatedCache;
            cacheHits = message.cacheHits;
            cacheMisses = message.cacheMisses;
            scanDiagnostics = ScanDiagnostics(
              skippedFileCount: message.skippedFileCount,
              failedFiles: message.failedFiles,
              playlistSuggestions: message.playlistSuggestions,
              autoImportedPlaylistFolders: message.autoImportedPlaylistFolders,
            );
          } else if (message.type == ScanMessageType.error) {
            errorMessage = message.error;
          }
          if (!done.isCompleted) done.complete();
        }
      });

      await done.future;

      if (errorMessage != null) {
        print('[LibraryScannerIsolate] Scan failed: $errorMessage');
        return (
          library: null,
          updatedCache: null,
          cacheHits: 0,
          cacheMisses: 0,
          scanDiagnostics: const ScanDiagnostics(),
        );
      }

      return (
        library: result,
        updatedCache: updatedCache,
        cacheHits: cacheHits,
        cacheMisses: cacheMisses,
        scanDiagnostics: scanDiagnostics,
      );
    } catch (e) {
      print('[LibraryScannerIsolate] Error spawning isolate: $e');
      return (
        library: null,
        updatedCache: null,
        cacheHits: 0,
        cacheMisses: 0,
        scanDiagnostics: const ScanDiagnostics(),
      );
    } finally {
      receivePort.close();
      errorPort.close();
      exitPort.close();
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
    final failedFiles = <ScanFailedFile>[];
    var skippedFileCount = 0;

    void recordFailure(String filePath, String reason) {
      skippedFileCount++;
      if (failedFiles.length < ScanDiagnostics.maxFailedFiles) {
        failedFiles.add(ScanFailedFile(path: filePath, reason: reason));
      }
    }

    try {
      // Step 1: Collect audio files and detect [PLAYLIST] folders
      _sendProgress(
          sendPort, 'collecting', 0, 0, 0.0, 'Scanning for audio files...');

      final approvedPlaylistFolderPaths = params.approvedPlaylistFolderPaths
          .map(path.normalize)
          .toSet();
      final scanResult = await _collectAudioFiles(
        folderPath,
        approvedPlaylistFolderPaths: approvedPlaylistFolderPaths,
      );
      final audioFiles = scanResult.files;
      final playlistFolders = scanResult.playlistFolders;
      final m3uFiles = scanResult.m3uFiles;
      final totalFiles = audioFiles.length;

      // Surface subtrees the traversal had to skip (permissions, dead
      // mounts, I/O errors) in scan diagnostics instead of failing silently.
      for (final failure in scanResult.unreadableDirectories) {
        recordFailure(failure.path, 'directory unreadable: ${failure.reason}');
      }

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
          failedFiles: failedFiles,
          skippedFileCount: skippedFileCount,
        ));
        return;
      }

      // Step 2: Extract metadata (with cache support)
      _sendProgress(
          sendPort, 'metadata', 0, totalFiles, 10.0, 'Extracting metadata...');

      final extractor = MetadataExtractor();
      final songs = <SongMetadata>[];
      final cacheHitPaths = <String>{};

      final batchSize = _calculateBatchSize();
      for (var i = 0; i < totalFiles; i += batchSize) {
        final batchEnd =
            (i + batchSize < totalFiles) ? i + batchSize : totalFiles;
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
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          if (result != null) {
            songs.add(result.metadata);
            // Store in updated cache
            final cacheEntry = <String, dynamic>{
              'mtime': result.mtime,
              'size': result.size,
              'metadata': result.metadata.toJson(),
            };
            if (result.fromCache) {
              cacheHits++;
              cacheHitPaths.add(result.metadata.filePath);
              // The file is unchanged, so its previously computed
              // duplicate-detection hash is still valid — carry it forward
              // instead of forcing a re-hash on the next scan.
              final previousHash =
                  existingCache[result.metadata.filePath]?['partialHash'];
              if (previousHash is String) {
                cacheEntry['partialHash'] = previousHash;
              }
            } else {
              cacheMisses++;
            }
            updatedCache[result.metadata.filePath] = cacheEntry;
          } else {
            recordFailure(batch[i], 'metadata extraction failed');
          }
        }

        // Calculate progress (10% to 70% for metadata extraction)
        final metadataProgress = 10.0 + (batchEnd / totalFiles) * 60.0;
        final cacheInfo = existingCache.isNotEmpty
            ? ' (cache: $cacheHits hits, $cacheMisses misses)'
            : '';
        _sendProgress(
            sendPort,
            'metadata',
            batchEnd,
            totalFiles,
            metadataProgress,
            'Processed $batchEnd/$totalFiles files$cacheInfo');
      }

      await extractor.dispose();

      // Step 3: Detect duplicates
      _sendProgress(sendPort, 'duplicates', 0, songs.length, 70.0,
          'Detecting duplicates...');

      // Extract cached hashes for duplicate detection. Only trust hashes for
      // files that validated against the cache this scan (unchanged mtime and
      // size) — a stale hash for a modified file would corrupt grouping.
      final cachedHashes = <String, String>{};
      for (final entry in existingCache.entries) {
        if (!cacheHitPaths.contains(entry.key)) continue;
        final hash = entry.value['partialHash'] as String?;
        if (hash != null) {
          cachedHashes[entry.key] = hash;
        }
      }

      final duplicateDetector = DuplicateDetector();
      final playlistFolderSongPaths =
          playlistFolders.values.expand((paths) => paths).toSet();
      final albumCandidateSongPaths = songs
          .where((song) => !playlistFolderSongPaths.contains(song.filePath))
          .map((song) => song.filePath)
          .toSet();
      final duplicateGroups = await duplicateDetector.detectDuplicates(
        songs,
        cachedHashes: cachedHashes,
        preferredPaths: albumCandidateSongPaths,
      );
      final uniqueSongs =
          duplicateDetector.filterDuplicates(songs, duplicateGroups);

      // Store computed hashes back in cache for future scans
      for (final entry in duplicateDetector.computedHashes.entries) {
        final cached = updatedCache[entry.key];
        if (cached != null) {
          cached['partialHash'] = entry.value;
        }
      }

      _sendProgress(sendPort, 'duplicates', uniqueSongs.length, songs.length,
          85.0, '${uniqueSongs.length} unique songs after filtering');

      // Step 3.5: Classify unmarked folders. High-confidence mixed folders
      // auto-import: they join playlistFolders here, BEFORE album building,
      // so the artifact-tag guard, playlist building, natural ordering, and
      // stable IDs all treat them exactly like [PLAYLIST] folders.
      // Medium-confidence folders stay advisory suggestions. User "ignore"
      // decisions block both.
      final classification = const PlaylistFolderClassifier().classify(
        songs: uniqueSongs,
        libraryRootPath: folderPath,
        explicitPlaylistFolderPaths: playlistFolders.keys.toSet(),
        ignoredFolderPaths: params.ignoredSuggestionFolderPaths
            .map(path.normalize)
            .toSet(),
      );

      // A folder with an explicit playlist folder somewhere inside it is
      // demoted to a suggestion: importing it would make incremental
      // rebuilds (which collapse nested playlist paths to the outermost)
      // swallow the inner playlist.
      final autoImports = <PlaylistSuggestion>[];
      final playlistSuggestions = [...classification.suggestions];
      for (final autoImport in classification.autoImports) {
        final prefix = '${autoImport.folderPath}${path.separator}';
        if (playlistFolders.keys.any((p) => p.startsWith(prefix))) {
          playlistSuggestions.add(autoImport);
        } else {
          autoImports.add(autoImport);
        }
      }
      playlistSuggestions
          .sort((a, b) => a.folderPath.compareTo(b.folderPath));

      // Membership mirrors [PLAYLIST] collection: recursive, keeps duplicate
      // copies (their IDs remap to the surviving song later), and never
      // steals a file already owned by an explicit playlist folder.
      final explicitPlaylistFilePaths =
          playlistFolders.values.expand((paths) => paths).toSet();
      for (final autoImport in autoImports) {
        playlistFolders[autoImport.folderPath] = audioFiles
            .where((filePath) =>
                filePath.startsWith(
                    '${autoImport.folderPath}${path.separator}') &&
                !explicitPlaylistFilePaths.contains(filePath))
            .toList();
      }
      if (autoImports.isNotEmpty) {
        _sendProgress(sendPort, 'playlists', autoImports.length,
            autoImports.length, 85.0,
            'Auto-imported ${autoImports.length} playlist folder(s)');
      }

      // Step 4: Build albums
      // Playlist membership is additive: songs under [PLAYLIST] folders join
      // album grouping (or become standalone) like any other track, and also
      // appear in their folder playlist. Exception: album tags that are
      // downloader artifacts (a playlist name written into the album field)
      // — those tracks stay standalone.
      _sendProgress(sendPort, 'albums', 0, uniqueSongs.length, 85.0,
          'Building album structure...');

      final suspiciousTagPaths = suspiciousPlaylistAlbumTagPaths(
        songs: uniqueSongs,
        playlistFolders: playlistFolders,
      );
      final albumCandidateSongs = uniqueSongs
          .where((song) => !suspiciousTagPaths.contains(song.filePath))
          .toList();
      final suppressedAlbumSongs = uniqueSongs
          .where((song) => suspiciousTagPaths.contains(song.filePath))
          .toList();

      final albumBuilder = AlbumBuilder(metadataExtractor: extractor);
      final baseLibrary =
          await albumBuilder.buildLibraryAsync(albumCandidateSongs);

      // Step 5: Build folder playlists
      // First, build a map from duplicate file paths to their "original" paths
      // This ensures playlist song IDs match the library (duplicates are filtered out)
      final duplicateToOriginalPath = <String, String>{};
      for (final group in duplicateGroups) {
        for (final duplicate in group.duplicates) {
          duplicateToOriginalPath[duplicate.filePath] = group.original.filePath;
        }
      }

      final folderPlaylistsList = <FolderPlaylist>[];
      for (final entry in playlistFolders.entries) {
        final folderPath = entry.key;
        final filePaths = entry.value;

        // Skip empty playlist folders
        if (filePaths.isEmpty) continue;

        // Canonical playlist order: natural path order (numeric-aware, so
        // "2" < "10" < "100"), matching incremental rebuilds so watcher
        // updates never silently reorder a playlist.
        final sortedPaths = List<String>.from(filePaths)
          ..sort(compareNaturalPath);

        // Convert file paths to song IDs, mapping duplicates to their originals
        final songIds = sortedPaths.map((fp) {
          // If this file is a duplicate, use the original's path for ID generation
          final originalPath = duplicateToOriginalPath[fp] ?? fp;
          return _generateSongId(originalPath);
        }).toList();

        final playlist = FolderPlaylist(
          id: FolderPlaylist.generateId(folderPath),
          name: FolderPlaylist.extractName(path.basename(folderPath)),
          folderPath: folderPath,
          songIds: songIds,
        );
        folderPlaylistsList.add(playlist);
      }

      // Step 6: Import M3U/M3U8 playlists. Explicit sources, imported
      // automatically; a malformed file only produces a diagnostic.
      final uniqueSongPaths =
          uniqueSongs.map((song) => song.filePath).toSet();
      final m3uPlaylists = await _buildM3uPlaylists(
        m3uFiles: m3uFiles,
        uniqueSongPaths: uniqueSongPaths,
        duplicateToOriginalPath: duplicateToOriginalPath,
        recordFailure: recordFailure,
      );
      folderPlaylistsList.addAll(m3uPlaylists);

      folderPlaylistsList
          .sort((a, b) => a.folderPath.compareTo(b.folderPath));

      // Step 7: Medium-confidence suggestions were classified in step 3.5
      // (advisory only — surfaced in scan diagnostics for the approval UI).

      // Create final library with playlists
      final library = LibraryStructure(
        albums: baseLibrary.albums,
        standaloneSongs: <SongMetadata>[
          ...baseLibrary.standaloneSongs,
          ...suppressedAlbumSongs,
        ],
        folderPlaylists: folderPlaylistsList,
        duplicateToOriginalPath: duplicateToOriginalPath,
      );

      final cacheStats = existingCache.isNotEmpty
          ? ' (cache: $cacheHits hits, $cacheMisses extractions)'
          : '';
      final playlistStats = folderPlaylistsList.isNotEmpty
          ? ', ${folderPlaylistsList.length} playlists'
          : '';
      _sendProgress(
          sendPort,
          'complete',
          library.totalSongs,
          library.totalSongs,
          100.0,
          'Scan complete: ${library.totalAlbums} albums, ${library.totalSongs} songs$playlistStats$cacheStats');

      // Send the result with updated cache
      sendPort.send(ScanResultMessage(
        type: ScanMessageType.complete,
        library: library,
        scanTime: DateTime.now(),
        updatedCache: updatedCache,
        cacheHits: cacheHits,
        cacheMisses: cacheMisses,
        failedFiles: failedFiles,
        skippedFileCount: skippedFileCount,
        playlistSuggestions: playlistSuggestions,
        autoImportedPlaylistFolders: autoImports,
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
  static Future<({SongMetadata metadata, int mtime, int size, bool fromCache})?>
      _extractOrUseCached(
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

        // Validate cache entry and only trust it when duration data is already
        // present. Older cache entries without duration should be refreshed.
        if (cachedMtime == currentMtime && cachedSize == currentSize) {
          final metadataJson = cached['metadata'] as Map<String, dynamic>?;
          final cachedDuration = metadataJson?['duration'] as int?;
          if (metadataJson != null &&
              cachedDuration != null &&
              cachedDuration > 0) {
            var metadata = SongMetadata.fromJson(metadataJson);
            if (metadata.trackNumber == null) {
              final inferredTrack =
                  _inferTrackNumberFromPath(metadata.filePath);
              if (inferredTrack != null) {
                metadata = metadata.copyWith(trackNumber: inferredTrack);
              }
            }
            return (
              metadata: metadata,
              mtime: currentMtime,
              size: currentSize,
              fromCache: true,
            );
          }
        }
      }

      // Cache miss (or stale partial metadata) - extract metadata and duration
      // in a single pass so the scan persists ready-to-use durations.
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

  /// Checks if an entry name is hidden or system (e.g., .DS_Store, ._AppleDouble)
  static bool _isHiddenName(String name) {
    return name.startsWith('.') && name.length > 1;
  }

  /// Collect audio files from directory and detect [PLAYLIST] folders
  ///
  /// Uses an explicit directory stack instead of `list(recursive: true)` so a
  /// single unreadable directory (permissions, dead mount, I/O error) skips
  /// only that subtree instead of aborting the entire scan. Listing each
  /// directory ourselves also guarantees parents are seen before children, so
  /// [PLAYLIST] folder membership no longer depends on OS listing order.
  ///
  /// [approvedPlaylistFolderPaths] (normalized) are user-approved suggestion
  /// folders; they join the playlist set exactly like marker folders, so
  /// membership, nesting collapse, dedupe preference, the artifact-tag guard,
  /// and natural ordering all apply unchanged. Their display name is the
  /// plain basename (no marker to strip).
  ///
  /// Hidden entries (dot-prefixed names) are skipped and not descended into.
  /// Only entry names below the root are checked, so a library that itself
  /// lives under a dotted directory (e.g. ~/.local/music) still scans.
  static Future<
      ({
        List<String> files,
        Map<String, List<String>> playlistFolders,
        List<String> m3uFiles,
        List<({String path, String reason})> unreadableDirectories,
      })> _collectAudioFiles(
    String folderPath, {
    Set<String> approvedPlaylistFolderPaths = const {},
  }) async {
    final files = <String>[];
    final playlistFolders = <String, List<String>>{};
    final playlistPaths = <String>{};
    final m3uFiles = <String>[];
    final unreadableDirectories = <({String path, String reason})>[];
    final rootDir = Directory(folderPath);

    if (!await rootDir.exists()) {
      return (
        files: files,
        playlistFolders: playlistFolders,
        m3uFiles: m3uFiles,
        unreadableDirectories: unreadableDirectories,
      );
    }

    final pending = <Directory>[rootDir];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();

      final entries = <FileSystemEntity>[];
      try {
        await for (final entity in dir.list(followLinks: false)) {
          entries.add(entity);
        }
      } catch (e) {
        unreadableDirectories.add((path: dir.path, reason: e.toString()));
        continue;
      }

      for (final entity in entries) {
        if (_isHiddenName(path.basename(entity.path))) continue;

        if (entity is Directory) {
          final folderName = path.basename(entity.path);
          if (FolderPlaylist.isPlaylistFolder(folderName) ||
              approvedPlaylistFolderPaths
                  .contains(path.normalize(entity.path))) {
            // Check this isn't nested inside another playlist folder
            final isNested = playlistPaths
                .any((p) => entity.path.startsWith('$p${path.separator}'));
            if (!isNested) {
              playlistPaths.add(entity.path);
              playlistFolders[entity.path] = [];
            }
          }
          pending.add(entity);
        } else if (entity is File) {
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
          } else if (M3uPlaylistParser.isM3uFile(entity.path)) {
            m3uFiles.add(entity.path);
          }
        }
      }
    }

    return (
      files: files,
      playlistFolders: playlistFolders,
      m3uFiles: m3uFiles,
      unreadableDirectories: unreadableDirectories,
    );
  }

  /// Builds playlists from `.m3u`/`.m3u8` files found during the scan.
  ///
  /// Entries resolve against the playlist file's directory, keep file order,
  /// map deduped copies to their canonical song, and are deduplicated so the
  /// same song never appears twice. Entries that don't match any scanned
  /// audio file are recorded as scan diagnostics. Malformed playlist files
  /// never abort the scan.
  static Future<List<FolderPlaylist>> _buildM3uPlaylists({
    required List<String> m3uFiles,
    required Set<String> uniqueSongPaths,
    required Map<String, String> duplicateToOriginalPath,
    required void Function(String filePath, String reason) recordFailure,
  }) async {
    const parser = M3uPlaylistParser();
    final playlists = <FolderPlaylist>[];

    for (final m3uPath in m3uFiles) {
      final parsed = await parser.parseFile(m3uPath);
      if (parsed.isMalformed) {
        recordFailure(m3uPath, 'M3U playlist ${parsed.malformedReason}');
        continue;
      }

      final songIds = <String>[];
      final seenIds = <String>{};
      var missingEntryCount = 0;
      for (final entry in parsed.entries) {
        final canonicalPath = duplicateToOriginalPath[entry] ?? entry;
        if (!uniqueSongPaths.contains(canonicalPath)) {
          missingEntryCount++;
          if (missingEntryCount <= 5) {
            recordFailure(
                entry, 'M3U entry not found in library (${path.basename(m3uPath)})');
          }
          continue;
        }
        final songId = _generateSongId(canonicalPath);
        if (seenIds.add(songId)) {
          songIds.add(songId);
        }
      }
      if (missingEntryCount > 5) {
        recordFailure(
            m3uPath,
            'M3U playlist has $missingEntryCount entries not found in '
            'library (first 5 listed individually)');
      }

      if (songIds.isEmpty) continue;

      playlists.add(FolderPlaylist(
        id: FolderPlaylist.generateId(m3uPath),
        name: path.basenameWithoutExtension(m3uPath),
        folderPath: m3uPath,
        songIds: songIds,
      ));
    }

    return playlists;
  }

  /// Generate a unique song ID from file path (must match LibraryManager)
  static String _generateSongId(String filePath) {
    final bytes = utf8.encode(filePath);
    final hash = md5.convert(bytes);
    return hash.toString().substring(0, 12);
  }

  /// Infer track number from common numeric filename prefixes.
  static int? _inferTrackNumberFromPath(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath).trim();
    final match =
        RegExp(r'^(\d{1,3})(?:\s*[-._)]\s*|\s+)').firstMatch(fileName);
    if (match == null) return null;

    final parsed = int.tryParse(match.group(1)!);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
