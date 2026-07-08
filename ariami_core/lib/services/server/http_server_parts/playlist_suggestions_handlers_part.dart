part of '../http_server.dart';

/// Playlist-suggestion approval workflow: lets the dashboard act on the
/// advisory suggestions the scanner surfaces (see PLAYLIST_DETECTION.md).
///
/// Decisions are library-wide (they change what every account sees), so both
/// endpoints use the same authorization as the other library-mutating setup
/// endpoints: admin session when users exist, open during first-run setup.
extension AriamiHttpServerPlaylistSuggestionsMethods on AriamiHttpServer {
  Response _playlistDecisionsUnavailable() =>
      _jsonResponse(HttpStatus.serviceUnavailable, {
        'error': {
          'code': 'PLAYLIST_DECISIONS_UNAVAILABLE',
          'message': 'Playlist decision storage is not initialized',
        },
      });

  Response _invalidPlaylistDecisionRequest(String message) => _jsonBadRequest({
        'error': {'code': 'INVALID_PLAYLIST_DECISION', 'message': message},
      });

  /// GET /api/playlists/suggestions — pending suggestions plus every
  /// recorded decision.
  Future<Response> _handlePlaylistSuggestionsGet(Request request) async {
    final authResponse = await _authorizeSetupRequest(request);
    if (authResponse != null) return authResponse;

    final store = _libraryManager.playlistDecisionStore;
    var decisions = const <PlaylistFolderDecisionRecord>[];
    var decidedPaths = const <String>{};
    if (store != null) {
      await store.ensureLoaded();
      decisions = store.decisions;
      decidedPaths = {
        ...store.importedFolderPaths,
        ...store.ignoredFolderPaths,
      };
    }

    // A fresh decision hides its suggestion immediately, even though the
    // decided folder stays in the last scan's diagnostics until a rescan.
    final pendingSuggestions = _libraryManager
        .latestScanDiagnostics.playlistSuggestions
        .where((s) => !decidedPaths.contains(p.normalize(s.folderPath)))
        .toList(growable: false);

    return _jsonOk({
      'suggestions':
          pendingSuggestions.map((s) => s.toJson()).toList(growable: false),
      'decisions': decisions.map((d) => d.toJson()).toList(growable: false),
      'isScanning': _libraryManager.isScanning,
    });
  }

  /// POST /api/playlists/suggestions/decision {folderPath, decision}.
  ///
  /// decision: 'import' | 'ignore' | 'reset'. Import triggers a rescan so
  /// the playlist materializes without further action.
  Future<Response> _handlePlaylistSuggestionDecisionPost(
    Request request,
  ) async {
    final authResponse = await _authorizeSetupRequest(request);
    if (authResponse != null) return authResponse;

    final store = _libraryManager.playlistDecisionStore;
    if (store == null) return _playlistDecisionsUnavailable();

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(await request.readAsString());
      body = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      body = null;
    }
    if (body == null) {
      return _invalidPlaylistDecisionRequest('Body must be a JSON object');
    }

    final rawFolderPath = body['folderPath'];
    final rawDecision = body['decision'];
    if (rawFolderPath is! String || rawFolderPath.trim().isEmpty) {
      return _invalidPlaylistDecisionRequest(
        'folderPath must be a non-empty string',
      );
    }
    if (rawDecision is! String) {
      return _invalidPlaylistDecisionRequest(
        "decision must be 'import', 'ignore', or 'reset'",
      );
    }

    await store.ensureLoaded();
    try {
      if (rawDecision == 'reset') {
        final removed = await store.clearDecision(rawFolderPath);
        return _jsonOk({'success': true, 'removed': removed});
      }

      final decision = playlistFolderDecisionFromName(rawDecision);
      if (decision == null) {
        return _invalidPlaylistDecisionRequest(
          "decision must be 'import', 'ignore', or 'reset'",
        );
      }

      final record = await store.setDecision(rawFolderPath, decision);
      var rescanStarted = false;
      if (decision == PlaylistFolderDecision.import) {
        rescanStarted = await _startRescanForPlaylistImport();
      }
      return _jsonOk({
        'success': true,
        'decision': record.toJson(),
        'rescanStarted': rescanStarted,
      });
    } on ArgumentError catch (error) {
      return _invalidPlaylistDecisionRequest(
        error.message?.toString() ?? 'Invalid playlist decision',
      );
    }
  }

  /// Starts a rescan so an imported suggestion becomes a real playlist.
  ///
  /// Prefers the host's start-scan callback (CLI); in-process servers without
  /// one (desktop) fall back to rescanning the last scanned folder.
  Future<bool> _startRescanForPlaylistImport() async {
    final startScan = _startScanCallback;
    if (startScan != null) {
      try {
        return await startScan();
      } catch (_) {
        return false;
      }
    }

    final folderPath = _libraryManager.lastScannedFolderPath;
    if (folderPath == null || _libraryManager.isScanning) return false;
    unawaited(
      _libraryManager.scanMusicFolder(folderPath).catchError((Object e) {
        print('[HttpServer] Rescan after playlist import failed: $e');
      }),
    );
    return true;
  }
}
