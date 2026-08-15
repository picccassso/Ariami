import 'dart:convert';

import 'music_discovery_api_key_config.dart';

typedef MusicDiscoveryKeyReader = Future<String?> Function();
typedef MusicDiscoveryKeyWriter = Future<void> Function(String value);
typedef MusicDiscoveryKeyDeleter = Future<void> Function();
typedef MusicDiscoveryConfigReader = Future<MusicDiscoveryApiKeyConfig>
    Function();
typedef MusicDiscoveryConfigWriter = Future<MusicDiscoveryApiKeyConfig>
    Function(String value);
typedef MusicDiscoveryConfigDeleter = Future<MusicDiscoveryApiKeyConfig>
    Function();

/// Resolved API-key state for one client and one connected Ariami household.
class MusicDiscoveryApiKeySyncState {
  const MusicDiscoveryApiKeySyncState({
    required this.embeddedKey,
    required this.localKey,
    required this.householdKey,
    required this.remoteConfig,
  });

  final String? embeddedKey;
  final String? localKey;
  final String? householdKey;

  /// Null when the server is offline or predates household key sync.
  final MusicDiscoveryApiKeyConfig? remoteConfig;

  String? get effectiveKey => embeddedKey ?? householdKey ?? localKey;
  bool get hasKey => effectiveKey != null;
  bool get isHouseholdManaged => embeddedKey == null && householdKey != null;
  bool get canManageHousehold => remoteConfig?.canManage ?? false;
}

class MusicDiscoveryApiKeySaveResult {
  const MusicDiscoveryApiKeySaveResult({
    required this.state,
    required this.syncAttempted,
    required this.syncSucceeded,
  });

  final MusicDiscoveryApiKeySyncState state;
  final bool syncAttempted;
  final bool syncSucceeded;
}

/// Coordinates local fallback and household-server synchronization without
/// depending on Flutter or either client's HTTP implementation.
class MusicDiscoveryApiKeySync {
  const MusicDiscoveryApiKeySync({
    required this.readLocalKey,
    required this.writeLocalKey,
    required this.readHouseholdCache,
    required this.writeHouseholdCache,
    required this.deleteHouseholdCache,
    this.fetchRemoteConfig,
    this.putRemoteKey,
    this.putRemoteKeyIfMissing,
    this.deleteRemoteKey,
  });

  final MusicDiscoveryKeyReader readLocalKey;
  final MusicDiscoveryKeyWriter writeLocalKey;
  final MusicDiscoveryKeyReader readHouseholdCache;
  final MusicDiscoveryKeyWriter writeHouseholdCache;
  final MusicDiscoveryKeyDeleter deleteHouseholdCache;
  final MusicDiscoveryConfigReader? fetchRemoteConfig;
  final MusicDiscoveryConfigWriter? putRemoteKey;
  final MusicDiscoveryConfigWriter? putRemoteKeyIfMissing;
  final MusicDiscoveryConfigDeleter? deleteRemoteKey;

  Future<MusicDiscoveryApiKeySyncState> load({String? embeddedKey}) async {
    final normalizedEmbedded = _normalize(embeddedKey);
    final values = await Future.wait<String?>(<Future<String?>>[
      readLocalKey(),
      readHouseholdCache(),
    ]);
    final localKey = _normalize(values[0]);
    var householdKey = _normalize(values[1]);
    MusicDiscoveryApiKeyConfig? remoteConfig;

    // Preserve the existing build-time contract: an embedded Ariami key is
    // authoritative and does not need a household round trip.
    if (normalizedEmbedded == null && fetchRemoteConfig != null) {
      try {
        remoteConfig = await fetchRemoteConfig!();
        householdKey = _normalize(remoteConfig.lastFmApiKey);
        if (householdKey == null &&
            localKey != null &&
            remoteConfig.canManage &&
            putRemoteKeyIfMissing != null) {
          remoteConfig = await putRemoteKeyIfMissing!(localKey);
          householdKey = _normalize(remoteConfig.lastFmApiKey);
        }
        if (householdKey == null) {
          await deleteHouseholdCache();
        } else {
          await writeHouseholdCache(householdKey);
        }
      } catch (_) {
        // Offline and older servers retain the scoped cached household key.
      }
    }

    return MusicDiscoveryApiKeySyncState(
      embeddedKey: normalizedEmbedded,
      localKey: localKey,
      householdKey: householdKey,
      remoteConfig: remoteConfig,
    );
  }

