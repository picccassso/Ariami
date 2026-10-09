part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

class _TranscodeTask {
  final String sourcePath;
  final String songId;
  final QualityPreset quality;
  final TranscodeOutputFormat outputFormat;
  final Completer<File?> completer;
  final int? sourceBitrateKbps;

  _TranscodeTask({
    required this.sourcePath,
    required this.songId,
    required this.quality,
    this.outputFormat = TranscodeOutputFormat.aac,
    required this.completer,
    this.sourceBitrateKbps,
  });
}

class _CacheIndexEntry {
  final String path;
  final int size;
  DateTime lastAccess;

  _CacheIndexEntry({
    required this.path,
    required this.size,
    required this.lastAccess,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'lastAccess': lastAccess.toIso8601String(),
      };

  factory _CacheIndexEntry.fromJson(Map<String, dynamic> json) =>
      _CacheIndexEntry(
        path: json['path'] as String,
        size: json['size'] as int,
        lastAccess: DateTime.parse(json['lastAccess'] as String),
      );
}

class _FailureRecord {
  final DateTime lastFailure;
  final int failureCount;
  final String? errorMessage;

  _FailureRecord({
    required this.lastFailure,
    required this.failureCount,
    this.errorMessage,
  });
}

class _AudioProperties {
  final String? codec;
  final int? bitrate; // bits per second
  final int? sampleRate;

  _AudioProperties({
    this.codec,
    this.bitrate,
    this.sampleRate,
  });

  bool shouldSkipTranscode(QualityPreset quality) {
    if (bitrate == null) return false;
    final targetBps = (quality.bitrate ?? 0) * 1000; // kbps to bps
    return bitrate! <= targetBps;
  }
}

/// Result of a download transcode operation.
///
/// Contains a temporary file that should be deleted by the caller
/// after the download completes.
class DownloadTranscodeResult {
  final File tempFile;

  /// Whether the caller should delete this file after use.
  final bool shouldDelete;

  DownloadTranscodeResult({
    required this.tempFile,
    required this.shouldDelete,
  });

  /// Delete the temporary file. Call this after download completes.
  Future<void> cleanup() async {
    if (shouldDelete) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }
}
