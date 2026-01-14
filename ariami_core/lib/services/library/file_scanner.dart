import 'dart:io';
import 'package:ariami_core/models/scan_result.dart';

/// Service for scanning directories and discovering audio files
class FileScanner {
  /// Supported audio file extensions
  static const supportedExtensions = [
    '.mp3', '.m4a', '.mp4', // Common formats
    '.flac', '.wav', '.aiff', // Lossless formats
    '.ogg', '.opus', '.wma', // Other formats
    '.aac', '.alac', // Apple formats
  ];

  /// Scans a directory recursively for audio files
  ///
  /// Yields [ScanProgress] events as the scan progresses.
  /// Uses single-pass traversal for efficiency.
  Stream<ScanProgress> scanDirectory(String path) async* {
    final foundFiles = <String>[];
    final errors = <ScanError>[];
    int directoriesScanned = 0;

    // Verify the root path exists
    final rootDir = Directory(path);
    if (!await rootDir.exists()) {
      yield ScanProgress(
        filesFound: 0,
        directoriesScanned: 0,
        currentPath: path,
        percentage: 1.0,
      );
      return;
    }

    // Single-pass traversal: collect files and count directories simultaneously
    try {
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          if (!_isHiddenOrSystem(entity.path)) {
            directoriesScanned++;
          }
        } else if (entity is File) {
          // Skip files in hidden directories
          if (_isHiddenOrSystem(entity.path)) continue;

          final filePath = entity.path;
          if (_isSupportedAudioFile(filePath)) {
            foundFiles.add(filePath);

            // Yield progress every 100 files
            if (foundFiles.length % 100 == 0) {
              yield ScanProgress(
                filesFound: foundFiles.length,
                directoriesScanned: directoriesScanned,
                currentPath: filePath,
                // Use file count for progress (more meaningful than directory count)
                percentage: 0.5, // Approximate - we don't know total until done
              );
            }
          }
        }
      }
    } catch (e) {
      errors.add(ScanError(
        path: path,
        message: e.toString(),
        type: _categorizeError(e),
      ));
    }

    // Yield final progress
    yield ScanProgress(
      filesFound: foundFiles.length,
      directoriesScanned: directoriesScanned,
      currentPath: '',
      percentage: 1.0,
    );
  }

  /// Collects all audio files in a single pass (internal use)
  ///
  /// Returns a record with found files, directory count, and errors.
  Future<({List<String> files, int directories, List<ScanError> errors})>
      _collectAudioFiles(String path) async {
    final foundFiles = <String>[];
    final errors = <ScanError>[];
    int directoriesScanned = 0;

    final rootDir = Directory(path);
    if (!await rootDir.exists()) {
      return (files: foundFiles, directories: 0, errors: errors);
    }

    try {
      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          if (!_isHiddenOrSystem(entity.path)) {
            directoriesScanned++;
          }
        } else if (entity is File) {
          // Skip files in hidden directories
          if (_isHiddenOrSystem(entity.path)) continue;

          if (_isSupportedAudioFile(entity.path)) {
            foundFiles.add(entity.path);
          }
        }
      }
    } catch (e) {
      errors.add(ScanError(
        path: path,
        message: e.toString(),
        type: _categorizeError(e),
      ));
    }

    return (files: foundFiles, directories: directoriesScanned, errors: errors);
  }

  /// Checks if a file path has a supported audio extension
  bool _isSupportedAudioFile(String path) {
    final extension = _getFileExtension(path).toLowerCase();
    return supportedExtensions.contains(extension);
  }

  /// Gets the file extension including the dot (e.g., '.mp3')
  String _getFileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) {
      return '';
    }
    return path.substring(lastDot);
  }

  /// Checks if a path is a hidden or system directory
  bool _isHiddenOrSystem(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (final part in parts) {
      if (part.startsWith('.') && part.length > 1) {
        return true;
      }
    }
    return false;
  }

  /// Categorizes an error based on its type
  ScanErrorType _categorizeError(dynamic error) {
    if (error is FileSystemException) {
      if (error.osError?.errorCode == 13 || // Permission denied on Unix
          error.osError?.errorCode == 5) {   // Access denied on Windows
        return ScanErrorType.permissionDenied;
      }
      if (error.osError?.errorCode == 2) {   // No such file or directory
        return ScanErrorType.pathNotFound;
      }
    }
    return ScanErrorType.unknown;
  }

  /// Scans a directory and returns the complete result
  ///
  /// Uses single-pass traversal for efficiency - no redundant directory scans.
  Future<ScanResult> scanDirectoryComplete(String path) async {
    final startTime = DateTime.now();

    // Single-pass collection (no redundant traversals)
    final result = await _collectAudioFiles(path);

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    return ScanResult(
      filePaths: result.files,
      totalDirectories: result.directories,
      scanDuration: duration,
      errors: result.errors,
    );
  }
}
