import 'package:ariami_core/ariami_core.dart'
    show
        MusicDiscoveryMix,
        MusicDiscoveryPreferences,
        MusicRecommendation,
        MusicRecommendationKind,
        MusicRecommendationSnapshot,
        OwnedMusicTrack;
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/music_discovery_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cache = MusicDiscoveryCache();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MusicRecommendation rec(
    MusicRecommendationKind kind,
    String name, {
    String? artist,
  }) =>
      MusicRecommendation(
        kind: kind,
        name: name,
        artist: artist,
        score: 1,
        lastFmUrl: Uri.https('www.last.fm', '/music/$name'),
        sourceSeeds: const <String>['Seed'],
      );

  MusicRecommendationSnapshot snap(String tag) => MusicRecommendationSnapshot(
        generatedAt: DateTime.utc(2026, 7, 1),
        recommendations: <MusicRecommendation>[
          rec(MusicRecommendationKind.track, 'Track $tag', artist: 'Artist'),
        ],
        artistSeeds: const <String>['Seed'],
        trackSeeds: const <String>[],
      );

  ServerInfo server(String active, {String? tailscale = '100.64.0.2'}) =>
      ServerInfo(
        server: active,
        lanServer: '192.168.1.2',
        tailscaleServer: tailscale,
        port: 8080,
        name: 'Home',
        version: '5.3.0',
      );

  test('scope stays stable across endpoints and falls back offline via lastScope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const pref = MusicDiscoveryPreferences();
    final lanScope = MusicDiscoveryCache.scopeFor(
      serverInfo: server('192.168.1.2'),
      userId: null,
    );
    expect(lanScope, startsWith('guest|'));
    expect(
      lanScope,
      MusicDiscoveryCache.scopeFor(
        serverInfo: server('100.64.0.2'),
        userId: null,
      ),
    );

    await cache.writeSnapshot(
      prefs,
      scope: lanScope,
      preferences: pref,
      snapshot: snap('lan'),
    );

    final offline = await cache.readSnapshot(
      prefs,
      preferences: pref,
      scopes: MusicDiscoveryCache.scopesFor(
        prefs,
        serverInfo: null,
        userId: null,
      ),
    );
    expect(offline?.recommendations.single.name, 'Track lan');

    final otherUser = await cache.readSnapshot(
      prefs,
      preferences: pref,
      scopes: MusicDiscoveryCache.scopesFor(
        prefs,
        serverInfo: null,
        userId: 'user-2',
      ),
    );
    expect(otherUser, isNull);
  });

  test('evicts LRU snapshot at 8 entries and removes legacy v1..v8 keys',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mobile_music_discovery_cache_v1_old': 'legacy1',
      'mobile_music_discovery_cache_v8_old': 'legacy8',
    });
    final prefs = await SharedPreferences.getInstance();
    const scope = 'user-1|home|8080|192.168.1.2';

    for (var i = 0; i < 9; i++) {
      await cache.writeSnapshot(
        prefs,
        scope: scope,
        preferences: MusicDiscoveryPreferences(
          mix: MusicDiscoveryMix.balanced,
          preferredTags: <String>{'tag$i'},
        ),
        snapshot: snap('$i'),
      );
    }

    expect(prefs.getString('mobile_music_discovery_cache_v1_old'), isNull);
    expect(prefs.getString('mobile_music_discovery_cache_v8_old'), isNull);
    expect(
      await cache.readSnapshot(
        prefs,
        preferences: const MusicDiscoveryPreferences(
          preferredTags: <String>{'tag0'},
        ),
        scopes: const <String>[scope],
      ),
      isNull,
    );
    expect(
      await cache.readSnapshot(
        prefs,
        preferences: const MusicDiscoveryPreferences(
          preferredTags: <String>{'tag8'},
        ),
        scopes: const <String>[scope],
      ),
      isNotNull,
    );

    await MusicDiscoveryCache.clearAll(prefs);
    expect(prefs.getString(MusicDiscoveryCache.cacheKey), isNull);
    expect(prefs.getString(MusicDiscoveryCache.lastScopeKey), isNull);
  });

  test('filters owned tracks, albums, and artists (>=3 tracks or album)', () {
    final snapshot = MusicRecommendationSnapshot(
      generatedAt: DateTime.utc(2026, 7, 1),
      recommendations: <MusicRecommendation>[
        rec(MusicRecommendationKind.artist, 'Three Tracks'),
        rec(MusicRecommendationKind.artist, 'Two Track Album'),
        rec(MusicRecommendationKind.artist, 'One Track Only'),
        rec(MusicRecommendationKind.album, 'Owned LP', artist: 'One Track Only'),
        rec(MusicRecommendationKind.track, 'Song A (Remastered)',
            artist: 'One Track Only'),
        rec(MusicRecommendationKind.track, 'Fresh Song',
            artist: 'One Track Only'),
      ],
      artistSeeds: const <String>[],
      trackSeeds: const <String>[],
    );

    final filtered = MusicDiscoveryCache.filterOwnedRecommendations(
      snapshot,
      const <OwnedMusicTrack>[
        OwnedMusicTrack(title: '1', artist: 'Three Tracks'),
        OwnedMusicTrack(title: '2', artist: 'Three Tracks'),
        OwnedMusicTrack(title: '3', artist: 'Three Tracks'),
        OwnedMusicTrack(title: 'A', artist: 'Two Track Album', album: 'Duo'),
        OwnedMusicTrack(title: 'B', artist: 'Two Track Album', album: 'Duo'),
        OwnedMusicTrack(
          title: 'Song A',
          artist: 'One Track Only',
          album: 'Owned LP',
        ),
      ],
    );

    expect(
      filtered.recommendations.map((r) => '${r.kind.name}:${r.name}'),
      <String>['artist:One Track Only', 'track:Fresh Song'],
    );
  });

  test('dismisses and restores recommendations', () async {
    final prefs = await SharedPreferences.getInstance();
    final item = rec(MusicRecommendationKind.track, 'Song', artist: 'Artist');
    await cache.dismiss(prefs, item);
    expect(
      await cache.readDismissed(prefs),
      <String>{MusicDiscoveryCache.keyFor(item)},
    );
    await cache.restoreAll(prefs);
    expect(await cache.readDismissed(prefs), isEmpty);
  });
}
