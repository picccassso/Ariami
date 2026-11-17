import 'dart:convert';

import 'package:ariami_core/ariami_core.dart'
    show
        MusicDiscoveryPreferences,
        MusicRecommendation,
        MusicRecommendationSnapshot,
        OwnedMusicIndex,
        OwnedMusicTrack;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_info.dart';

class MusicDiscoveryCache {
  const MusicDiscoveryCache();

  static const cacheKey = 'mobile_music_discovery_cache_v9';
  static const lastScopeKey = 'mobile_music_discovery_last_scope_v1';
  static const dismissedKey = 'mobile_music_discovery_dismissed_v1';
  static const wishlistKey = 'mobile_music_discovery_wishlist_v1';
  static const maxEntries = 8;
  static const legacyCachePrefixes = <String>[
    'mobile_music_discovery_cache_v1_',
    'mobile_music_discovery_cache_v2_',
    'mobile_music_discovery_cache_v3_',
    'mobile_music_discovery_cache_v4_',
    'mobile_music_discovery_cache_v5_',
    'mobile_music_discovery_cache_v6_',
    'mobile_music_discovery_cache_v7_',
    'mobile_music_discovery_cache_v8_',
  ];

  static String scopeFor({
    required ServerInfo? serverInfo,
    String? userId,
  }) {
    final user = _normalizeUser(userId);
    if (serverInfo == null) return 'offline|$user';
    final endpoints = _endpointsFor(serverInfo).toList()..sort();
    return <String>[
      user,
      serverInfo.name.trim().toLowerCase(),
      '${serverInfo.port}',
      endpoints.join(','),
    ].join('|');
  }

  static List<String> scopesFor(
    SharedPreferences prefs, {
    required ServerInfo? serverInfo,
    String? userId,
  }) {
    final user = _normalizeUser(userId);
    final lastScope = prefs.getString(lastScopeKey);
    if (serverInfo == null) {
      return <String>{
        if (lastScope != null && lastScope.startsWith('$user|')) lastScope,
        'offline|$user',
      }.toList(growable: false);
    }

    final name = serverInfo.name.trim().toLowerCase();
    final port = '${serverInfo.port}';
    final endpoints = _endpointsFor(serverInfo);
    final primary = scopeFor(serverInfo: serverInfo, userId: userId);
    return <String>{
      primary,
      for (final endpoint in endpoints) '$user|$name|$port|$endpoint',
      if (lastScope != null &&
          lastScope.startsWith('$user|$name|$port|') &&
          _sharesEndpoint(lastScope, endpoints))
        lastScope,
    }.toList(growable: false);
  }

  Future<MusicRecommendationSnapshot?> readSnapshot(
    SharedPreferences prefs, {
    required MusicDiscoveryPreferences preferences,
    required List<String> scopes,
  }) async {
    await removeLegacyCaches(prefs);
    if (scopes.isEmpty) return null;
    final entries = await _readLruEntries(prefs);
    if (entries.isEmpty) return null;

    for (final scope in scopes) {
      final targetKey = _entryKey(scope, preferences);
      final index = entries.indexWhere((entry) => entry['key'] == targetKey);
      if (index == -1) continue;
      final matched = entries[index];
      final rawSnapshot = matched['snapshot'];
      if (rawSnapshot is Map) {
        try {
          final parsed = MusicRecommendationSnapshot.fromJson(
            Map<String, dynamic>.from(rawSnapshot),
          );
          if (index != entries.length - 1) {
            entries.removeAt(index);
            entries.add(matched);
            await _writeLruEntries(prefs, entries);
          }
          return parsed;
        } catch (_) {}
      }
      entries.removeAt(index);
      await _writeLruEntries(prefs, entries);
    }
    return null;
  }

  Future<void> writeSnapshot(
    SharedPreferences prefs, {
    required String scope,
    required MusicDiscoveryPreferences preferences,
    required MusicRecommendationSnapshot snapshot,
  }) async {
    await removeLegacyCaches(prefs);
    final key = _entryKey(scope, preferences);
    final entries = (await _readLruEntries(prefs))
      ..removeWhere((entry) => entry['key'] == key);
    entries.add(<String, dynamic>{
      'key': key,
      'snapshot': snapshot.toJson(),
    });
    while (entries.length > maxEntries) {
      entries.removeAt(0);
    }
    await _writeLruEntries(prefs, entries);
    if (!scope.startsWith('offline|')) {
      await prefs.setString(lastScopeKey, scope);
    }
  }

