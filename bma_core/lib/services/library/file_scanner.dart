import 'dart:io';
import 'package:bma_core/models/scan_result.dart';

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
  /// Yields [ScanProgress] events as the scan progresses
  /// Returns a stream that completes when scanning is done
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

    // Build directory tree first for accurate progress tracking
    final allDirectories = <Directory>[];
    try {
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is Directory && !_isHiddenOrSystem(entity.path)) {
          allDirectories.add(entity);
        }
      }
    } catch (e) {
      // If we can't list directories, just scan the root
      allDirectories.add(rootDir);
    }

    final totalDirectories = allDirectories.isEmpty ? 1 : allDirectories.length;

    // Add root directory to scan
    if (allDirectories.isEmpty) {
      allDirectories.add(rootDir);
    }

    // Scan each directory
    for (final directory in allDirectories) {
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File) {
            final filePath = entity.path;
            if (_isSupportedAudioFile(filePath)) {
              foundFiles.add(filePath);

              // Yield progress every 100 files or at the end
              if (foundFiles.length % 100 == 0 ||
                  directoriesScanned == totalDirectories - 1) {
                yield ScanProgress(
                  filesFound: foundFiles.length,
                  directoriesScanned: directoriesScanned + 1,
                  currentPath: filePath,
                  percentage: (directoriesScanned + 1) / totalDirectories,
                );
              }
            }
          }
        }
        directoriesScanned++;
      } catch (e) {
        // Handle permission errors and continue scanning
        errors.add(ScanError(
          path: directory.path,
          message: e.toString(),
          type: _categorizeError(e),
        ));
        directoriesScanned++;
      }
    }

    // Yield final progress
    yield ScanProgress(
      filesFound: foundFiles.length,
      directoriesScanned: directoriesScanned,
      currentPath: '',
      percentage: 1.0,
    );
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
  /// This is a convenience method that collects all progress updates
  /// and returns the final result
  Future<ScanResult> scanDirectoryComplete(String path) async {
    final startTime = DateTime.now();
    final foundFiles = <String>[];
    final errors = <ScanError>[];
    int totalDirectories = 0;

    await for (final progress in scanDirectory(path)) {
      totalDirectories = progress.directoriesScanned;

      // Collect files by rescanning (in a real implementation,
      // you might want to modify scanDirectory to also yield the files)
    }

    // Perform a final scan to collect all files
    final rootDir = Directory(path);
    if (await rootDir.exists()) {
      try {
        await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
          if (entity is File && _isSupportedAudioFile(entity.path)) {
            foundFiles.add(entity.path);
          }
        }
      } catch (e) {
        errors.add(ScanError(
          path: path,
          message: e.toString(),
          type: _categorizeError(e),
        ));
      }
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    return ScanResult(
      filePaths: foundFiles,
      totalDirectories: totalDirectories,
      scanDuration: duration,
      errors: errors,
    );
  }
}
