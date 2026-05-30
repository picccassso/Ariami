import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

import 'daemon_service.dart';
import 'server_lifecycle_service.dart';

/// Transitions the foreground setup server into the background daemon.
class ServerDaemonTransitionService {
  ServerDaemonTransitionService({
    required AriamiHttpServer httpServer,
    required DaemonService daemonService,
    required ServerLifecycleService lifecycleService,
  })  : _httpServer = httpServer,
        _daemonService = daemonService,
        _lifecycleService = lifecycleService;

  final AriamiHttpServer _httpServer;
  final DaemonService _daemonService;
  final ServerLifecycleService _lifecycleService;

  Future<Map<String, dynamic>> transitionToBackground({
    required int serverPort,
  }) async {
    print('[ServerRunner] Transitioning to background mode...');

    try {
      print('[ServerRunner] Stopping HTTP server to release port...');
      await _httpServer.stop();
      print('[ServerRunner] Port released');

      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        serverPort.toString(),
      ]);

      if (pid == null) {
        print('[ServerRunner] ERROR: Failed to spawn background process');
        await _lifecycleService.cancelSignalHandlers();
        exit(1);
      }

      await _daemonService.saveServerState({
        'port': serverPort,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      print('[ServerRunner] Background process spawned with PID: $pid');
      print('');
      print('═══════════════════════════════════════════════════════');
      print('  Setup complete! Server is now running in background.');
      print('');
      print('  You can safely close this terminal window.');
      print('');
      print('  To check status:  ./ariami_cli status');
      print('  To stop server:   ./ariami_cli stop');
      print('═══════════════════════════════════════════════════════');
      print('');

      await _lifecycleService.cancelSignalHandlers();
      exit(0);
    } catch (e) {
      print('[ServerRunner] Transition error: $e');
      await _lifecycleService.cancelSignalHandlers();
      exit(1);
    }
  }
}
