import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:bma_core/models/library_structure.dart';
import 'package:bma_core/models/song_metadata.dart';
import 'package:bma_core/services/library/file_scanner.dart';
import 'package:bma_core/services/library/metadata_extractor.dart';
import 'package:bma_core/services/library/album_builder.dart';
import 'package:bma_core/services/library/duplicate_detector.dart';

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

  const ScanResultMessage({
    required this.type,
    this.library,
    this.error,
    required this.scanTime,
  });
}

/// Parameters passed to the isolate entry point
class ScanParams {
  final String folderPath;
  final SendPort sendPort;

  const ScanParams({
    required this.folderPath,
    required this.sendPort,
  });
}

/// Library scanner that runs in a background isolate
/// 
/// This prevents UI blocking during library scans by moving all
/// heavy I/O and processing to a separate isolate.
class LibraryScannerIsolate {
  /// Spawn an isolate to scan the library and return the result
  /// 
  /// Progress updates are sent via [onProgress] callback.
  /// Returns the scanned [LibraryStructure] or null on error.
  static Future<LibraryStructure?> scan(
    String folderPath, {
    void Function(ScanProgressMessage)? onProgress,
  }) async {
    final receivePort = ReceivePort();
    
    try {
      // Spawn the isolate
      await Isolate.spawn(
        _isolateEntryPoint,
        ScanParams(
          folderPath: folderPath,
          sendPort: receivePort.sendPort,
        ),
      );

      // Listen for messages from the isolate
      LibraryStructure? result;
      String? errorMessage;

      await for (final message in receivePort) {
        if (message is ScanProgressMessage) {
          onProgress?.call(message);
        } else if (message is ScanResultMessage) {
          if (message.type == ScanMessageType.complete) {
            result = message.library;
          } else if (message.type == ScanMessageType.error) {
            errorMessage = message.error;
          }
          break; // Done - exit the loop
        }
      }

      if (errorMessage != null) {
        print('[LibraryScannerIsolate] Scan failed: $errorMessage');
        return null;
      }

      return result;
    } catch (e) {
      print('[LibraryScannerIsolate] Error spawning isolate: $e');
      return null;
    } finally {
      receivePort.close();
    }
  }

  /// Entry point for the isolate - must be a top-level or static function
  static Future<void> _isolateEntryPoint(ScanParams params) async {
    final sendPort = params.sendPort;
    final folderPath = params.folderPath;

    try {
      // Step 1: Collect audio files
      _sendProgress(sendPort, 'collecting', 0, 0, 0.0, 'Scanning for audio files...');
      
      final audioFiles = await _collectAudioFiles(folderPath);
      final totalFiles = audioFiles.length;
      
      _sendProgress(sendPort, 'collecting', totalFiles, totalFiles, 10.0, 
          'Found $totalFiles audio files');

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
        ));
        return;
      }

      // Step 2: Extract metadata (parallel batches)
      _sendProgress(sendPort, 'metadata', 0, totalFiles, 10.0, 
          'Extracting metadata...');
      
      final extractor = MetadataExtractor();
      final songs = <SongMetadata>[];
      
      const batchSize = 15;
      for (var i = 0; i < totalFiles; i += batchSize) {
        final batchEnd = (i + batchSize < totalFiles) ? i + batchSize : totalFiles;
        final batch = audioFiles.sublist(i, batchEnd);
        
        // Process batch in parallel
        final results = await Future.wait(
          batch.map((filePath) => _extractFileData(extractor, filePath)),
        );
        
        // Collect successful results
        for (final result in results) {
          if (result != null) {
            songs.add(result);
          }
        }
        
        // Calculate progress (10% to 70% for metadata extraction)
        final metadataProgress = 10.0 + (batchEnd / totalFiles) * 60.0;
        _sendProgress(sendPort, 'metadata', batchEnd, totalFiles, metadataProgress,
            'Processed $batchEnd/$totalFiles files');
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
      final library = albumBuilder.buildLibrary(uniqueSongs);
      
      _sendProgress(sendPort, 'complete', library.totalSongs, library.totalSongs, 100.0,
          'Scan complete: ${library.totalAlbums} albums, ${library.totalSongs} songs');

      // Send the result
      sendPort.send(ScanResultMessage(
        type: ScanMessageType.complete,
        library: library,
        scanTime: DateTime.now(),
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

  /// Collect audio files from directory
  static Future<List<String>> _collectAudioFiles(String folderPath) async {
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

  /// Extract metadata from a single file
  static Future<SongMetadata?> _extractFileData(
    MetadataExtractor extractor,
    String filePath,
  ) async {
    try {
      return await extractor.extractMetadataWithDuration(filePath);
    } catch (e) {
      // Log but don't throw - just skip this file
      print('[LibraryScannerIsolate] Failed to extract metadata from $filePath: $e');
      return null;
    }
  }
}

