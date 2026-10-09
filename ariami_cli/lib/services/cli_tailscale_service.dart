import 'package:ariami_core/services/server/tailscale_locator.dart';

import 'container_environment.dart';

class CliTailscaleService {
  CliTailscaleService({ContainerEnvironment? environment})
      : _environment = environment ?? ContainerEnvironment();

  final ContainerEnvironment _environment;

  /// Get LAN IP address (for when Tailscale isn't available)
  ///
  /// Returns the first private network IP address found (192.168.x.x, 10.x.x.x, 172.x.x.x)
  Future<String?> getLanIp() => TailscaleLocator.getLanIp(
        skipTailscaleInterfaces: true,
        onError: (e) => print('Error getting LAN IP: $e'),
      );

  /// Get the Tailscale IP address using cross-platform detection
  ///
  /// Primary method: `tailscale ip -4` CLI command
  /// Fallback: NetworkInterface scanning for CGNAT range (100.64.0.0/10)
  Future<String?> getTailscaleIp() => TailscaleLocator.getTailscaleIp();

  Future<bool> isTailscaleInstalled() async =>
      await TailscaleLocator.findBinary() != null;

  Future<bool> isTailscaleRunning() async => await getTailscaleIp() != null;

  /// Get Tailscale status as a map (for API endpoint)
  Future<Map<String, dynamic>> getStatus() async {
    final isInstalled = await isTailscaleInstalled();
    final isRunning = await isTailscaleRunning();
    final ip = await getTailscaleIp();

    return {
      'isInstalled': isInstalled,
      'isRunning': isRunning,
      'ip': ip,
      'containerized': _environment.isContainerized,
      'advertisedHost': _environment.advertisedHostOverride,
      'advertisedLanHost': _environment.advertisedLanHostOverride,
      'advertisedTailscaleHost': _environment.advertisedTailscaleHostOverride,
    };
  }
}
