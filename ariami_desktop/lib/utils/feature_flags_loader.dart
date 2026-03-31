import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';

/// Loads [AriamiFeatureFlags] from process environment (desktop / CLI).
AriamiFeatureFlags loadFeatureFlagsFromEnvironment() {
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

void validateFeatureFlagInvariantsOrThrow(AriamiFeatureFlags flags) {
  if (flags.enableDownloadJobs && !flags.enableV2Api) {
    throw StateError(
      'Invalid feature flag configuration: enableDownloadJobs=true '
      'requires enableV2Api=true.',
    );
  }
}
