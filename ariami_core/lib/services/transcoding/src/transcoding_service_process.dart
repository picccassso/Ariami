part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

extension _TranscodingServiceProcess on TranscodingService {
  Future<File?> _performDownloadTranscode(
    String sourcePath,
    String songId,
    QualityPreset quality,
    String lockKey,
  ) async {
    try {
      // Create temp directory if needed
      final tempDir = Directory('$cacheDirectory/tmp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // Generate unique temp filename
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = random.nextInt(999999).toString().padLeft(6, '0');
      final tempPath =
          '${tempDir.path}/${songId}_${timestamp}_$randomSuffix.${quality.fileExtension}';

      print('TranscodingService: Download transcode $songId to ${quality.name} '
          '(running: $_runningDownloadCount)');

      final result = await _transcodeFile(sourcePath, tempPath, quality);

      if (result != null) {
        _clearFailure(lockKey);
        return result;
      }

      _recordFailure(lockKey, 'Download transcode returned null');
      return null;
    } catch (e) {
      print('TranscodingService: Download transcode error - $e');
      _recordFailure(lockKey, e.toString());
      return null;
    }
  }

  /// Get the cached file path for a song at a specific quality.
  File _getCachedFile(String songId, QualityPreset quality) {
    final qualityDir = Directory('$cacheDirectory/${quality.name}');
    return File('${qualityDir.path}/$songId.${quality.fileExtension}');
  }

  /// Transcode a file using Sonic.
  Future<File?> _transcodeFile(
    String sourcePath,
    String outputPath,
    QualityPreset quality,
  ) async {
    // Ensure output directory exists
    final outputDir = Directory(outputPath).parent;
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      print('TranscodingService: Source file missing: $sourcePath');
      return null;
    }

    final adapter = _sonicFfiAdapter;
    if (adapter == null) {
      print('TranscodingService: Sonic adapter is not initialized');
      return null;
    }

    final preset = _sonicPresetForQuality(quality);
    print(
        'TranscodingService: Running Sonic FFI (${adapter.libraryPath}, preset=$preset)');

    Future<void> cleanupPartialOutput() async {
      try {
        final partialFile = File(outputPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
    }

    try {
      final pathResult = await adapter.transcodeFileToFileAsync(
        sourcePath,
        outputPath,
        preset,
      );

      if (pathResult.status == _SonicFfiAdapter.statusOk) {
        print('TranscodingService: Sonic FFI file-to-file path succeeded');
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          final size = await outputFile.length();
          print(
              'TranscodingService: Transcode complete - ${(size / 1024).round()} KB');
          return outputFile;
        }
      } else if (pathResult.status != _SonicFfiAdapter.statusNotImplemented) {
        print(
            'TranscodingService: Sonic FFI file transcode failed (status ${pathResult.status})');
        if (pathResult.errorMessage != null &&
            pathResult.errorMessage!.isNotEmpty) {
          print('TranscodingService: Sonic error: ${pathResult.errorMessage}');
        }
        await cleanupPartialOutput();
        return null;
      }

      // Backward compatibility path for older Sonic builds without file API.
      print(
          'TranscodingService: Sonic file API unavailable, falling back to buffer API');
      final inputBytes = await sourceFile.readAsBytes();
      final result = adapter.transcode(inputBytes, preset);
      final outputBytes = result.outputBytes;
      if (result.status == _SonicFfiAdapter.statusOk &&
          outputBytes != null &&
          outputBytes.isNotEmpty) {
        final outputFile = File(outputPath);
        await outputFile.writeAsBytes(outputBytes, flush: true);
        final size = await outputFile.length();
        print(
            'TranscodingService: Transcode complete - ${(size / 1024).round()} KB');
        return outputFile;
      }

      print('TranscodingService: Sonic FFI failed (status ${result.status})');
      if (result.errorMessage != null && result.errorMessage!.isNotEmpty) {
        print('TranscodingService: Sonic error: ${result.errorMessage}');
      }
      await cleanupPartialOutput();
      return null;
    } catch (e) {
      print('TranscodingService: Sonic FFI error - $e');
      await cleanupPartialOutput();
      return null;
    }
  }
}
