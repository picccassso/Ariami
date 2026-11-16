import 'package:ariami_mobile/services/music_discovery_api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = MusicDiscoveryApiKeyStore();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('migrates the old secure-storage key once into local preferences',
      () async {
    final preferences = await SharedPreferences.getInstance();
    var legacyReads = 0;

    final first = await store.readAndMigrate(
      preferences,
      readLegacyKey: () async {
        legacyReads++;
        return ' legacy-key ';
      },
    );
    final second = await store.readAndMigrate(
      preferences,
      readLegacyKey: () async {
        legacyReads++;
        return 'unexpected';
      },
    );

    expect(first, 'legacy-key');
    expect(second, 'legacy-key');
    expect(legacyReads, 1);
  });

  test('a declined migration is not retried', () async {
    final preferences = await SharedPreferences.getInstance();
    var legacyReads = 0;

    Future<String?> denied() async {
      legacyReads++;
      throw StateError('credential access declined');
    }

    expect(
      await store.readAndMigrate(preferences, readLegacyKey: denied),
      isNull,
    );
    expect(
      await store.readAndMigrate(preferences, readLegacyKey: denied),
      isNull,
    );
    expect(legacyReads, 1);
  });

  test('deleting a local key does not resurrect the legacy copy', () async {
    final preferences = await SharedPreferences.getInstance();
    var legacyReads = 0;
    await store.write(preferences, 'local-key');
    await store.delete(preferences);

    final key = await store.readAndMigrate(
      preferences,
      readLegacyKey: () async {
        legacyReads++;
        return 'legacy-key';
      },
    );

    expect(key, isNull);
    expect(legacyReads, 0);
  });

  test('blank values clear stored local and household keys', () async {
    final preferences = await SharedPreferences.getInstance();
    await store.write(preferences, 'local-key');
    await store.writeHouseholdCache(preferences, 'server-a|owner', 'key-a');

    await store.write(preferences, '   ');
    await store.writeHouseholdCache(preferences, 'server-a|owner', ' \t ');

    expect(preferences.getString(MusicDiscoveryApiKeyStore.key), isNull);
    expect(
      await store.readHouseholdCache(preferences, 'server-a|owner'),
      isNull,
    );
  });

  test('household caches are isolated by server scope', () async {
    final preferences = await SharedPreferences.getInstance();
    await store.writeHouseholdCache(preferences, 'server-a|owner', 'key-a');
    await store.writeHouseholdCache(preferences, 'server-b|owner', 'key-b');

    expect(
      await store.readHouseholdCache(preferences, 'server-a|owner'),
      'key-a',
    );
    expect(
      await store.readHouseholdCache(preferences, 'server-b|owner'),
      'key-b',
    );

    await store.deleteHouseholdCache(preferences, 'server-a|owner');
    expect(
      await store.readHouseholdCache(preferences, 'server-a|owner'),
      isNull,
    );
    expect(
      await store.readHouseholdCache(preferences, 'server-b|owner'),
      'key-b',
    );
  });
}
