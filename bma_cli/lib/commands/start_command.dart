import 'dart:io';
import '../services/daemon_service.dart';
import '../services/cli_state_service.dart';
import '../services/browser_service.dart';
import '../server_runner.dart';

/// Command to start the BMA CLI server
class StartCommand {
  final DaemonService _daemonService = DaemonService();
  final CliStateService _stateService = CliStateService();
  final BrowserService _browserService = BrowserService();

  /// Execute the start command
  Future<void> execute({int port = 8080}) async {
    // Check if already running
    if (await _daemonService.isRunning()) {
      print('BMA CLI server is already running.');
      print('Use "bma_cli status" to check status or "bma_cli stop" to stop it.');
      return;
    }

    // Check if web build exists
    final webBuildPath = Directory('build/web');
    if (!await webBuildPath.exists()) {
      print('ERROR: Web UI not built yet.');
      print('Please build the web UI first:');
      print('  cd bma_cli');
      print('  flutter build web -t lib/web/main.dart');
      print('');
      return;
    }

    // Check if this is first-time setup
    final isSetupComplete = await _stateService.isSetupComplete();

    if (!isSetupComplete) {
      print('Starting BMA CLI server for first-time setup...');
      print('Opening web browser for setup at http://localhost:$port');
      print('');
      print('Note: The server will run in the foreground during setup.');
      print('After completing setup, you can run the server in the background.');
      print('');

      // Open browser after short delay (in background)
      Future.delayed(const Duration(seconds: 2), () async {
        await _browserService.openBmaInterface(port: port);
      });

      // Run server in foreground (setup mode)
      final runner = ServerRunner();
      await runner.run(port: port, isSetupMode: true);
    } else {
      print('Starting BMA CLI server in background...');
      print('');

      // Get the current executable path
      final executable = Platform.resolvedExecutable;

      // Start server in background with --server-mode flag
      final pid = await _daemonService.startServerInBackground([
        executable,
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

      print('✓ BMA CLI server started successfully!');
      print('');
      print('Server details:');
      print('  PID: $pid');
      print('  Port: $port');
      print('  URL: http://localhost:$port');
      print('');
      print('Use "bma_cli status" to check server status');
      print('Use "bma_cli stop" to stop the server');
      print('');
    }
  }
}
