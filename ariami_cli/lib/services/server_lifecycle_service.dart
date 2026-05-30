import 'dart:async';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

/// Handles process signals and graceful HTTP server shutdown.
class ServerLifecycleService {
  ServerLifecycleService({required AriamiHttpServer httpServer})
      : _httpServer = httpServer;

  final AriamiHttpServer _httpServer;
  final Completer<void> _shutdownCompleter = Completer<void>();

  bool _isShuttingDown = false;
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  StreamSubscription<ProcessSignal>? _sigintSubscription;

  void setupSignalHandlers() {
    _sigtermSubscription = ProcessSignal.sigterm.watch().listen((signal) {
      print('');
      print('Received SIGTERM signal, shutting down gracefully...');
      _triggerShutdown();
    });

    _sigintSubscription = ProcessSignal.sigint.watch().listen((signal) {
      print('');
      print('Received SIGINT signal (Ctrl+C), shutting down gracefully...');
      _triggerShutdown();
    });
  }

  Future<void> cancelSignalHandlers() async {
    await _sigtermSubscription?.cancel();
    await _sigintSubscription?.cancel();
    _sigtermSubscription = null;
    _sigintSubscription = null;
  }

  Future<void> waitForShutdown() async {
    await _shutdownCompleter.future;
  }

  Future<void> shutdown() async {
    if (_isShuttingDown) {
      return;
    }

    _isShuttingDown = true;
    print('');
    print('Shutting down Ariami server...');

    try {
      print('Stopping HTTP server...');
      await _httpServer.stop();
      print('✓ HTTP server stopped');
      print('✓ Server shutdown complete');
      print('');
    } catch (e) {
      print('Warning: Error during shutdown: $e');
    }
  }

  void _triggerShutdown() {
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
  }
}
