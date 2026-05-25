import 'package:ariami_core/models/scan_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  group('ScanDiagnostics', () {
    test('toJson includes skipped count and bounded failed files', () {
      final failedFiles = List.generate(
        55,
        (index) => ScanFailedFile(
          path: '/music/file$index.mp3',
          reason: 'metadata extraction failed',
        ),
      );

      const diagnostics = ScanDiagnostics(
        skippedFileCount: 55,
        failedFiles: [],
      );

      final withFailures = ScanDiagnostics(
        skippedFileCount: 55,
        failedFiles: failedFiles.take(ScanDiagnostics.maxFailedFiles).toList(),
      );

      expect(diagnostics.toJson()['skippedFileCount'], 55);
      expect(withFailures.failedFiles.length, ScanDiagnostics.maxFailedFiles);
    });
  });
}
