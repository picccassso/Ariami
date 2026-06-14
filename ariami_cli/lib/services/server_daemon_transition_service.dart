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
    try {
      await _httpServer.stop();

      final pid = await _daemonService.startServerInBackground([
        '--server-mode',
        '--port',
        serverPort.toString(),
      ]);

      if (pid == null) {
        print('ERROR: Failed to start Ariami in the background.');
        await _lifecycleService.cancelSignalHandlers();
        exit(1);
      }

      await _daemonService.saveServerState({
        'port': serverPort,
        'pid': pid,
        'started_at': DateTime.now().toIso8601String(),
      });

      stdout.writeln('');
      stdout.writeln('Setup complete. Ariami is running in the background.');
      stdout.writeln('You can safely close this terminal window.');
      stdout.writeln('');
      stdout.writeln('Useful commands:');
      stdout.writeln('  ./ariami_cli status');
      stdout.writeln('  ./ariami_cli stop');
      stdout.writeln('');

      await _lifecycleService.cancelSignalHandlers();
      exit(0);
    } catch (e) {
      print('ERROR: Failed to move Ariami into the background: $e');
      await _lifecycleService.cancelSignalHandlers();
      exit(1);
    }
  }
}
