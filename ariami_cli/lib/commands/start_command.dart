import 'dart:async';
import 'dart:io';
import '../services/daemon_service.dart';
import '../services/cli_state_service.dart';
import '../services/browser_service.dart';
import '../services/cli_tailscale_service.dart';
import '../services/web_assets_resolver.dart';
import '../services/autostart_service.dart';
import '../server_runner.dart';

/// Command to start the Ariami CLI server
class StartCommand {
  final DaemonService _daemonService = DaemonService();
  final CliStateService _stateService = CliStateService();
  final BrowserService _browserService = BrowserService();
  final WebAssetsResolver _webAssetsResolver = WebAssetsResolver();
  final CliTailscaleService _tailscaleService = CliTailscaleService();
  final AutostartService _autostartService = AutostartService();

  /// Execute the start command
  Future<void> execute({
    int port = 8080,
    bool portExplicitlyRequested = false,
  }) async {
    // Check if already running
    if (await _daemonService.isRunning()) {
      print('Ariami CLI server is already running.');
      print(
        'Use "ariami_cli status" to check status or "ariami_cli stop" to stop it.',
      );
      return;
    }

    final webAssets = await _webAssetsResolver.resolve();
    if (!webAssets.found) {
      _webAssetsResolver.printNotFoundError(webAssets);
      return;
    }

    // Check if this is first-time setup
    final isSetupComplete = await _stateService.isSetupComplete();
    final savedPort = await _stateService.getServerPort();
    final preferredPort = portExplicitlyRequested ? port : (savedPort ?? port);
    final allowPortFallback = !portExplicitlyRequested;

    if (!isSetupComplete) {
      // Ask about starting on boot before anything else launches.
      await _promptAndConfigureAutostart();

      _writeSetupLine('Starting Ariami setup...');
      _writeSetupLine('');

      // Run server in foreground (setup mode)
      final runner = ServerRunner();
      await runZoned(
        () => runner.run(
          port: preferredPort,
          isSetupMode: true,
          allowPortFallback: allowPortFallback,
          onHttpServerReady: _openSetupBrowser,
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            if (_shouldShowQuietSetupLog(line)) {
              parent.print(zone, line);
            }
          },
        ),
      );
    } else {
      print('Starting Ariami CLI server in background...');
      print('');

      final daemonPort = savedPort ?? preferredPort;

      // Start server in background with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        daemonPort.toString(),
      ]);

      if (pid == null) {
        print('ERROR: Failed to start server in background.');
        print('Check logs for details.');
        exit(1);
      }

      // Save server state
      await _daemonService.saveServerState({
        'port': daemonPort,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('✓ Ariami CLI server started successfully!');
      print('');
      print('Server details:');
      print('  PID: $pid');
      print('  Port: $daemonPort');
      print('  URL: http://localhost:$daemonPort');
      print('');
      print('Use "ariami_cli status" to check server status');
      print('Use "ariami_cli stop" to stop the server');
      print('');
    }
  }

  /// Ask the user whether Ariami should start automatically on boot, and apply
  /// their choice. Runs before the setup server/browser launches.
  Future<void> _promptAndConfigureAutostart() async {
    if (!_autostartService.isSupported) {
      return;
    }

    stdout.write(
      'Start Ariami automatically on boot (after restart, etc.)? [y/N]: ',
    );
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    final wantsAutostart = answer == 'y' || answer == 'yes';

    if (wantsAutostart) {
      final ok = await _autostartService.enable();
      _writeSetupLine(
        ok
            ? '✓ Ariami will start automatically on boot.'
            : 'Could not configure start-on-boot. Continuing setup.',
      );
    } else {
      // Make sure any previous autostart entry is removed.
      await _autostartService.disable();
      _writeSetupLine('Ariami will not start automatically on boot.');
    }
    _writeSetupLine('');
  }

  Future<void> _openSetupBrowser(int port) async {
    await _printSetupReadyUrls(port);

    final opened = await _browserService.openAriamiInterface(port: port);
    if (!opened) {
      _writeSetupLine('');
      _writeSetupLine('Your browser did not open automatically.');
      _writeSetupLine('Open one of the addresses above to continue setup.');
    }
  }

  Future<void> _printSetupReadyUrls(int port) async {
    final lanIp = await _tailscaleService.getLanIp();
    final tailscaleIp = await _tailscaleService.getTailscaleIp();

    _writeSetupLine('Ariami setup is ready.');
    _writeSetupLine('');
    _writeSetupLine('Open setup:');
    _writeSetupLine('  This machine:  http://localhost:$port');

    if (lanIp != null) {
      _writeSetupLine('  Same network:  http://$lanIp:$port');
    }

    if (tailscaleIp != null) {
      _writeSetupLine('  Tailscale:     http://$tailscaleIp:$port');
      _writeSetupLine('');
      _writeSetupLine(
        'Use the Tailscale address from devices signed into Tailscale.',
      );
    } else {
      _writeSetupLine('');
      _writeSetupLine(
        'No Tailscale address was detected. You can enable it later for remote access.',
      );
    }

    _writeSetupLine('Keep this terminal open until setup finishes.');
    _writeSetupLine('');
  }

  bool _shouldShowQuietSetupLog(String line) {
    return line.startsWith('ERROR:') ||
        line.startsWith('Error:') ||
        line.startsWith('Failed to start server:') ||
        line.startsWith('Warning: Error during shutdown:');
  }

  void _writeSetupLine(String line) {
    stdout.writeln(line);
  }
}
