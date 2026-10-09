part of '../http_server.dart';

extension AriamiHttpServerMediaTicketHandlersMethods on AriamiHttpServer {
  Future<Response> _handleStreamTicket(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _jsonError(HttpStatus.unauthorized, AuthErrorCodes.authRequired,
          'Not authenticated');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final songId = data['songId'] as String?;
      final quality = QualityPreset.fromString(data['quality'] as String?).name;

      if (songId == null) {
        return _jsonError(
            HttpStatus.badRequest, 'INVALID_REQUEST', 'songId is required');
      }

      final availability = _libraryManager.musicAvailability;
      if (availability.needsAttention ||
          (_libraryManager.isScanning && _libraryManager.library == null)) {
        return _jsonResponse(HttpStatus.serviceUnavailable, {
          'error': {
            'code': 'MUSIC_UNAVAILABLE',
            'message': availability.message,
          },
          'musicAvailability': availability.toJson(),
        }, headers: {
          'Retry-After': '30'
        });
      }

      // A ticket for a song that no longer exists would only fail later at
      // /stream as an opaque player error clients cannot classify. Reject it
      // here with SONG_NOT_FOUND so they can skip the entry instead of
      // stalling playback on it. 410 rather than 404: the server's Cascade
      // treats handler 404s as unmatched routes and replaces the JSON body.
      if (_libraryManager.getSongFilePath(songId) == null) {
        return _jsonError(HttpStatus.gone, ApiErrorCodes.songNotFound,
            'Song ID not found in library: $songId');
      }

      // Keep ticket issuing fast for bulk downloads by using only known/cached
      // duration values here (no on-demand file metadata extraction).
      final durationSeconds = _libraryManager.getKnownSongDuration(songId) ?? 0;

      final ticket = _streamTracker.issueTicket(
        userId: session.userId,
        sessionToken: session.sessionToken,
        songId: songId,
        durationSeconds: durationSeconds,
        quality: quality,
      );

      return Response.ok(
        jsonEncode(StreamTicketResponse(
          streamToken: ticket.token,
          expiresAt: ticket.expiresAt.toIso8601String(),
        ).toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'INTERNAL_ERROR',
          'Failed to issue stream ticket');
    }
  }

  Future<Response> _handleStreamWarmup(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _jsonError(HttpStatus.unauthorized, AuthErrorCodes.authRequired,
          'Not authenticated');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawSongIds = data['songIds'] as List<dynamic>?;
      final quality = QualityPreset.fromString(data['quality'] as String?);

      if (rawSongIds == null || rawSongIds.isEmpty) {
        return _jsonError(
            HttpStatus.badRequest, 'INVALID_REQUEST', 'songIds is required');
      }

      final songIds = rawSongIds
          .whereType<String>()
          .map((songId) => songId.trim())
          .where((songId) => songId.isNotEmpty)
          .take(3)
          .toList();

      var queued = 0;
      var skipped = 0;
      var missing = 0;

      for (final songId in songIds) {
        final filePath = _libraryManager.getSongFilePath(songId);
        if (filePath == null) {
          missing++;
          continue;
        }

        if (!quality.requiresTranscoding || _transcodingService == null) {
          skipped++;
          continue;
        }

        final didQueue = await _transcodingService!.warmTranscodedFile(
          filePath,
          songId,
          quality,
          sourceBitrateKbps: _libraryManager.getKnownSongBitrate(songId),
        );
        if (didQueue) {
          queued++;
        } else {
          skipped++;
        }
      }

      return _jsonOk({
        'queued': queued,
        'skipped': skipped,
        'missing': missing,
      });
    } catch (_) {
      return _jsonError(HttpStatus.internalServerError, 'INTERNAL_ERROR',
          'Failed to warm streams');
    }
  }

  Future<Response> _handleDownloadTicket(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _jsonError(HttpStatus.unauthorized, AuthErrorCodes.authRequired,
          'Not authenticated');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final ticketRequest = DownloadTicketRequest.fromJson(data);
      final songId = ticketRequest.songId.trim();

      if (songId.isEmpty) {
        return _jsonError(
            HttpStatus.badRequest, 'INVALID_REQUEST', 'songId is required');
      }

      final filePath = _libraryManager.getSongFilePath(songId);
      if (filePath == null) {
        return _jsonNotFound({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $songId',
        });
      }

      final quality = ticketRequest.quality?.trim().toLowerCase();
      final requestedFormat = ticketRequest.format?.trim().toLowerCase();
      final outputFormat = TranscodeOutputFormat.tryParse(requestedFormat);
      if (requestedFormat != null &&
          requestedFormat.isNotEmpty &&
          outputFormat == null) {
        return _jsonError(HttpStatus.badRequest, 'INVALID_REQUEST',
            'format must be one of: aac, m4a, opus');
      }
      final ticket = _streamTracker.issueDownloadTicket(
        userId: session.userId,
        sessionToken: session.sessionToken,
        songId: songId,
        quality: quality == null || quality.isEmpty ? null : quality,
        format: outputFormat?.name,
      );

      return Response.ok(
        jsonEncode(DownloadTicketResponse(
          downloadToken: ticket.token,
          expiresAt: ticket.expiresAt.toIso8601String(),
        ).toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on TypeError {
      return _jsonError(
          HttpStatus.badRequest, 'INVALID_REQUEST', 'Invalid request body');
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, 'INTERNAL_ERROR',
          'Failed to issue download ticket');
    }
  }
}
