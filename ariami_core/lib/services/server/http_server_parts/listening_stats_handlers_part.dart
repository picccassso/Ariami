part of '../http_server.dart';

/// Handlers for the per-account listening statistics API.
///
/// All endpoints require an authenticated session; the user and device are
/// always derived from the validated session, never from the payload, so a
/// client cannot write to (or read) another account's stats.
extension AriamiHttpServerListeningStatsMethods on AriamiHttpServer {
  static const int _defaultDailyDays = 120;
  static const int _maxDailyDays = 400;

  ListeningStatsStore? get _statsStoreIfReady {
    final store = _listeningStatsStore;
    if (store == null || !store.isInitialized) return null;
    return store;
  }

  Response _statsUnavailable() {
    return _jsonResponse(HttpStatus.serviceUnavailable, {
      'error': {
        'code': 'STATS_UNAVAILABLE',
        'message': 'Listening stats storage is not initialized',
      },
    });
  }

  /// POST /api/v2/listening/events — idempotent batch upload.
  Future<Response> _handleListeningEventsPost(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    Map<String, dynamic> data;
    try {
      data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': 'Body must be a JSON object',
        },
      });
    }

    final rawEvents = data['events'];
    if (rawEvents is! List) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': 'events must be a list',
        },
      });
    }
    if (rawEvents.length > ListeningStatsStore.maxEventsPerBatch) {
      return _jsonBadRequest({
        'error': {
          'code': 'INVALID_REQUEST',
          'message':
              'events exceeds the batch limit of ${ListeningStatsStore.maxEventsPerBatch}',
        },
      });
    }

    final events = <ListeningEvent>[];
    var rejected = 0;
    for (final raw in rawEvents) {
      final event = raw is Map<String, dynamic>
          ? ListeningEvent.tryFromJson(raw)
          : null;
      if (event == null) {
        rejected++;
        continue;
      }
      events.add(event);
    }

    final result = store.applyEvents(session.userId, session.deviceId, events);

    // Wake the account's other online clients so their stats views refresh in
    // real time. The uploading device already knows.
    if (result.accepted > 0) {
      _connectHub.sendToUser(
        session.userId,
        WsMessage(
          type: WsMessageType.listeningStatsUpdated,
          data: {'reason': 'events', 'sourceDeviceId': session.deviceId},
        ),
        exceptDeviceId: session.deviceId,
      );
    }

    return _jsonOk({
      'accepted': result.accepted,
      'duplicates': result.duplicates,
      'rejected': result.rejected + rejected,
    });
  }

  /// GET /api/v2/listening/summary — account-wide per-song rollups.
  Future<Response> _handleListeningSummaryGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    return _jsonOk(store.getSummary(session.userId).toJson());
  }

  /// GET /api/v2/listening/daily?days=N — listened ms per local day.
  Future<Response> _handleListeningDailyGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    var days = _defaultDailyDays;
    final rawDays = request.url.queryParameters['days'];
    if (rawDays != null) {
      final parsed = int.tryParse(rawDays);
      if (parsed == null || parsed <= 0 || parsed > _maxDailyDays) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'days must be an integer between 1 and $_maxDailyDays',
          },
        });
      }
      days = parsed;
    }

    return _jsonOk({
      'days': store.getDailyListenedMs(session.userId, days: days),
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// GET /api/v2/listening/recent?days=N — per-song totals in the window.
  Future<Response> _handleListeningRecentGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    var days = 7;
    final rawDays = request.url.queryParameters['days'];
    if (rawDays != null) {
      final parsed = int.tryParse(rawDays);
      if (parsed == null || parsed <= 0 || parsed > _maxDailyDays) {
        return _jsonBadRequest({
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'days must be an integer between 1 and $_maxDailyDays',
          },
        });
      }
      days = parsed;
    }

    final songs = store.getRecentSongTotals(session.userId, days: days);
    return _jsonOk({
      'songs': songs.map((rollup) => rollup.toJson()).toList(),
      'days': days,
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// POST /api/v2/listening/reset — wipes this account's listening history.
  Future<Response> _handleListeningResetPost(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    store.resetUser(session.userId);

    _connectHub.sendToUser(
      session.userId,
      WsMessage(
        type: WsMessageType.listeningStatsUpdated,
        data: {'reason': 'reset', 'sourceDeviceId': session.deviceId},
      ),
      exceptDeviceId: session.deviceId,
    );

    return _jsonOk({'success': true});
  }
}
