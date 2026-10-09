import 'dart:io';

import '../models/feature_flags.dart';

/// Reads a boolean env var: `1`/`true`/`yes`/`on` (trimmed, case-insensitive)
/// are true, anything else false, unset yields [defaultValue].
bool parseBoolEnv(String key, {bool defaultValue = false}) {
  final value = Platform.environment[key];
  if (value == null) return defaultValue;

  final normalized = value.trim().toLowerCase();
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'on';
}

/// Builds the rollout flags from `ARIAMI_ENABLE_*` environment variables.
AriamiFeatureFlags loadFeatureFlagsFromEnvironment() => AriamiFeatureFlags(
      enableV2Api: parseBoolEnv('ARIAMI_ENABLE_V2_API', defaultValue: true),
      enableCatalogWrite: parseBoolEnv('ARIAMI_ENABLE_CATALOG_WRITE'),
      enableCatalogRead: parseBoolEnv('ARIAMI_ENABLE_CATALOG_READ'),
      enableArtworkPrecompute: parseBoolEnv('ARIAMI_ENABLE_ARTWORK_PRECOMPUTE'),
      enableDownloadJobs:
          parseBoolEnv('ARIAMI_ENABLE_DOWNLOAD_JOBS', defaultValue: true),
      enableApiScopedAuthForCliWeb: parseBoolEnv(
        'ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB',
        defaultValue: true,
      ),
      enableConnectProtocolV3: parseBoolEnv(
        'ARIAMI_ENABLE_CONNECT_PROTOCOL_V3',
        defaultValue: true,
      ),
    );

/// Startup-time invariant check shared by the CLI and desktop hosts.
void validateFeatureFlagInvariantsOrThrow(AriamiFeatureFlags flags) {
  if (flags.enableDownloadJobs && !flags.enableV2Api) {
    throw StateError(
      'Invalid feature flag configuration: enableDownloadJobs=true '
      'requires enableV2Api=true.',
    );
  }
}
