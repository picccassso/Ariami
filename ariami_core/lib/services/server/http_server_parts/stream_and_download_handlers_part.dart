part of '../http_server.dart';

extension AriamiHttpServerStreamAndDownloadHandlersMethods on AriamiHttpServer {
  /// Handle stream request
  ///
  /// Supports quality parameter for transcoded streaming:
  /// - ?quality=high (default) - Original file
  /// - ?quality=medium - 128 kbps AAC
  /// - ?quality=low - 64 kbps AAC
  Future<Response> _handleStream(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Validate stream token if auth is required
    String? streamToken;
    if (_authRequired && !_legacyMode) {
      streamToken = request.url.queryParameters['streamToken'];
      if (streamToken == null || streamToken.isEmpty) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final ticket = _streamTracker.validateToken(streamToken);
      if (ticket == null) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token expired or invalid',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Verify the token is for the requested song
      if (ticket.songId != path) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token does not match requested song',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Mark stream as active for stats tracking
      _streamTracker.startStream(streamToken);
    }

    // Parse quality parameter
    final qualityParam = request.url.queryParameters['quality'];
    final quality = QualityPreset.fromString(qualityParam);

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final File originalFile = File(filePath);

    // Check if file exists
    if (!await originalFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = originalFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    }

    // Determine which file to stream
    File fileToStream = originalFile;

    // If transcoding is requested and service is available
    if (quality.requiresTranscoding && _transcodingService != null) {
      // Serve only completed transcodes here. This keeps lower-quality playback
      // on the normal file streaming path with range support.
      final transcodedFile = await _transcodingService!.getTranscodedFile(
        filePath,
        path, // songId
        quality,
        requestType: TranscodeRequestType.streaming,
      );

      if (transcodedFile != null) {
        fileToStream = transcodedFile;
        // Mark as in-use to prevent eviction during streaming
        _transcodingService!.markInUse(path, quality);
        print(
            '[HttpServer] Streaming transcoded file at ${quality.name} quality');

        // Stream the file and release in-use when done
        try {
          return await _streamingService.streamFile(fileToStream, request);
        } finally {
          _transcodingService!.releaseInUse(path, quality);
        }
      } else {
        // Transcoding failed or FFmpeg not available - fall back to original
        print(
            '[HttpServer] Transcoding unavailable, falling back to original file');
      }
    } else if (quality.requiresTranscoding && _transcodingService == null) {
      print(
          '[HttpServer] Transcoding requested but service not configured, using original');
    }

    // Stream the file (original or non-transcoded)
    return await _streamingService.streamFile(fileToStream, request);
  }

