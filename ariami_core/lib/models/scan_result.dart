/// Represents the current progress of a directory scan
class ScanProgress {
  /// Number of audio files found so far
  final int filesFound;

  /// Number of directories that have been scanned
  final int directoriesScanned;

  /// The current directory or file path being processed
  final String currentPath;

  /// Percentage of completion (0.0 to 1.0)
  final double percentage;

  const ScanProgress({
    required this.filesFound,
    required this.directoriesScanned,
    required this.currentPath,
    required this.percentage,
  });

  @override
  String toString() {
    return 'ScanProgress(files: $filesFound, dirs: $directoriesScanned, '
        'progress: ${(percentage * 100).toStringAsFixed(1)}%)';
  }
}

/// Represents the final result of a directory scan
class ScanResult {
  /// List of all audio file paths found
  final List<String> filePaths;

  /// Total number of directories scanned
  final int totalDirectories;

  /// Total time taken for the scan
  final Duration scanDuration;

  /// Any errors encountered during scanning
  final List<ScanError> errors;

  const ScanResult({
    required this.filePaths,
    required this.totalDirectories,
    required this.scanDuration,
    this.errors = const [],
  });

  /// Total number of files found
  int get totalFiles => filePaths.length;

  /// Whether the scan completed without errors
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() {
    return 'ScanResult(files: $totalFiles, dirs: $totalDirectories, '
        'duration: ${scanDuration.inSeconds}s, errors: ${errors.length})';
  }
}

/// Represents an error encountered during scanning
class ScanError {
  /// The path where the error occurred
  final String path;

  /// The error message
  final String message;

  /// The type of error
  final ScanErrorType type;

  const ScanError({
    required this.path,
    required this.message,
    required this.type,
  });

  @override
  String toString() {
    return 'ScanError($type: $path - $message)';
  }
}

/// Types of errors that can occur during scanning
enum ScanErrorType {
  permissionDenied,
  pathNotFound,
  invalidPath,
  unknown,
}
