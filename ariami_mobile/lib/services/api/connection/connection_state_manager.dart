import 'dart:async';
import '../../../models/server_info.dart';

/// Manages the core connection state and broadcasts state changes.
///
/// This is the single source of truth for:
/// - Connection status (connected/disconnected)
/// - Manual disconnect state
/// - Server info
/// - Restore failure tracking
class ConnectionStateManager {
  bool _isConnected = false;
  bool _isManuallyDisconnected = false;
  ServerInfo? _serverInfo;
  String? _lastRestoreFailureCode;
  String? _lastRestoreFailureMessage;
  Map<String, dynamic>? _lastRestoreFailureDetails;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<ServerInfo?> _serverInfoController =
      StreamController<ServerInfo?>.broadcast();

  bool get isConnected => _isConnected;

  /// Whether the user manually disconnected (manual offline mode)
  bool get isManuallyDisconnected => _isManuallyDisconnected;

  ServerInfo? get serverInfo => _serverInfo;

  bool get hasServerInfo => _serverInfo != null;

  String? get lastRestoreFailureCode => _lastRestoreFailureCode;

  String? get lastRestoreFailureMessage => _lastRestoreFailureMessage;

  Map<String, dynamic>? get lastRestoreFailureDetails =>
      _lastRestoreFailureDetails;

  bool get didLastRestoreFailForAuth {
    const authRequiredCode = 'AUTH_REQUIRED';
    const sessionExpiredCode = 'SESSION_EXPIRED';
    return _lastRestoreFailureCode == authRequiredCode ||
        _lastRestoreFailureCode == sessionExpiredCode;
  }

  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  Stream<ServerInfo?> get serverInfoStream => _serverInfoController.stream;

  void setConnected(bool value) {
    if (_isConnected != value) {
      _isConnected = value;
      _connectionStateController.add(value);
    }
  }

  void setManuallyDisconnected(bool value) {
    _isManuallyDisconnected = value;
  }

  void setServerInfo(ServerInfo? serverInfo) {
    _serverInfo = serverInfo;
    _serverInfoController.add(serverInfo);
  }

  /// Update the server IP without broadcasting (used during endpoint switches)
  void updateServerIp(String newIp) {
    final current = _serverInfo;
    if (current != null && current.server != newIp) {
      _serverInfo = current.withServer(newIp);
    }
  }

  void setRestoreFailure({
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    _lastRestoreFailureCode = code;
    _lastRestoreFailureMessage = message;
    _lastRestoreFailureDetails = details;
  }

  void clearRestoreFailure() {
    _lastRestoreFailureCode = null;
    _lastRestoreFailureMessage = null;
    _lastRestoreFailureDetails = null;
  }

  void resetConnectionState() {
    _isConnected = false;
    _isManuallyDisconnected = false;
    // Note: We don't clear serverInfo here - it's kept for reconnection
  }

  void dispose() {
    _connectionStateController.close();
    _serverInfoController.close();
  }
}
