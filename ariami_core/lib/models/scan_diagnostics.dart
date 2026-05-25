/// A file that could not be processed during library scan.
class ScanFailedFile {
  const ScanFailedFile({
    required this.path,
    required this.reason,
  });

  final String path;
  final String reason;

  Map<String, dynamic> toJson() => {
        'path': path,
        'reason': reason,
      };
}

/// Structured diagnostics from the most recent library scan.
class ScanDiagnostics {
  static const int maxFailedFiles = 50;

  const ScanDiagnostics({
    this.skippedFileCount = 0,
    this.failedFiles = const [],
  });

  final int skippedFileCount;
  final List<ScanFailedFile> failedFiles;

  Map<String, dynamic> toJson() => {
        'skippedFileCount': skippedFileCount,
        'failedFiles': failedFiles.map((f) => f.toJson()).toList(),
      };
}
