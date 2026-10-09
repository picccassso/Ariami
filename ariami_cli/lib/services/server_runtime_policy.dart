import 'dart:io';

import 'package:ariami_core/services/server/download_limits.dart';
import 'package:ariami_core/utils/device_model.dart';

enum StorageType { microSd, fastExternal, unknown }

enum StorageProfile { microSd, externalFast, unknown }

class CachePolicy {
  final int transcodeCacheSizeMB;
  final int artworkCacheSizeMB;
  final Duration transcodeIndexPersistInterval;
  final bool touchArtworkOnCacheHit;
  final Duration artworkTouchThrottle;

  const CachePolicy({
    required this.transcodeCacheSizeMB,
    required this.artworkCacheSizeMB,
    required this.transcodeIndexPersistInterval,
    required this.touchArtworkOnCacheHit,
    required this.artworkTouchThrottle,
  });
}

/// Detects host capabilities and chooses platform-sensitive server limits.
class ServerRuntimePolicy {
  static const _modelPaths = ['/proc/device-tree/model', '/proc/cpuinfo'];

  bool isRaspberryPi() => DeviceModel.isRaspberryPi();

  Future<bool> isRaspberryPi5() => DeviceModel.isRaspberryPiGeneration(
        5,
        paths: _modelPaths,
      );

  Future<StorageType> detectStorageType(String? targetPath) async {
    if (!Platform.isLinux || targetPath == null || targetPath.isEmpty) {
      return StorageType.unknown;
    }

    final mountsFile = File('/proc/mounts');
    if (!await mountsFile.exists()) {
      return StorageType.unknown;
    }

    try {
      final lines = await mountsFile.readAsLines();
      String? bestMountPoint;
      String? bestDevice;

      for (final line in lines) {
        final parts = line.split(' ');
        if (parts.length < 2) continue;
        final device = parts[0];
        final mountPoint = parts[1];

        if (targetPath.startsWith(mountPoint)) {
          if (bestMountPoint == null ||
              mountPoint.length > bestMountPoint.length) {
            bestMountPoint = mountPoint;
            bestDevice = device;
          }
        }
      }

      if (bestDevice == null) {
        return StorageType.unknown;
      }

      final device = bestDevice.toLowerCase();
      if (device.contains('mmcblk')) {
        return StorageType.microSd;
      }
      if (device.contains('nvme') || device.contains('/dev/sd')) {
        return StorageType.fastExternal;
      }
    } catch (_) {
      // Ignore mount parsing errors.
    }

    return StorageType.unknown;
  }

  DownloadLimits selectDownloadLimits({
    required bool isPi,
    required bool isPi5,
    required StorageType storageType,
  }) {
    if (!isPi) return DownloadLimits.forDesktopPlatform();

    if (storageType == StorageType.fastExternal) {
      return const DownloadLimits(
        maxConcurrent: 6,
        maxQueue: 80,
        maxConcurrentPerUser: 4,
        maxQueuePerUser: 30,
      );
    }

    if (isPi5) {
      return const DownloadLimits(
        maxConcurrent: 4,
        maxQueue: 50,
        maxConcurrentPerUser: 4,
        maxQueuePerUser: 20,
      );
    }

    // Pi 3/4 with microSD or unknown storage: downloads are mostly I/O-bound.
    return const DownloadLimits(
      maxConcurrent: 4,
      maxQueue: 50,
      maxConcurrentPerUser: 4,
      maxQueuePerUser: 20,
    );
  }
}

StorageProfile selectStorageProfile({
  required bool isPi,
  required StorageType musicStorageType,
  required StorageType stateStorageType,
  String? override,
}) {
  final normalized = override?.trim().toLowerCase();
  if (normalized != null && normalized.isNotEmpty) {
    switch (normalized) {
      case 'microsd':
      case 'micro_sd':
      case 'micro-sd':
      case 'sd':
        return StorageProfile.microSd;
      case 'externalfast':
      case 'external_fast':
      case 'external-fast':
      case 'ssd':
      case 'fast':
        return StorageProfile.externalFast;
      case 'unknown':
      case 'auto':
        break;
      default:
        print(
            'Unknown ARIAMI_STORAGE_PROFILE="$override"; using auto detection.');
    }
  }

  if (!isPi) return StorageProfile.unknown;
  if (stateStorageType == StorageType.microSd ||
      musicStorageType == StorageType.microSd) {
    return StorageProfile.microSd;
  }
  if (stateStorageType == StorageType.fastExternal &&
      musicStorageType == StorageType.fastExternal) {
    return StorageProfile.externalFast;
  }
  return StorageProfile.unknown;
}

CachePolicy selectCachePolicy({
  required bool isPi,
  required bool isPi5,
  required StorageProfile storageProfile,
}) {
  if (!isPi && (Platform.isMacOS || Platform.isWindows)) {
    return const CachePolicy(
      transcodeCacheSizeMB: 4096,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  if (!isPi) {
    return const CachePolicy(
      transcodeCacheSizeMB: 2048,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  if (storageProfile == StorageProfile.externalFast) {
    return CachePolicy(
      transcodeCacheSizeMB: isPi5 ? 2048 : 1024,
      artworkCacheSizeMB: 256,
      transcodeIndexPersistInterval: const Duration(seconds: 30),
      touchArtworkOnCacheHit: true,
      artworkTouchThrottle: Duration.zero,
    );
  }

  return const CachePolicy(
    transcodeCacheSizeMB: 384,
    artworkCacheSizeMB: 96,
    transcodeIndexPersistInterval: Duration(minutes: 5),
    touchArtworkOnCacheHit: false,
    artworkTouchThrottle: Duration(minutes: 30),
  );
}
