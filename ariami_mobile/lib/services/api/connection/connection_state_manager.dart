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
  // Private state
  bool _isConnected = false;
  bool _isManuallyDisconnected = false;
  ServerInfo? _serverInfo;
  String? _lastRestoreFailureCode;
  String? _lastRestoreFailureMessage;
  Map<String, dynamic>? _lastRestoreFailureDetails;

  // Stream controllers for state broadcasts
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<ServerInfo?> _serverInfoController =
      StreamController<ServerInfo?>.broadcast();

  /// Whether currently connected to the server
  bool get isConnected => _isConnected;

  /// Whether the user manually disconnected (manual offline mode)
  bool get isManuallyDisconnected => _isManuallyDisconnected;

  /// Current server information
  ServerInfo? get serverInfo => _serverInfo;

  /// Whether we have server info (even if not currently connected)
  bool get hasServerInfo => _serverInfo != null;

  /// Most recent reconnect failure code from restore attempts, if any
  String? get lastRestoreFailureCode => _lastRestoreFailureCode;

  /// Most recent reconnect failure message from restore attempts, if any
  String? get lastRestoreFailureMessage => _lastRestoreFailureMessage;

  /// Most recent reconnect failure details from restore attempts, if any
  Map<String, dynamic>? get lastRestoreFailureDetails =>
      _lastRestoreFailureDetails;

  /// Whether the last restore failed due to authentication issues
  bool get didLastRestoreFailForAuth {
    const authRequiredCode = 'AUTH_REQUIRED';
    const sessionExpiredCode = 'SESSION_EXPIRED';
    return _lastRestoreFailureCode == authRequiredCode ||
        _lastRestoreFailureCode == sessionExpiredCode;
  }

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Stream of server info changes, including endpoint switches
  Stream<ServerInfo?> get serverInfoStream => _serverInfoController.stream;

  /// Set the connected state and broadcast the change
  void setConnected(bool value) {
    if (_isConnected != value) {
      _isConnected = value;
      _connectionStateController.add(value);
    }
  }

  /// Set the manual disconnect state
  void setManuallyDisconnected(bool value) {
    _isManuallyDisconnected = value;
  }

  /// Set the server info and broadcast the change
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

  /// Record a restore failure with details
  void setRestoreFailure({
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    _lastRestoreFailureCode = code;
    _lastRestoreFailureMessage = message;
    _lastRestoreFailureDetails = details;
  }

  /// Clear any recorded restore failure
  void clearRestoreFailure() {
    _lastRestoreFailureCode = null;
    _lastRestoreFailureMessage = null;
    _lastRestoreFailureDetails = null;
  }

  /// Reset all connection state (used on disconnect)
  void resetConnectionState() {
    _isConnected = false;
    _isManuallyDisconnected = false;
    // Note: We don't clear serverInfo here - it's kept for reconnection
  }

  /// Dispose resources
  void dispose() {
    _connectionStateController.close();
    _serverInfoController.close();
  }
}
