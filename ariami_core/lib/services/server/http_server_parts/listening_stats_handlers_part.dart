part of '../http_server.dart';

/// Handlers for the per-account listening statistics API.
///
/// All endpoints require an authenticated session; the user and device are
/// always derived from the validated session, never from the payload, so a
/// client cannot write to (or read) another account's stats.
extension AriamiHttpServerListeningStatsMethods on AriamiHttpServer {
  static const int _defaultDailyDays = 120;
  static const int _maxDailyDays = 400;
  static const int _defaultTopLimit = 50;
  static const int _maxTopLimit = 200;

  /// Longest allowed day/period range — generous enough for multi-year
  /// recaps while bounding the query.
  static const int _maxPeriodDays = 1100;

  static final RegExp _localDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Validates a `yyyy-mm-dd` local-day query value; returns its parsed
  /// DateTime or null when malformed (including non-round-tripping dates
  /// like 2026-02-31).
  DateTime? _parseLocalDay(String? raw) {
    if (raw == null || !_localDayPattern.hasMatch(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final formatted = '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return formatted == raw ? parsed : null;
  }

  /// Parses an optional positive-int query parameter with an upper bound.
  /// Returns [fallback] when absent, -1 when present but invalid.
  int _parseBoundedInt(Request request, String name,
      {required int fallback, required int max}) {
    final raw = request.url.queryParameters[name];
    if (raw == null) return fallback;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0 || parsed > max) return -1;
    return parsed;
  }

  Response _invalidParam(String message) {
    return _jsonBadRequest({
      'error': {'code': 'INVALID_REQUEST', 'message': message},
    });
  }

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
      // Additive: same local days with play counts included. Old clients
      // ignore this field; new clients get plays without a second request.
      'totals': store
          .getDailyTotals(session.userId, days: days)
          .map((day, total) => MapEntry(day, total.toJson())),
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// GET /api/v2/listening/day?date=yyyy-mm-dd&limit=N — totals plus top
  /// songs / credited artists / albums for one local day.
  Future<Response> _handleListeningDayGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    final rawDate = request.url.queryParameters['date'];
    final date = _parseLocalDay(rawDate);
    if (rawDate == null || date == null) {
      return _invalidParam('date must be a valid yyyy-mm-dd day');
    }
    final limit = _parseBoundedInt(request, 'limit',
        fallback: _defaultTopLimit, max: _maxTopLimit);
    if (limit < 0) {
      return _invalidParam(
          'limit must be an integer between 1 and $_maxTopLimit');
    }

    final stats = store.getPeriodStats(
      session.userId,
      fromDay: rawDate,
      toDay: rawDate,
      limit: limit,
    );
    return _jsonOk({
      'date': rawDate,
      ...stats.toJson(),
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// GET /api/v2/listening/period?from=yyyy-mm-dd&to=yyyy-mm-dd&limit=N —
  /// totals, per-day breakdown and top items for an arbitrary local-day
  /// range (a month or year view is just a wider range).
  Future<Response> _handleListeningPeriodGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    final rawFrom = request.url.queryParameters['from'];
    final rawTo = request.url.queryParameters['to'];
    final from = _parseLocalDay(rawFrom);
    final to = _parseLocalDay(rawTo);
    if (rawFrom == null || from == null || rawTo == null || to == null) {
      return _invalidParam('from and to must be valid yyyy-mm-dd days');
    }
    if (to.isBefore(from)) {
      return _invalidParam('to must not be before from');
    }
    if (to.difference(from).inDays > _maxPeriodDays) {
      return _invalidParam('period must not exceed $_maxPeriodDays days');
    }
    final limit = _parseBoundedInt(request, 'limit',
        fallback: _defaultTopLimit, max: _maxTopLimit);
    if (limit < 0) {
      return _invalidParam(
          'limit must be an integer between 1 and $_maxTopLimit');
    }

    final stats = store.getPeriodStats(
      session.userId,
      fromDay: rawFrom,
      toDay: rawTo,
      limit: limit,
    );
    return _jsonOk({
      ...stats.toJson(),
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// GET /api/v2/listening/artists?days=N&limit=N — top credited artists,
  /// all-time when days is omitted. Multi-artist strings are split
  /// server-side, so "Mercy" credits Kanye West, Big Sean, Pusha T and
  /// 2 Chainz individually — each with the full play and full time.
  Future<Response> _handleListeningArtistsGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    final days = _parseBoundedInt(request, 'days',
        fallback: 0, max: _maxDailyDays);
    if (days < 0) {
      return _invalidParam(
          'days must be an integer between 1 and $_maxDailyDays');
    }
    final limit = _parseBoundedInt(request, 'limit',
        fallback: _defaultTopLimit, max: _maxTopLimit);
    if (limit < 0) {
      return _invalidParam(
          'limit must be an integer between 1 and $_maxTopLimit');
    }

    final artists = store.getTopArtists(
      session.userId,
      days: days == 0 ? null : days,
      limit: limit,
    );
    return _jsonOk({
      'artists': artists.map((rollup) => rollup.toJson()).toList(),
      if (days > 0) 'days': days,
      'generatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// GET /api/v2/listening/albums?days=N&limit=N — top albums, all-time when
  /// days is omitted.
  Future<Response> _handleListeningAlbumsGet(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) return _authRequiredResponse();
    final store = _statsStoreIfReady;
    if (store == null) return _statsUnavailable();

    final days = _parseBoundedInt(request, 'days',
        fallback: 0, max: _maxDailyDays);
    if (days < 0) {
      return _invalidParam(
          'days must be an integer between 1 and $_maxDailyDays');
    }
    final limit = _parseBoundedInt(request, 'limit',
        fallback: _defaultTopLimit, max: _maxTopLimit);
    if (limit < 0) {
      return _invalidParam(
          'limit must be an integer between 1 and $_maxTopLimit');
    }

    final albums = store.getTopAlbums(
      session.userId,
      days: days == 0 ? null : days,
      limit: limit,
    );
    return _jsonOk({
      'albums': albums.map((rollup) => rollup.toJson()).toList(),
      if (days > 0) 'days': days,
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
