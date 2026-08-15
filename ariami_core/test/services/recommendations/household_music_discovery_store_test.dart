import 'dart:io';

import 'package:ariami_core/services/recommendations/household_music_discovery_store.dart';
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
}
