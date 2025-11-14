import 'dart:io';
import 'package:shelf/shelf.dart';

/// Service for streaming audio files with HTTP range request support
class StreamingService {
  /// Stream an audio file by file path
  /// Supports HTTP range requests for seeking
  Future<Response> streamFile(File audioFile, Request request) async {
    try {
      // Check if file exists
      if (!await audioFile.exists()) {
        return Response.notFound('File not found');
      }

      // Get file size
      final fileSize = await audioFile.length();

      // Parse range header if present
      final rangeHeader = request.headers['range'];
      final range = rangeHeader != null
          ? RangeHeader.parse(rangeHeader, fileSize)
          : null;

      // Determine content range
      final int start = range?.start ?? 0;
      final int end = range?.end ?? (fileSize - 1);
      final int contentLength = end - start + 1;

      // Validate range
      if (start < 0 || end >= fileSize || start > end) {
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
      final stream = _createRangeStream(raf, start, end);

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
      return Response.internalServerError(body: 'Error streaming file: $e');
    }
  }

  /// Create a stream that reads a specific range from a file
  Stream<List<int>> _createRangeStream(
    RandomAccessFile raf,
    int start,
    int end,
  ) async* {
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
