class ConnectionManager {
  final Map<String, ConnectedClient> _clients = {};
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    // A listener may detach itself while handling the notification (for
    // example when server shutdown disposes its screen). Use a snapshot to
    // keep that lifecycle change from invalidating this iteration.
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void registerClient(
    String deviceId,
    String deviceName, {
    String? userId,
    String? clientType,
  }) {
    _clients[deviceId] = ConnectedClient(
      deviceId: deviceId,
      deviceName: deviceName,
      userId: userId,
      clientType: clientType,
      connectedAt: DateTime.now(),
      lastHeartbeat: DateTime.now(),
    );
    print('Client connected: $deviceName ($deviceId)');
    _notifyListeners();
  }

  /// Update heartbeat only when client is already registered.
  /// Returns true when an existing client was updated.
  bool refreshHeartbeatIfRegistered(
    String deviceId, {
    String? userId,
    String? deviceName,

    /// When non-null, replaces [ConnectedClient.clientType] (e.g. upgrade to
    /// `dashboard` after WebSocket identify).
    String? replaceClientType,
  }) {
    final client = _clients[deviceId];
    if (client == null) {
      return false;
    }

    _clients[deviceId] = client.copyWith(
      lastHeartbeat: DateTime.now(),
      userId: userId ?? client.userId,
      deviceName: (deviceName != null && deviceName.isNotEmpty)
          ? deviceName
          : client.deviceName,
      clientType: replaceClientType ?? client.clientType,
    );
    return true;
  }

  /// Explicit helper for authenticated connection points:
  /// register unknown clients, refresh known clients.
  void registerOrRefreshClient(
    String deviceId,
    String deviceName, {
    String? userId,
    String? clientType,
  }) {
    final didRefresh = refreshHeartbeatIfRegistered(
      deviceId,
      userId: userId,
      deviceName: deviceName,
      replaceClientType: clientType,
    );
    if (!didRefresh) {
      registerClient(deviceId, deviceName,
          userId: userId, clientType: clientType);
    }
  }

  void renameDevice(String deviceId, String deviceName) {
    final client = _clients[deviceId];
    if (client == null || client.deviceName == deviceName) return;
    _clients[deviceId] = client.copyWith(deviceName: deviceName);
    _notifyListeners();
  }

  void unregisterClient(String deviceId) {
    unregisterClientAndGet(deviceId);
  }

  ConnectedClient? unregisterClientAndGet(String deviceId) {
    final client = _clients.remove(deviceId);
    if (client != null) {
      print('Client disconnected: ${client.deviceName} ($deviceId)');
      _notifyListeners();
    }
    return client;
  }

  List<ConnectedClient> getConnectedClients() {
    return _clients.values.toList();
  }

  ConnectedClient? getClient(String deviceId) {
    return _clients[deviceId];
  }

  int get clientCount => _clients.length;

  /// Get count of mobile clients (excludes dashboard clients)
  int get mobileClientCount {
    return _clients.values
        .where((client) => client.clientType != 'dashboard')
        .length;
  }

  int get uniqueUserCount {
    final uniqueUserIds = _clients.values
        .map((client) => client.userId)
        .whereType<String>()
        .toSet();
    return uniqueUserIds.length;
  }

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

class ConnectedClient {
  final String deviceId;
  final String deviceName;
  final String? userId;
  final String? clientType;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;

  ConnectedClient({
    required this.deviceId,
    required this.deviceName,
    required this.userId,
    this.clientType,
    required this.connectedAt,
    required this.lastHeartbeat,
  });

  ConnectedClient copyWith({
    String? deviceId,
    String? deviceName,
    String? userId,
    String? clientType,
    DateTime? connectedAt,
    DateTime? lastHeartbeat,
  }) {
    return ConnectedClient(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      userId: userId ?? this.userId,
      clientType: clientType ?? this.clientType,
      connectedAt: connectedAt ?? this.connectedAt,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (userId != null) 'userId': userId,
      if (clientType != null) 'clientType': clientType,
      'connectedAt': connectedAt.toIso8601String(),
      'lastHeartbeat': lastHeartbeat.toIso8601String(),
    };
  }
}
