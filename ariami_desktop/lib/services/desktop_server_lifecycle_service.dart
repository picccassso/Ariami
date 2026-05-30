import 'package:ariami_core/ariami_core.dart';

import 'desktop_state_service.dart';
import 'desktop_tailscale_service.dart';
import 'server_initialization_service.dart';

/// Successful desktop server launch with the advertised network address.
class DesktopServerLaunchResult {
  const DesktopServerLaunchResult({
    required this.advertisedIp,
    required this.serverStart,
  });

  final String advertisedIp;
  final DesktopServerStartResult serverStart;
}

/// Starts the desktop server after resolving network and auth configuration.
class DesktopServerLifecycleService {
  const DesktopServerLifecycleService({
    required this.httpServer,
    required this.stateService,
    required this.tailscaleService,
  });

  final AriamiHttpServer httpServer;
  final DesktopStateService stateService;
  final DesktopTailscaleService tailscaleService;

  /// Returns null when no LAN or Tailscale address is currently available.
  Future<DesktopServerLaunchResult?> start() async {
    final tailscaleIp = await tailscaleService.getTailscaleIp();
    final lanIp = await tailscaleService.getLanIp();
    final advertisedIp = tailscaleIp ?? lanIp;
    if (advertisedIp == null) {
      return null;
    }

    await ServerInitializationService.initializeAuth(httpServer, stateService);
    await ServerInitializationService.applyDesktopDownloadLimits(httpServer);
    final serverStart = await ServerInitializationService.startListeningServer(
      httpServer: httpServer,
      stateService: stateService,
      advertisedIp: advertisedIp,
      tailscaleIp: tailscaleIp,
      lanIp: lanIp,
    );

    return DesktopServerLaunchResult(
      advertisedIp: advertisedIp,
      serverStart: serverStart,
    );
  }
}
