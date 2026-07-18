part of '../http_server.dart';

extension AriamiHttpServerMediaTicketHandlersMethods on AriamiHttpServer {
  /// Handle stream ticket request (for authenticated streaming)
  Future<Response> _handleStreamTicket(Request request) async {
    // Session is attached by auth middleware
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final songId = data['songId'] as String?;
      final quality = QualityPreset.fromString(data['quality'] as String?).name;

      if (songId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'songId is required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Keep ticket issuing fast for bulk downloads by using only known/cached
      // duration values here (no on-demand file metadata extraction).
      final durationSeconds = _libraryManager.getKnownSongDuration(songId) ?? 0;

      // Issue stream ticket
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
      return Response.internalServerError(
        body: jsonEncode({
          'error': {
            'code': 'INTERNAL_ERROR',
            'message': 'Failed to issue stream ticket',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  Future<Response> _handleStreamWarmup(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawSongIds = data['songIds'] as List<dynamic>?;
      final quality = QualityPreset.fromString(data['quality'] as String?);

      if (rawSongIds == null || rawSongIds.isEmpty) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'songIds is required',
          },
        });
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
      return _jsonInternalServerError({
        'error': {
          'code': 'INTERNAL_ERROR',
          'message': 'Failed to warm streams',
        },
      });
    }
  }

  /// Handle download ticket request (for authenticated offline downloads).
  Future<Response> _handleDownloadTicket(Request request) async {
    // Session is attached by auth middleware.
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final ticketRequest = DownloadTicketRequest.fromJson(data);
      final songId = ticketRequest.songId.trim();

      if (songId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'songId is required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final filePath = _libraryManager.getSongFilePath(songId);
      if (filePath == null) {
        return _jsonNotFound({
          'error': 'Song not found',
          'message': 'Song ID not found in library: $songId',
        });
      }

      final quality = ticketRequest.quality?.trim().toLowerCase();
      final ticket = _streamTracker.issueDownloadTicket(
        userId: session.userId,
        sessionToken: session.sessionToken,
        songId: songId,
        quality: quality == null || quality.isEmpty ? null : quality,
      );

      return Response.ok(
        jsonEncode(DownloadTicketResponse(
          downloadToken: ticket.token,
          expiresAt: ticket.expiresAt.toIso8601String(),
        ).toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on TypeError {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'Invalid request body',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': {
            'code': 'INTERNAL_ERROR',
            'message': 'Failed to issue download ticket',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }
}
