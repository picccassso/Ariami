import 'package:ariami_core/services/recommendations/music_discovery_api_key_config.dart';
import 'package:ariami_core/services/recommendations/music_discovery_api_key_sync.dart';
import 'package:test/test.dart';

void main() {
  String? local;
  String? cache;
  MusicDiscoveryApiKeyConfig? remote;
  var writes = 0;
  var deletes = 0;

  MusicDiscoveryApiKeySync service({bool remoteFails = false}) =>
      MusicDiscoveryApiKeySync(
        readLocalKey: () async => local,
        writeLocalKey: (value) async => local = value,
        readHouseholdCache: () async => cache,
        writeHouseholdCache: (value) async => cache = value,
        deleteHouseholdCache: () async => cache = null,
        fetchRemoteConfig: () async {
          if (remoteFails) throw StateError('offline');
          return remote!;
        },
        putRemoteKey: (value) async {
          writes++;
          remote = MusicDiscoveryApiKeyConfig(
            lastFmApiKey: value,
            canManage: true,
          );
          return remote!;
        },
        putRemoteKeyIfMissing: (value) async {
          writes++;
          if (remote!.lastFmApiKey == null) {
            remote = MusicDiscoveryApiKeyConfig(
              lastFmApiKey: value,
              canManage: true,
            );
          }
          return remote!;
        },
        deleteRemoteKey: () async {
          deletes++;
          remote = const MusicDiscoveryApiKeyConfig(
            lastFmApiKey: null,
            canManage: true,
          );
          return remote!;
        },
      );

  setUp(() {
    local = null;
    cache = null;
    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: null,
      canManage: true,
    );
    writes = 0;
    deletes = 0;
  });

  test('household key wins over local and refreshes its offline cache',
      () async {
    local = 'local-key';
    cache = 'stale-key';
    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: 'household-key',
      canManage: false,
    );

    final state = await service().load();
    expect(state.effectiveKey, 'household-key');
    expect(state.isHouseholdManaged, isTrue);
    expect(state.canManageHousehold, isFalse);
    expect(cache, 'household-key');
  });

  test('offline load uses the scoped household cache before local fallback',
      () async {
    local = 'local-key';
    cache = 'cached-household-key';

    final state = await service(remoteFails: true).load();
    expect(state.effectiveKey, 'cached-household-key');
    expect(state.remoteConfig, isNull);
  });

  test('an empty online server clears stale cache and reveals local key',
      () async {
    cache = 'stale-household-key';

    final state = await service().load();
    expect(state.effectiveKey, isNull);
    expect(state.householdKey, isNull);
    expect(cache, isNull);
  });

  test('owner existing local key migrates once without overwriting a winner',
      () async {
    local = 'existing-local-key';

    final migrated = await service().load();
    expect(migrated.effectiveKey, 'existing-local-key');
    expect(migrated.householdKey, 'existing-local-key');
    expect(cache, 'existing-local-key');
    expect(writes, 1);

    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: 'other-device-won',
      canManage: true,
    );
    cache = null;
    final existingWins = await service().load();
    expect(existingWins.effectiveKey, 'other-device-won');
    expect(writes, 1);
  });

  test('embedded key stays authoritative without contacting the server',
      () async {
    local = 'local-key';
    cache = 'cached-household-key';

    final state = await service(remoteFails: true).load(
      embeddedKey: 'embedded-key',
    );
    expect(state.effectiveKey, 'embedded-key');
    expect(state.remoteConfig, isNull);
  });

  test('owner save updates local fallback, server, and household cache',
      () async {
    final state = await service().load();
    final result = await service().save(state, ' new-key ');

    expect(result.syncAttempted, isTrue);
    expect(result.syncSucceeded, isTrue);
    expect(result.state.effectiveKey, 'new-key');
    expect(local, 'new-key');
    expect(cache, 'new-key');
    expect(remote!.lastFmApiKey, 'new-key');
    expect(writes, 1);
  });

  test('member save remains local and cannot replace household key', () async {
    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: 'owner-key',
      canManage: false,
    );
    final state = await service().load();
    final result = await service().save(state, 'member-key');

    expect(result.syncAttempted, isFalse);
    expect(result.state.effectiveKey, 'owner-key');
    expect(local, 'member-key');
    expect(remote!.lastFmApiKey, 'owner-key');
    expect(writes, 0);
  });

  test('saving unchanged shared key does not create a personal fallback',
      () async {
    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: 'owner-key',
      canManage: false,
    );
    final state = await service().load();
    final result = await service().save(state, 'owner-key');

    expect(result.syncSucceeded, isTrue);
    expect(local, isNull);
    expect(writes, 0);
  });

  test('owner can remove household key while retaining local fallback',
      () async {
    local = 'local-key';
    remote = const MusicDiscoveryApiKeyConfig(
      lastFmApiKey: 'household-key',
      canManage: true,
    );
    final state = await service().load();
    final result = await service().removeHouseholdKey(state);

    expect(result.syncSucceeded, isTrue);
    expect(result.state.effectiveKey, 'local-key');
    expect(cache, isNull);
    expect(deletes, 1);
  });

  test('rejects an oversized local key before writing or syncing', () async {
    final state = await service().load();
    expect(
      () => service().save(
        state,
        'A' * (MusicDiscoveryApiKeyConfig.maxApiKeyBytes + 1),
      ),
      throwsArgumentError,
    );
    expect(local, isNull);
    expect(writes, 0);
  });
}
