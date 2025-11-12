import 'http_server.dart';

/// Singleton server manager to ensure only one server instance
class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  HttpServer? _server;
  bool _isRunning = false;

  HttpServer get server {
    _server ??= HttpServer();
    return _server!;
  }

  bool get isRunning => _isRunning;

  Future<bool> startServer() async {
    if (_isRunning) {
      print('Server already running');
      return true;
    }

    final success = await server.start();
    if (success) {
      _isRunning = true;
    }
    return success;
  }

  Future<void> stopServer() async {
    if (!_isRunning) {
      print('Server not running');
      return;
    }

    await server.stop();
    _isRunning = false;
  }

  String? get tailscaleIp => _isRunning ? server.tailscaleIp : null;
  int? get port => _isRunning ? server.port : null;
}
