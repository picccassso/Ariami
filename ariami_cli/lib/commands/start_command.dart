import 'dart:io';
import '../services/daemon_service.dart';
import '../services/cli_state_service.dart';
import '../services/browser_service.dart';
import '../services/cli_tailscale_service.dart';
import '../services/web_assets_resolver.dart';
import '../server_runner.dart';

/// Command to start the Ariami CLI server
class StartCommand {
  final DaemonService _daemonService = DaemonService();
  final CliStateService _stateService = CliStateService();
  final BrowserService _browserService = BrowserService();
  final WebAssetsResolver _webAssetsResolver = WebAssetsResolver();
  final CliTailscaleService _tailscaleService = CliTailscaleService();

  /// Execute the start command
  Future<void> execute({int port = 8080}) async {
    // Check if already running
    if (await _daemonService.isRunning()) {
      print('Ariami CLI server is already running.');
      print('Use "ariami_cli status" to check status or "ariami_cli stop" to stop it.');
      return;
    }

    final webAssets = await _webAssetsResolver.resolve();
    if (!webAssets.found) {
      _webAssetsResolver.printNotFoundError(webAssets);
      return;
    }

    // Check if this is first-time setup
    final isSetupComplete = await _stateService.isSetupComplete();

    if (!isSetupComplete) {
      print('Starting Ariami CLI server for first-time setup...');
      print('Opening web browser for setup at http://localhost:$port');
      print('');
      print('Note: The server will run in the foreground during setup.');
      print('After completing setup, you can run the server in the background.');
      print('');

      // Open browser after short delay (in background)
      Future.delayed(const Duration(seconds: 2), () async {
        final opened = await _browserService.openAriamiInterface(port: port);
        if (!opened) {
          await _printBrowserOpenFailureUrls(port);
        }
      });

      // Run server in foreground (setup mode)
      final runner = ServerRunner();
      await runner.run(port: port, isSetupMode: true);
    } else {
      print('Starting Ariami CLI server in background...');
      print('');

      // Start server in background with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port', port.toString(),
      ]);

      if (pid == null) {
        print('ERROR: Failed to start server in background.');
        print('Check logs for details.');
        exit(1);
      }

      // Save server state
      await _daemonService.saveServerState({
        'port': port,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('✓ Ariami CLI server started successfully!');
      print('');
      print('Server details:');
      print('  PID: $pid');
      print('  Port: $port');
      print('  URL: http://localhost:$port');
      print('');
      print('Use "ariami_cli status" to check server status');
      print('Use "ariami_cli stop" to stop the server');
      print('');
    }
  }

  Future<void> _printBrowserOpenFailureUrls(int port) async {
    print('Could not open a browser automatically.');
    print('Open this from your machine: http://localhost:$port');

    final lanIp = await _tailscaleService.getLanIp();
    if (lanIp != null) {
      print('Local network: http://$lanIp:$port');
    }

    final tailscaleIp = await _tailscaleService.getTailscaleIp();
    if (tailscaleIp != null) {
      print('Tailscale: http://$tailscaleIp:$port');
    }

    print('');
  }
}
