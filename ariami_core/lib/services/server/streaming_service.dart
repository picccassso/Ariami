import 'dart:io';
import 'package:shelf/shelf.dart';

/// Service for streaming audio files with HTTP range request support
class StreamingService {
  static const Duration _growingFilePollInterval = Duration(milliseconds: 15);

  /// Stream an audio file by file path
  /// Supports HTTP range requests for seeking
  Future<Response> streamFile(
    File audioFile,
    Request request, {
    void Function()? onDone,
  }) async {
    try {
      // Check if file exists
      if (!await audioFile.exists()) {
        onDone?.call();
        return Response.notFound('File not found');
      }

      // Get file size
      final fileSize = await audioFile.length();

      // Parse range header if present
      final rangeHeader = request.headers['range'];
      final range =
          rangeHeader != null ? RangeHeader.parse(rangeHeader, fileSize) : null;

      // Determine content range
      final int start = range?.start ?? 0;
      final int end = range?.end ?? (fileSize - 1);
      final int contentLength = end - start + 1;

      // Validate range
      if (start < 0 || end >= fileSize || start > end) {
        onDone?.call();
        return Response(
          416, // Range Not Satisfiable
          body: 'Invalid range',
          headers: {
            'Content-Range': 'bytes */$fileSize',
          },
        );
      }

      // Get MIME type
      final mimeType = getAudioMimeType(audioFile.path);

      // Build headers
      final headers = <String, String>{
        'Content-Type': mimeType,
        'Accept-Ranges': 'bytes',
        'Content-Length': contentLength.toString(),
        'Cache-Control': 'no-cache',
      };

      // Add range headers if this is a range request
      if (range != null) {
        headers['Content-Range'] = 'bytes $start-$end/$fileSize';
      }

      // Open file and create stream
      final RandomAccessFile raf = await audioFile.open(mode: FileMode.read);
      await raf.setPosition(start);

      // Create stream that reads specified range
      final stream = _createRangeStream(raf, start, end, onDone: onDone);

      // Return appropriate response
      if (range != null) {
        // Partial content response
        return Response(
          206, // Partial Content
          body: stream,
          headers: headers,
        );
      } else {
        // Full content response
        return Response.ok(
          stream,
          headers: headers,
        );
      }
    } catch (e) {
      print('Error streaming file: $e');
      onDone?.call();
      return Response.internalServerError(body: 'Error streaming file: $e');
    }
  }

  /// Starts serving a cold AAC transcode as soon as Sonic writes its first
  /// bytes. Returning null means transcoding was skipped/failed and the caller
  /// should serve the original source instead.
  ///
  /// Non-zero range requests still wait for the completed cache file because a
  /// stable length is required for correct seek semantics. Initial playback is
  /// chunked, allowing time-to-first-audio to overlap the remaining transcode.
  Future<Response?> streamGrowingTranscode({
    required File partialFile,
    required Future<File?> completion,
    required Request request,
    required String mimeType,
    DateTime? partialNotBefore,
    void Function()? onDone,
  }) async {
    final rangeHeader = request.headers[HttpHeaders.rangeHeader];
    if (rangeHeader != null && !_isInitialRange(rangeHeader)) {
      final completed = await completion;
      if (completed == null) return null;
      return streamFile(completed, request, onDone: onDone);
    }

    var isComplete = false;
    File? completedFile;
    Object? completionError;
    completion.then<void>(
      (file) {
        completedFile = file;
        isComplete = true;
      },
      onError: (Object error, StackTrace _) {
        completionError = error;
        isComplete = true;
      },
    );

    while (true) {
      final partialIsCurrent = await _isCurrentPartialFile(
        partialFile,
        notBefore: partialNotBefore,
      );
      var partialLength = 0;
      if (partialIsCurrent) {
        try {
          partialLength = await partialFile.length();
        } catch (_) {
          // Renamed to the final path (or cleaned up after a failure) between
          // the two stats; the completion future decides on a later iteration.
        }
      }
      if (partialLength > 0) {
        return Response.ok(
          _createGrowingFileStream(
            partialFile,
            isComplete: () => isComplete,
            completedFile: () => completedFile,
            onDone: onDone,
          ),
          headers: <String, String>{
            HttpHeaders.contentTypeHeader: mimeType,
            HttpHeaders.cacheControlHeader: 'no-cache',
          },
        );
      }
      if (isComplete) {
        if (completionError != null || completedFile == null) return null;
        return streamFile(completedFile!, request, onDone: onDone);
      }
      await Future<void>.delayed(_growingFilePollInterval);
    }
  }

