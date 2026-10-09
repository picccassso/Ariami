import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/utils/feature_flags_env.dart';

/// Loads and validates feature flags used during CLI server startup.
class ServerFeatureFlagService {
  AriamiFeatureFlags loadFromEnvironment() => loadFeatureFlagsFromEnvironment();

  /// Env override that forces the pre-auth sign-in account picker on even
  /// when the persisted config turned it off.
  ///
  /// Not part of [AriamiFeatureFlags]: it's an owner privacy setting rather
  /// than a rollout flag. The picker is off by default; the persisted config
  /// (web dashboard switch) is the normal way to enable it.
  bool loadPublicUserPickerFromEnvironment() {
    return parseBoolEnv('ARIAMI_ENABLE_PUBLIC_USER_PICKER');
  }

  /// Whether the server should trust `X-Forwarded-For` when resolving
  /// client IPs for rate limiting. Only set this when Ariami runs behind a
  /// reverse proxy the owner controls; otherwise clients can spoof their
  /// address and rotate rate-limit buckets.
  bool loadTrustProxyHeadersFromEnvironment() {
    return parseBoolEnv('ARIAMI_TRUST_PROXY_HEADERS');
  }

  void validateOrThrow(AriamiFeatureFlags flags) =>
      validateFeatureFlagInvariantsOrThrow(flags);
}
