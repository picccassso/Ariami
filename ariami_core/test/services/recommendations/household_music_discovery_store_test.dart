import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String storePath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ariami_discovery_key_');
    storePath = p.join(directory.path, 'music_discovery.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('starts empty and persists a normalized API key', () async {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(store.lastFmApiKey, isNull);

    await store.save('  household-key  ');
    expect(store.lastFmApiKey, 'household-key');

    final reopened = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(reopened.lastFmApiKey, 'household-key');
  });

  test('serializes mutations and leaves the latest value on disk', () async {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    await Future.wait(<Future<void>>[
      store.save('first-key'),
      store.save('second-key'),
      store.clear(),
      store.save('latest-key'),
    ]);

    expect(store.lastFmApiKey, 'latest-key');
    final reopened = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(reopened.lastFmApiKey, 'latest-key');
  });

  test('saveIfEmpty lets exactly one concurrent migration win', () async {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    final results = await Future.wait<bool>(<Future<bool>>[
      store.saveIfEmpty('desktop-key'),
      store.saveIfEmpty('mobile-key'),
    ]);

    expect(results.where((saved) => saved), hasLength(1));
    expect(store.lastFmApiKey, anyOf('desktop-key', 'mobile-key'));
    final reopened = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(reopened.lastFmApiKey, store.lastFmApiKey);
  });

  test('clear removes memory and disk state', () async {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    await store.save('household-key');
    await store.clear();

    expect(store.lastFmApiKey, isNull);
    expect(File(storePath).existsSync(), isFalse);
  });

  test('rejects empty and oversized keys', () {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(() => store.save('   '), throwsArgumentError);
    expect(
      () => store.save(
        'é' * (HouseholdMusicDiscoveryStore.maxApiKeyBytes ~/ 2 + 1),
      ),
      throwsArgumentError,
    );
  });

  test('ignores malformed and oversized files without blocking startup', () {
    File(storePath).writeAsStringSync('{not-json');
    var store = HouseholdMusicDiscoveryStore(filePath: storePath)..initialize();
    expect(store.lastFmApiKey, isNull);

    File(storePath).writeAsStringSync(
      '{"lastFmApiKey":"${'A' * (HouseholdMusicDiscoveryStore.maxApiKeyBytes + 1)}"}',
    );
    store = HouseholdMusicDiscoveryStore(filePath: storePath)..initialize();
    expect(store.lastFmApiKey, isNull);
  });

  test('throws when used before initialize', () {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath);
    expect(() => store.lastFmApiKey, throwsStateError);
  });

  test('persists wishlist, webhookUrl, feedToken, and prunes owned items',
      () async {
    final store = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    final track = MusicRecommendation(
      kind: MusicRecommendationKind.track,
      name: 'Fresh Track',
      artist: 'Artist A',
      score: 1,
      lastFmUrl: Uri.https('www.last.fm', '/music/Artist+A/_/Fresh+Track'),
      artistMusicBrainzId: '11111111-1111-1111-1111-111111111111',
      sourceSeeds: const <String>['Seed'],
    );
    final artist = MusicRecommendation(
      kind: MusicRecommendationKind.artist,
      name: 'Artist B',
      score: 1,
      lastFmUrl: Uri.https('www.last.fm', '/music/Artist+B'),
      musicBrainzId: '22222222-2222-2222-2222-222222222222',
      sourceSeeds: const <String>['Seed'],
    );

    await store.saveWebhookUrl('https://example.com/hook');
    await store.addWishlistItem(track);
    await store.addWishlistItem(artist);

    final reopened = HouseholdMusicDiscoveryStore(filePath: storePath)
      ..initialize();
    expect(reopened.webhookUrl, 'https://example.com/hook');
    expect(reopened.feedToken, store.feedToken);
    expect(reopened.wishlist.map((i) => i.name), <String>['Artist B', 'Fresh Track']);

    final removedOwned = await reopened.removeOwnedWishlistItems(
      OwnedMusicIndex(const <OwnedMusicTrack>[
        OwnedMusicTrack(title: 'Fresh Track', artist: 'Artist A'),
      ]),
    );
    expect(removedOwned, 1);
    expect(reopened.wishlist.map((i) => i.name), <String>['Artist B']);

    expect(await reopened.removeWishlistItem(artist.identityKey), isTrue);
    expect(reopened.wishlist, isEmpty);
  });
}