  Stream<List<int>> _createGrowingFileStream(
    File partialFile, {
    required bool Function() isComplete,
    required File? Function() completedFile,
    void Function()? onDone,
  }) async* {
    RandomAccessFile? raf;
    var position = 0;
    try {
      // The body stream is listened to slightly after the headers go out, so
      // the partial can complete (rename to the final path) in between. On
      // POSIX an already-open handle survives the rename, but the open itself
      // needs the fallback.
      raf = await _openGrowingSource(
        partialFile,
        isComplete: isComplete,
        completedFile: completedFile,
      );
      if (raf == null) return;
      while (true) {
        final activeFile = completedFile() ?? partialFile;
        int length;
        try {
          length = await activeFile.length();
        } catch (_) {
          length = position;
        }

        if (length > position) {
          final bytesToRead = (length - position).clamp(1, 64 * 1024);
          final chunk = await raf.read(bytesToRead);
          if (chunk.isNotEmpty) {
            position += chunk.length;
            yield chunk;
            continue;
          }
        }

        if (isComplete()) {
          final finalFile = completedFile();
          int finalLength;
          try {
            finalLength =
                finalFile == null ? position : await finalFile.length();
          } catch (_) {
            finalLength = position;
          }
          if (position >= finalLength) break;
        }
        await Future<void>.delayed(_growingFilePollInterval);
      }
    } finally {
      await raf?.close();
      onDone?.call();
    }
  }

  /// Opens the in-progress transcode for reading, falling back to the
  /// completed cache file when the rename beat us to it. Returns null when
  /// neither exists (the transcode failed before producing output).
  Future<RandomAccessFile?> _openGrowingSource(
    File partialFile, {
    required bool Function() isComplete,
    required File? Function() completedFile,
  }) async {
    while (true) {
      final completed = completedFile();
      if (completed != null) {
        try {
          return await completed.open(mode: FileMode.read);
        } catch (_) {
          return null;
        }
      }
      try {
        return await partialFile.open(mode: FileMode.read);
      } catch (_) {
        // Mid-rename; the completion future resolves imminently.
      }
      if (isComplete()) return null;
      await Future<void>.delayed(_growingFilePollInterval);
    }
  }

  bool _isInitialRange(String header) {
    final normalized = header.trim().toLowerCase();
    return normalized == 'bytes=0-';
  }

  Future<bool> _isCurrentPartialFile(
    File file, {
    DateTime? notBefore,
  }) async {
    if (!await file.exists()) return false;
    if (notBefore == null) return true;
    try {
      return !(await file.stat()).modified.isBefore(notBefore);
    } catch (_) {
      return false;
    }
  }

  /// Create a stream that reads a specific range from a file
  Stream<List<int>> _createRangeStream(
    RandomAccessFile raf,
    int start,
    int end, {
    void Function()? onDone,
  }) async* {
    const int chunkSize = 64 * 1024; // 64 KB chunks
    int remaining = end - start + 1;

    try {
      while (remaining > 0) {
        final int bytesToRead = remaining < chunkSize ? remaining : chunkSize;
        final List<int> chunk = await raf.read(bytesToRead);

        if (chunk.isEmpty) {
          break; // End of file
        }

        yield chunk;
        remaining -= chunk.length;
      }
    } finally {
      await raf.close();
      onDone?.call();
    }
  }

  /// Get MIME type for audio file based on extension
  String getAudioMimeType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;

    switch (extension) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'aiff':
      case 'aif':
        return 'audio/aiff';
      case 'ogg':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'alac':
        return 'audio/x-alac';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Represents an HTTP Range header
class RangeHeader {
  final int start;
  final int end;

  RangeHeader({
    required this.start,
    required this.end,
  });

  /// Parse Range header value
  /// Format: "bytes=start-end" or "bytes=start-"
  /// Returns null if parsing fails
  static RangeHeader? parse(String headerValue, int fileSize) {
    try {
      // Remove "bytes=" prefix
      if (!headerValue.toLowerCase().startsWith('bytes=')) {
        return null;
      }

      final rangeValue = headerValue.substring(6);

      // Split by hyphen
      final parts = rangeValue.split('-');
      if (parts.length != 2) {
        return null;
      }

      // Parse start
      final int start = parts[0].isEmpty ? 0 : int.parse(parts[0]);

      // Parse end (if not specified, use file size - 1)
      final int end = parts[1].isEmpty ? fileSize - 1 : int.parse(parts[1]);

      return RangeHeader(start: start, end: end);
    } catch (e) {
      print('Error parsing range header: $e');
      return null;
    }
  }
}
