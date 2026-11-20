part of '../listening_stats_controller.dart';

extension _ListeningStatsPersistence on ListeningStatsController {
  void _markDirty() {
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 10), () {
      _saveTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(ListeningStatsController._storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        (json['daily'] as Map<String, dynamic>? ?? const {})
            .forEach((key, value) {
          _dailySeconds[key] = (value as num).toDouble();
        });
        _events = (json['events'] as List<dynamic>? ?? const [])
            .map((e) => PlayEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        _recentSources = (json['recents'] as List<dynamic>? ?? const [])
            .cast<String>()
            .toList();
      } catch (_) {
        // Corrupt stats are not worth breaking the player over — start fresh.
      }
    }
    _accountKey ??= _prefs!.getString(ListeningStatsController._lastAccountKey);
    _restoreAccountCache(
      _prefs!.getString(ListeningStatsController._accountCacheKey),
    );
    _restorePeriodCache(
      _prefs!.getString(ListeningStatsController._periodCacheKey),
    );
    _lastMinutesToday = minutesToday;
    _notifyListeners();
  }

  /// Restores the last successful account fetch so home highlights stay
  /// server-derived across an offline restart. Never applied over data
  /// fetched in this run.
  void _restoreAccountCache(String? raw) {
    if (raw == null || raw.isEmpty) return;
    if (_accountFetchedAt != null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final atMs = (json['at'] as num?)?.toInt();
      if (atMs == null) return;
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(atMs);
      final daily = <String, int>{};
      (json['daily'] as Map<String, dynamic>? ?? const {})
          .forEach((key, value) {
        daily[key] = (value as num).toInt();
      });
      _accountDailyMs = daily;
      if (DateTime.now().difference(cachedAt) <
          ListeningStatsController._accountCacheWindowMaxAge) {
        _accountRecent = (json['recent'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ListeningSongRollup.fromJson)
            .toList();
        _accountWeekArtists =
            (json['weekArtists'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(ListeningArtistRollup.fromJson)
                .toList();
      }
      _accountCachedAt = cachedAt;
      _pendingDaysDirty = true;
    } catch (_) {
      // A corrupt cache silently falls back to local-only highlights.
    }
  }

  /// Writes the small home-highlight bundle (daily minutes, trailing-week
  /// songs and credited artists). Deliberately excludes the all-time summary
  /// and rollups — the Settings dashboard always requires a live fetch.
  Future<void> _persistAccountCache() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
      ListeningStatsController._accountCacheKey,
      jsonEncode(<String, dynamic>{
        'at': DateTime.now().millisecondsSinceEpoch,
        'daily': _accountDailyMs,
        'recent': [for (final rollup in _accountRecent) rollup.toJson()],
        'weekArtists': [
          for (final rollup in _accountWeekArtists) rollup.toJson()
        ],
      }),
    );
  }

  Future<void> _persist() async {
    if (!_dirty) return;
    _dirty = false;
    _prefs ??= await SharedPreferences.getInstance();
    // Prune old days so the blob stays small over years of use.
    if (_dailySeconds.length > ListeningStatsController._maxDailyEntries) {
      final keys = _dailySeconds.keys.toList()..sort();
      for (final key in keys.take(
        _dailySeconds.length - ListeningStatsController._maxDailyEntries,
      )) {
        _dailySeconds.remove(key);
      }
    }
    await _prefs!.setString(
      ListeningStatsController._storageKey,
      jsonEncode(<String, dynamic>{
        'daily': _dailySeconds,
        'events': _events.map((e) => e.toJson()).toList(),
        'recents': _recentSources,
      }),
    );
  }

  String _periodCacheEntryKey({
    required String fromDay,
    required String toDay,
    required int limit,
  }) =>
      '$fromDay|$toDay|$limit';

  void _restorePeriodCache(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final cachedAccount = decoded['account'] as String?;
      if (_accountKey != null &&
          cachedAccount != null &&
          cachedAccount != _accountKey) {
        return;
      }
      final entries = decoded['entries'];
      if (entries is! Map) return;
      _periodCache.clear();
      for (final entry in entries.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! Map) continue;
        final statsMap = value['stats'];
        if (statsMap is! Map<String, dynamic>) continue;
        _periodCache[entry.key as String] = (
          savedAtMs: (value['at'] as num?)?.toInt() ?? 0,
          stats: ListeningPeriodStats.fromJson(statsMap),
        );
      }
    } catch (_) {}
  }

  Future<ListeningPeriodStats?> _readPeriodCache({
    required String fromDay,
    required String toDay,
    required int limit,
  }) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _accountKey ??= prefs.getString(ListeningStatsController._lastAccountKey);
    if (_periodCache.isEmpty) {
      _restorePeriodCache(
        prefs.getString(ListeningStatsController._periodCacheKey),
      );
    }
    return _periodCache[_periodCacheEntryKey(
      fromDay: fromDay,
      toDay: toDay,
      limit: limit,
    )]
        ?.stats;
  }

  Future<void> _writePeriodCache({
    required String fromDay,
    required String toDay,
    required int limit,
    required ListeningPeriodStats stats,
  }) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _accountKey ??= prefs.getString(ListeningStatsController._lastAccountKey);
    final key = _periodCacheEntryKey(
      fromDay: fromDay,
      toDay: toDay,
      limit: limit,
    );
    _periodCache[key] = (
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      stats: stats,
    );
    if (_periodCache.length > ListeningStatsController._maxPeriodCacheEntries) {
      final oldest = _periodCache.entries.toList()
        ..sort((a, b) => a.value.savedAtMs.compareTo(b.value.savedAtMs));
      final overflow =
          _periodCache.length - ListeningStatsController._maxPeriodCacheEntries;
      for (final entry in oldest.take(overflow)) {
        _periodCache.remove(entry.key);
      }
    }
    await prefs.setString(
      ListeningStatsController._periodCacheKey,
      jsonEncode(<String, dynamic>{
        if (_accountKey != null) 'account': _accountKey,
        'entries': <String, dynamic>{
          for (final entry in _periodCache.entries)
            entry.key: <String, dynamic>{
              'at': entry.value.savedAtMs,
              'stats': entry.value.stats.toJson(),
            },
        },
      }),
    );
  }

  Future<void> _clearPeriodCache() async {
    _periodCache.clear();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(ListeningStatsController._periodCacheKey);
  }
}
