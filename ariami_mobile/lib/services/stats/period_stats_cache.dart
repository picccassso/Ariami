import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/server_info.dart';

/// Persistent, account-scoped cache for server-derived listening periods.
///
/// Each exact inclusive day range is stored separately. This lets the stats
/// screen reuse a previously viewed day, week, month, or year when the server
/// is offline without ever falling back to another account's data.
class PeriodStatsCache {
  factory PeriodStatsCache() => _instance;

  PeriodStatsCache.withPreferences(
    SharedPreferences preferences, {
    int maxEntries = 64,
    DateTime Function()? now,
  })  : _preferences = preferences,
        _maxEntries = maxEntries,
        _now = now ?? DateTime.now;

  PeriodStatsCache._()
      : _maxEntries = 64,
        _now = DateTime.now;

  static final PeriodStatsCache _instance = PeriodStatsCache._();

  static const String _dataKeyPrefix = 'stats_period_cache_v1_data_';
  static const String _manifestKey = 'stats_period_cache_v1_manifest';

  SharedPreferences? _preferences;
  final int _maxEntries;
  final DateTime Function() _now;
  Future<void> _pendingMutation = Future<void>.value();

  /// Builds a stable scope across LAN/Tailscale route changes for one user.
  static String? scopeFor({
    required String? userId,
    required ServerInfo? serverInfo,
  }) {
    final normalizedUser = userId?.trim();
    if (normalizedUser == null ||
        normalizedUser.isEmpty ||
        serverInfo == null) {
      return null;
    }

    final endpoints = <String>{
      for (final endpoint in <String?>[
        serverInfo.publicOrigin,
        serverInfo.lanServer,
        serverInfo.tailscaleServer,
        serverInfo.server,
      ])
        if (endpoint != null && endpoint.trim().isNotEmpty)
          endpoint.trim().toLowerCase(),
    }.toList()
      ..sort();

    return <String>[
      normalizedUser,
      serverInfo.name.trim().toLowerCase(),
      '${serverInfo.port}',
      endpoints.join(','),
    ].join('|');
  }

  Future<Map<String, dynamic>?> read({
    required String scope,
    required String from,
    required String to,
  }) async {
    await _pendingMutation;
    try {
      final preferences = await _prefs();
      final encoded = preferences.getString(_dataKey(scope, from, to));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String scope,
    required String from,
    required String to,
    required Map<String, dynamic> stats,
  }) {
    return _mutate(() async {
      final preferences = await _prefs();
      final key = _dataKey(scope, from, to);
      await preferences.setString(key, jsonEncode(stats));

      final manifest = _readManifest(preferences);
      manifest[key] = _ManifestEntry(
        scope: scope,
        savedAtMs: _now().millisecondsSinceEpoch,
      );

      if (manifest.length > _maxEntries) {
        final oldest = manifest.entries.toList()
          ..sort((a, b) => a.value.savedAtMs.compareTo(b.value.savedAtMs));
        final overflow = manifest.length - _maxEntries;
        for (final entry in oldest.take(overflow)) {
          await preferences.remove(entry.key);
          manifest.remove(entry.key);
        }
      }

      await preferences.setString(
        _manifestKey,
        jsonEncode({
          for (final entry in manifest.entries) entry.key: entry.value.toJson(),
        }),
      );
    });
  }

  Future<void> clearScope(String? scope) {
    if (scope == null || scope.isEmpty) return Future<void>.value();
    return _mutate(() async {
      final preferences = await _prefs();
      final manifest = _readManifest(preferences);
      final keys = manifest.entries
          .where((entry) => entry.value.scope == scope)
          .map((entry) => entry.key)
          .toList();
      for (final key in keys) {
        await preferences.remove(key);
        manifest.remove(key);
      }
      await _persistManifest(preferences, manifest);
    });
  }

  Future<void> clearAll() {
    return _mutate(() async {
      final preferences = await _prefs();
      final manifest = _readManifest(preferences);
      for (final key in manifest.keys) {
        await preferences.remove(key);
      }
      await preferences.remove(_manifestKey);
    });
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _pendingMutation.then((_) => action());
    _pendingMutation = operation.catchError((_) {});
    return operation;
  }

  Map<String, _ManifestEntry> _readManifest(
    SharedPreferences preferences,
  ) {
    try {
      final encoded = preferences.getString(_manifestKey);
      if (encoded == null) return <String, _ManifestEntry>{};
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, _ManifestEntry>{};
      return <String, _ManifestEntry>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: _ManifestEntry.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return <String, _ManifestEntry>{};
    }
  }

  Future<void> _persistManifest(
    SharedPreferences preferences,
    Map<String, _ManifestEntry> manifest,
  ) async {
    if (manifest.isEmpty) {
      await preferences.remove(_manifestKey);
      return;
    }
    await preferences.setString(
      _manifestKey,
      jsonEncode({
        for (final entry in manifest.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  String _dataKey(String scope, String from, String to) {
    final encodedScope =
        base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return '$_dataKeyPrefix${encodedScope}_${from}_$to';
  }
}

class _ManifestEntry {
  const _ManifestEntry({required this.scope, required this.savedAtMs});

  final String scope;
  final int savedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scope': scope,
        'savedAtMs': savedAtMs,
      };

  factory _ManifestEntry.fromJson(Map<String, dynamic> json) => _ManifestEntry(
        scope: json['scope'] as String? ?? '',
        savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
      );
}
