import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';

/// Loads and validates feature flags used during CLI server startup.
class ServerFeatureFlagService {
  AriamiFeatureFlags loadFromEnvironment() {
    bool parseFlag(String key, {required bool defaultValue}) {
      final value = Platform.environment[key];
      if (value == null) return defaultValue;

      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'on';
    }

    return AriamiFeatureFlags(
      enableV2Api: parseFlag('ARIAMI_ENABLE_V2_API', defaultValue: true),
      enableCatalogWrite:
          parseFlag('ARIAMI_ENABLE_CATALOG_WRITE', defaultValue: false),
      enableCatalogRead:
          parseFlag('ARIAMI_ENABLE_CATALOG_READ', defaultValue: false),
      enableArtworkPrecompute:
          parseFlag('ARIAMI_ENABLE_ARTWORK_PRECOMPUTE', defaultValue: false),
      enableDownloadJobs:
          parseFlag('ARIAMI_ENABLE_DOWNLOAD_JOBS', defaultValue: true),
      enableApiScopedAuthForCliWeb: parseFlag(
        'ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB',
        defaultValue: true,
      ),
    );
  }

  /// Env override that forces the pre-auth sign-in account picker on even
  /// when the persisted config turned it off.
  ///
  /// Not part of [AriamiFeatureFlags]: it's an owner privacy setting rather
  /// than a rollout flag. The picker itself is on by default; the persisted
  /// config (web dashboard switch) is the normal way to control it.
  bool loadPublicUserPickerFromEnvironment() {
    final value = Platform.environment['ARIAMI_ENABLE_PUBLIC_USER_PICKER'];
    if (value == null) return false;

    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  void validateOrThrow(AriamiFeatureFlags flags) {
    if (flags.enableDownloadJobs && !flags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableDownloadJobs=true '
        'requires enableV2Api=true.',
      );
    }
  }
}