  static MusicRecommendationSnapshot filterOwnedRecommendations(
    MusicRecommendationSnapshot snapshot,
    Iterable<OwnedMusicTrack> ownedTracks,
  ) {
    if (snapshot.recommendations.isEmpty) return snapshot;
    final owned = OwnedMusicIndex(ownedTracks);
    if (owned.isEmpty) return snapshot;
    final filtered = snapshot.recommendations
        .where((item) => !owned.containsRecommendation(item))
        .toList(growable: false);
    return filtered.length == snapshot.recommendations.length
        ? snapshot
        : MusicRecommendationSnapshot(
            generatedAt: snapshot.generatedAt,
            recommendations: filtered,
            artistSeeds: snapshot.artistSeeds,
            trackSeeds: snapshot.trackSeeds,
          );
  }

  static List<MusicRecommendation> filterOwnedWishlist(
    List<MusicRecommendation> items,
    Iterable<OwnedMusicTrack> ownedTracks,
  ) {
    if (items.isEmpty) return items;
    final owned = OwnedMusicIndex(ownedTracks);
    if (owned.isEmpty) return items;
    final filtered = items
        .where((item) => !owned.containsRecommendation(item))
        .toList(growable: false);
    return filtered.length == items.length ? items : filtered;
  }

  static String keyFor(MusicRecommendation item) => item.identityKey;

  Future<List<MusicRecommendation>> readWishlist(SharedPreferences prefs) async {
    final raw = prefs.getString(wishlistKey);
    if (raw == null || raw.isEmpty) return const <MusicRecommendation>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(MusicRecommendation.fromJson)
            .where((item) =>
                item.name.trim().isNotEmpty && item.lastFmUrl.hasScheme)
            .toList(growable: false);
      }
    } catch (_) {
      await prefs.remove(wishlistKey);
    }
    return const <MusicRecommendation>[];
  }

  Future<void> writeWishlist(
    SharedPreferences prefs,
    List<MusicRecommendation> items,
  ) async {
    if (items.isEmpty) {
      await prefs.remove(wishlistKey);
      return;
    }
    await prefs.setString(
      wishlistKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<Set<String>> readDismissed(SharedPreferences prefs) async =>
      (prefs.getStringList(dismissedKey) ?? const <String>[]).toSet();

  Future<Set<String>> dismiss(
    SharedPreferences prefs,
    MusicRecommendation item,
  ) async {
    final next = <String>{...await readDismissed(prefs), keyFor(item)};
    await prefs.setStringList(dismissedKey, next.toList()..sort());
    return next;
  }

  Future<void> restoreAll(SharedPreferences prefs) async {
    await prefs.remove(dismissedKey);
  }

  static Future<void> removeLegacyCaches(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().toList(growable: false)) {
      if (legacyCachePrefixes.any(key.startsWith)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> clearAll([SharedPreferences? prefs]) async {
    final SharedPreferences target;
    if (prefs != null) {
      target = prefs;
    } else {
      try {
        target = await SharedPreferences.getInstance();
      } catch (_) {
        return;
      }
    }
    await target.remove(cacheKey);
    await target.remove(lastScopeKey);
    await removeLegacyCaches(target);
  }

  static String _normalizeUser(String? userId) {
    final trimmed = userId?.trim();
    return (trimmed == null || trimmed.isEmpty) ? 'guest' : trimmed;
  }

  static Set<String> _endpointsFor(ServerInfo serverInfo) => <String>{
        for (final endpoint in <String?>[
          serverInfo.publicOrigin,
          serverInfo.lanServer,
          serverInfo.tailscaleServer,
          serverInfo.server,
        ])
          if (endpoint != null && endpoint.trim().isNotEmpty)
            endpoint.trim().toLowerCase(),
      };

  static bool _sharesEndpoint(String scope, Set<String> endpoints) {
    final parts = scope.split('|');
    if (parts.length < 4) return false;
    return parts.last.split(',').any(endpoints.contains);
  }

  static String _entryKey(
    String scope,
    MusicDiscoveryPreferences preferences,
  ) =>
      '${base64Url.encode(utf8.encode(scope)).replaceAll('=', '')}_'
      '${preferences.cacheKey}';

  static Future<List<Map<String, dynamic>>> _readLruEntries(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final entries = decoded['entries'];
        if (entries is List) {
          return entries.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {
      await prefs.remove(cacheKey);
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> _writeLruEntries(
    SharedPreferences prefs,
    List<Map<String, dynamic>> entries,
  ) async {
    if (entries.isEmpty) {
      await prefs.remove(cacheKey);
      return;
    }
    await prefs.setString(
      cacheKey,
      jsonEncode(<String, dynamic>{'entries': entries}),
    );
  }
}
