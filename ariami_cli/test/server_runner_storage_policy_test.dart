import 'package:ariami_cli/server_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('storage profile policy', () {
    test('override forces microSD profile', () {
      final profile = selectStorageProfile(
        isPi: true,
        musicStorageType: StorageType.fastExternal,
        stateStorageType: StorageType.fastExternal,
        override: 'microsd',
      );

      expect(profile, StorageProfile.microSd);
    });

    test('Pi with state on microSD uses conservative profile', () {
      final profile = selectStorageProfile(
        isPi: true,
        musicStorageType: StorageType.fastExternal,
        stateStorageType: StorageType.microSd,
      );

      expect(profile, StorageProfile.microSd);
    });

    test('Pi with fast music and state storage uses fast profile', () {
      final profile = selectStorageProfile(
        isPi: true,
        musicStorageType: StorageType.fastExternal,
        stateStorageType: StorageType.fastExternal,
      );

      expect(profile, StorageProfile.externalFast);
    });

    test('microSD cache policy reduces write cadence and cache size', () {
      final policy = selectCachePolicy(
        isPi: true,
        isPi5: false,
        storageProfile: StorageProfile.microSd,
      );

      expect(policy.transcodeCacheSizeMB, lessThan(1024));
      expect(policy.artworkCacheSizeMB, lessThan(256));
      expect(policy.transcodeIndexPersistInterval, const Duration(minutes: 5));
      expect(policy.touchArtworkOnCacheHit, isFalse);
    });
  });
}