  /// Saves the key locally first, then shares it when this signed-in account
  /// is the owner. A failed server write leaves a usable offline fallback and
  /// is reported to the UI instead of pretending synchronization succeeded.
  Future<MusicDiscoveryApiKeySaveResult> save(
    MusicDiscoveryApiKeySyncState current,
    String value,
  ) async {
    final key = _normalize(value);
    if (key == null) throw ArgumentError('Last.fm API key must not be empty');

    // Saving recommendation preferences with an unchanged household key must
    // not silently turn that shared value into a personal fallback on every
    // member device.
    if (current.householdKey == key) {
      return MusicDiscoveryApiKeySaveResult(
        state: current,
        syncAttempted: false,
        syncSucceeded: true,
      );
    }
    await writeLocalKey(key);

    if (current.embeddedKey != null) {
      return MusicDiscoveryApiKeySaveResult(
        state: _copy(current, localKey: key),
        syncAttempted: false,
        syncSucceeded: false,
      );
    }

    final canAttemptSync = current.remoteConfig?.canManage == true;
    if (!canAttemptSync || putRemoteKey == null) {
      return MusicDiscoveryApiKeySaveResult(
        state: _copy(current, localKey: key),
        syncAttempted: false,
        syncSucceeded: false,
      );
    }

    try {
      final config = await putRemoteKey!(key);
      final householdKey = _normalize(config.lastFmApiKey) ?? key;
      await writeHouseholdCache(householdKey);
      return MusicDiscoveryApiKeySaveResult(
        state: MusicDiscoveryApiKeySyncState(
          embeddedKey: current.embeddedKey,
          localKey: key,
          householdKey: householdKey,
          remoteConfig: config,
        ),
        syncAttempted: true,
        syncSucceeded: true,
      );
    } catch (_) {
      return MusicDiscoveryApiKeySaveResult(
        state: _copy(current, localKey: key),
        syncAttempted: true,
        syncSucceeded: false,
      );
    }
  }

  Future<MusicDiscoveryApiKeySaveResult> removeHouseholdKey(
    MusicDiscoveryApiKeySyncState current,
  ) async {
    if (!current.canManageHousehold || deleteRemoteKey == null) {
      return MusicDiscoveryApiKeySaveResult(
        state: current,
        syncAttempted: false,
        syncSucceeded: false,
      );
    }
    try {
      final config = await deleteRemoteKey!();
      await deleteHouseholdCache();
      return MusicDiscoveryApiKeySaveResult(
        state: MusicDiscoveryApiKeySyncState(
          embeddedKey: current.embeddedKey,
          localKey: current.localKey,
          householdKey: null,
          remoteConfig: config,
        ),
        syncAttempted: true,
        syncSucceeded: true,
      );
    } catch (_) {
      return MusicDiscoveryApiKeySaveResult(
        state: current,
        syncAttempted: true,
        syncSucceeded: false,
      );
    }
  }

  static MusicDiscoveryApiKeySyncState _copy(
    MusicDiscoveryApiKeySyncState source, {
    String? localKey,
  }) {
    return MusicDiscoveryApiKeySyncState(
      embeddedKey: source.embeddedKey,
      localKey: localKey ?? source.localKey,
      householdKey: source.householdKey,
      remoteConfig: source.remoteConfig,
    );
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ||
            utf8.encode(normalized).length >
                MusicDiscoveryApiKeyConfig.maxApiKeyBytes
        ? null
        : normalized;
  }
}
