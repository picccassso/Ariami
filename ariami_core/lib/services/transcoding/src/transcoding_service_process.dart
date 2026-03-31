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

  /// Transcode a file using FFmpeg.
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

    // Build FFmpeg command (async for platform-aware codec detection)
    final args = await _buildFFmpegArgs(sourcePath, outputPath, quality);

    print('TranscodingService: Running ffmpeg ${args.join(' ')}');

    try {
      final result = await Process.run(
        'ffmpeg',
        args,
      ).timeout(
        transcodeTimeout,
        onTimeout: () {
          print(
              'TranscodingService: Transcode timeout after ${transcodeTimeout.inMinutes} minutes');
          return ProcessResult(-1, -1, '', 'Timeout');
        },
      );

      if (result.exitCode == 0) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          print(
              'TranscodingService: Transcode complete - ${(size / 1024).round()} KB');
          return outputFile;
        }
      }

      print('TranscodingService: FFmpeg failed (exit ${result.exitCode})');
      print('TranscodingService: stderr: ${result.stderr}');

      // Clean up partial file if it exists
      final partialFile = File(outputPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      return null;
    } catch (e) {
      print('TranscodingService: FFmpeg error - $e');

      // Clean up partial file
      try {
        final partialFile = File(outputPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}

      return null;
    }
  }
}
