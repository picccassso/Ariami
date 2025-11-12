import 'dart:async';

class ConnectedClient {
  final String deviceId;
  final String deviceName;
  final String sessionId;
  final String platform;
  final DateTime connectedAt;
  DateTime lastHeartbeat;

  ConnectedClient({
    required this.deviceId,
    required this.deviceName,
    required this.sessionId,
    required this.platform,
    required this.connectedAt,
    required this.lastHeartbeat,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'sessionId': sessionId,
      'platform': platform,
      'connectedAt': connectedAt.toIso8601String(),
      'lastHeartbeat': lastHeartbeat.toIso8601String(),
    };
  }
}

class ConnectionManager {
  final Map<String, ConnectedClient> _clients = {};
  Timer? _cleanupTimer;

  ConnectionManager() {
    _startCleanupTimer();
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanupInactiveClients();
    });
  }

  void _cleanupInactiveClients() {
    final now = DateTime.now();
    final timeout = const Duration(minutes: 5);

    _clients.removeWhere((sessionId, client) {
      final inactive = now.difference(client.lastHeartbeat) > timeout;
      if (inactive) {
        print('Removing inactive client: ${client.deviceName} (${client.sessionId})');
      }
      return inactive;
    });
  }

  String addClient({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    final sessionId = _generateSessionId();
    final now = DateTime.now();

    final client = ConnectedClient(
      deviceId: deviceId,
      deviceName: deviceName,
      sessionId: sessionId,
      platform: platform,
      connectedAt: now,
      lastHeartbeat: now,
    );

    _clients[sessionId] = client;
    print('Client connected: $deviceName ($sessionId) - Total clients: ${_clients.length}');
    return sessionId;
  }

  bool removeClient(String sessionId) {
    final client = _clients.remove(sessionId);
    if (client != null) {
      print('Client disconnected: ${client.deviceName} ($sessionId) - Total clients: ${_clients.length}');
      return true;
    }
    return false;
  }

  bool updateHeartbeat(String sessionId) {
    final client = _clients[sessionId];
    if (client != null) {
      client.lastHeartbeat = DateTime.now();
      return true;
    }
    return false;
  }

  ConnectedClient? getClient(String sessionId) {
    return _clients[sessionId];
  }

  bool isValidSession(String sessionId) {
    return _clients.containsKey(sessionId);
  }

  List<ConnectedClient> getAllClients() {
    return _clients.values.toList();
  }

  int get clientCount => _clients.length;

  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    return 'session_${timestamp}_$random';
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _clients.clear();
  }
}
