import 'package:ariami_core/ariami_core.dart';

/// Applies one advertised-endpoint precedence policy at startup and refresh.
NetworkEndpoints resolveAdvertisedEndpoints({
  required String bindHost,
  String? detectedTailscaleHost,
  String? detectedLanHost,
  String? advertisedHostOverride,
  String? advertisedLanHostOverride,
  String? advertisedTailscaleHostOverride,
}) {
  final tailscaleHost =
      advertisedTailscaleHostOverride ?? detectedTailscaleHost;
  final lanHost =
      advertisedLanHostOverride ?? advertisedHostOverride ?? detectedLanHost;
  final advertisedHost = _isLocalBindHost(bindHost)
      ? 'localhost'
      : advertisedHostOverride ?? tailscaleHost ?? lanHost ?? 'localhost';

  return NetworkEndpoints(
    advertisedIp: advertisedHost,
    tailscaleIp: tailscaleHost,
    lanIp: lanHost,
  );
}

bool _isLocalBindHost(String bindHost) {
  final normalized = bindHost.trim().toLowerCase();
  return normalized == '127.0.0.1' || normalized == 'localhost';
}