  /// Handle download request (full file download)
  ///
  /// Supports quality parameter for transcoded downloads:
  /// - ?quality=high (default) - Original file
  /// - ?quality=medium - 128 kbps AAC
  /// - ?quality=low - 64 kbps AAC
  Future<Response> _handleDownload(Request request, String path) async {
    // Validate path is provided
    if (path.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({
          'error': 'Invalid request',
          'message': 'Song ID is required',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Validate stream token if auth is required
    String? userId;
    if (_authRequired && !_legacyMode) {
      final streamToken = request.url.queryParameters['streamToken'];
      if (streamToken == null || streamToken.isEmpty) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final ticket = _streamTracker.validateToken(streamToken);
      if (ticket == null) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token expired or invalid',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Verify the token is for the requested song
      if (ticket.songId != path) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'code': AuthErrorCodes.streamTokenExpired,
              'message': 'Stream token does not match requested song',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      userId = ticket.userId;
    }

    // Parse quality parameter
    final qualityParam = request.url.queryParameters['quality'];
    final quality = QualityPreset.fromString(qualityParam);

    // Look up file path from library by song ID
    final filePath = _libraryManager.getSongFilePath(path);
    if (filePath == null) {
      return Response.notFound(
        jsonEncode({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final File originalFile = File(filePath);

    // Check if file exists
    if (!await originalFile.exists()) {
      return Response.notFound(
        jsonEncode({
          'error': 'File not found',
          'message': 'Audio file does not exist: $path',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Check if file is in allowed music folder (security check)
    if (_musicFolderPath != null) {
      final canonicalPath = originalFile.absolute.path;
      if (!canonicalPath.startsWith(_musicFolderPath!)) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Forbidden',
            'message': 'File is outside music library',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
    }

    // Enforce weighted-fair download limits across users.
    final userKey = userId ?? 'legacy';
    final acquireResult = await _downloadLimiter.acquire(userKey);
    if (acquireResult == _FairAcquireResult.userQuotaExceeded) {
      print(
          '[HttpServer] Download rejected (user queue full) userId=$userKey songId=$path');
      return _retryableErrorResponse(
        statusCode: 429,
        error: 'Too many downloads for user',
        message: 'Per-user download queue is full',
      );
    }
    if (acquireResult == _FairAcquireResult.queueFull) {
      print(
          '[HttpServer] Download rejected (queue full) userId=$userKey songId=$path '
          'active=${_downloadLimiter.activeCount} queue=${_downloadLimiter.queueLength}');
      return _retryableErrorResponse(
        statusCode: 503,
        error: 'Server busy',
        message: 'Download queue is full, try again later',
      );
    }

    bool releaseOnError = true;

    try {
      // Determine which file to download
      File fileToDownload = originalFile;
      String mimeType = _streamingService.getAudioMimeType(originalFile.path);
      DownloadTranscodeResult? downloadTranscodeResult;

      // If transcoding is requested and service is available
      if (quality.requiresTranscoding && _transcodingService != null) {
        // Use dedicated download pipeline (temp file, not cached)
        // This prevents cache churn during bulk downloads
        downloadTranscodeResult =
            await _transcodingService!.getDownloadTranscode(
          filePath,
          path, // songId
          quality,
        );

        if (downloadTranscodeResult != null) {
          fileToDownload = downloadTranscodeResult.tempFile;
          mimeType = quality.mimeType ?? mimeType;
          print(
              '[HttpServer] Downloading transcoded file at ${quality.name} quality (temp file)');
        } else {
          // Transcoding failed or FFmpeg not available - fall back to original
          print(
              '[HttpServer] Transcoding unavailable for download, falling back to original file');
        }
      } else if (quality.requiresTranscoding && _transcodingService == null) {
        print(
            '[HttpServer] Transcoding requested for download but service not configured, using original');
      }

      // Get file info
      final fileSize = await fileToDownload.length();
      final originalFileName =
          originalFile.path.split(Platform.pathSeparator).last;

      // Adjust filename extension if transcoded
      String downloadFileName = originalFileName;
      if (downloadTranscodeResult != null && quality.fileExtension != null) {
        // Replace extension with transcoded format extension
        final lastDot = originalFileName.lastIndexOf('.');
        if (lastDot > 0) {
          downloadFileName =
              '${originalFileName.substring(0, lastDot)}.${quality.fileExtension}';
        } else {
          downloadFileName = '$originalFileName.${quality.fileExtension}';
        }
      }

      // Open file with explicit handle management to prevent file handle leaks
      final RandomAccessFile raf =
          await fileToDownload.open(mode: FileMode.read);

      // Capture the result for cleanup in the stream's finally block
      final tempResult = downloadTranscodeResult;

      // Create stream that properly closes the file handle and cleans up temp files when done
      Stream<List<int>> createFileStream() async* {
        const int chunkSize = 64 * 1024; // 64 KB chunks
        try {
          while (true) {
            final chunk = await raf.read(chunkSize);
            if (chunk.isEmpty) break;
            yield chunk;
          }
        } finally {
          await raf.close();
          // Clean up temp file after download completes
          if (tempResult != null) {
            await tempResult.cleanup();
            print('[HttpServer] Cleaned up temp transcode file');
          }
          _releaseDownloadSlot(userKey);
        }
      }

      // Return the file as a download with appropriate headers
      releaseOnError = false;
      return Response.ok(
        createFileStream(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': fileSize.toString(),
          'Content-Disposition': _encodeContentDisposition(downloadFileName),
          'Cache-Control':
              'public, max-age=3600', // Cache for 1 hour during download
        },
      );
    } catch (e) {
      if (releaseOnError) {
        _releaseDownloadSlot(userKey);
      }
      print(
          '[HttpServer] Download failed userId=$userKey songId=$path error=$e');
      if (e is FileSystemException) {
        return _retryableErrorResponse(
          statusCode: 503,
          error: 'Server busy',
          message: 'File system error during download, try again',
        );
      }
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Download failed',
          'message': 'Unexpected server error during download',
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Encodes a filename for Content-Disposition header (RFC 5987)
  /// Provides ASCII-safe fallback and UTF-8 encoded filename for proper
  /// handling of non-ASCII characters (accents, Korean, Chinese, etc.)
  String _encodeContentDisposition(String filename) {
    // ASCII-safe fallback: replace non-ASCII chars with underscore
    final asciiFallback = filename.runes
        .map((r) => r < 128 ? String.fromCharCode(r) : '_')
        .join()
        .replaceAll('"', "'");

    // RFC 5987 percent-encode the UTF-8 filename
    final utf8Encoded = Uri.encodeComponent(filename);

    return 'attachment; filename="$asciiFallback"; filename*=UTF-8\'\'$utf8Encoded';
  }

  void _releaseDownloadSlot(String userId) {
    _downloadLimiter.release(userId);
  }
}
