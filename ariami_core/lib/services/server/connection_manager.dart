/// Connection manager for tracking connected clients
class ConnectionManager {
  final Map<String, ConnectedClient> _clients = {};
  final List<void Function()> _listeners = [];

  /// Add a listener for connection changes
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners of changes
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Register a new client connection
  void registerClient(String deviceId, String deviceName) {
    _clients[deviceId] = ConnectedClient(
      deviceId: deviceId,
      deviceName: deviceName,
      connectedAt: DateTime.now(),
      lastHeartbeat: DateTime.now(),
    );
    print('Client connected: $deviceName ($deviceId)');
    _notifyListeners();
  }

  /// Update client heartbeat timestamp
  void updateHeartbeat(String deviceId) {
    final client = _clients[deviceId];
    if (client != null) {
      _clients[deviceId] = client.copyWith(lastHeartbeat: DateTime.now());
    }
  }

  /// Unregister a client connection
  void unregisterClient(String deviceId) {
    final client = _clients.remove(deviceId);
    if (client != null) {
      print('Client disconnected: ${client.deviceName} ($deviceId)');
      _notifyListeners();
    }
  }

  /// Check if a client is connected
  bool isClientConnected(String deviceId) {
    return _clients.containsKey(deviceId);
  }

  /// Get all connected clients
  List<ConnectedClient> getConnectedClients() {
    return _clients.values.toList();
  }

  /// Get client by device ID
  ConnectedClient? getClient(String deviceId) {
    return _clients[deviceId];
  }

  /// Get count of connected clients
  int get clientCount => _clients.length;

  /// Clear all connected clients (used when server stops)
  void clearAll() {
    final hadClients = _clients.isNotEmpty;
    _clients.clear();
    print('All clients cleared from connection manager');
    if (hadClients) {
      _notifyListeners();
    }
  }

  /// Clean up stale connections (no heartbeat for 60 seconds)
  void cleanupStaleConnections() {
    final now = DateTime.now();
    final staleDeviceIds = <String>[];

    for (final entry in _clients.entries) {
      final timeSinceHeartbeat = now.difference(entry.value.lastHeartbeat);
      if (timeSinceHeartbeat.inSeconds > 60) {
        staleDeviceIds.add(entry.key);
      }
    }

    for (final deviceId in staleDeviceIds) {
      unregisterClient(deviceId);
    }
  }
}

/// Connected client data
class ConnectedClient {
  final String deviceId;
  final String deviceName;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;

  ConnectedClient({
    required this.deviceId,
    required this.deviceName,
    required this.connectedAt,
    required this.lastHeartbeat,
  });

  ConnectedClient copyWith({
    String? deviceId,
    String? deviceName,
    DateTime? connectedAt,
    DateTime? lastHeartbeat,
  }) {
    return ConnectedClient(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      connectedAt: connectedAt ?? this.connectedAt,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'connectedAt': connectedAt.toIso8601String(),
      'lastHeartbeat': lastHeartbeat.toIso8601String(),
    };
  }
}
