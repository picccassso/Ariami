import 'dart:async';
import '../api_client.dart';
import 'connection_state_manager.dart';

/// Manages the connection heartbeat mechanism.
///
/// Handles:
/// - Periodic heartbeat pings to the server
/// - Consecutive failure tracking
/// - Auto-reconnect attempts in auto-offline mode
/// - Connection loss detection
class HeartbeatManager {
  static const int _maxFailures = 3; // Retry 3 times before going offline
  static const Duration _defaultInterval = Duration(seconds: 30);

  final ConnectionStateManager _stateManager;
  final Future<ApiClient?> Function() _apiClientProvider;
  final Future<String> Function() _deviceIdProvider;
  final Future<bool> Function() _isManualOfflineProvider;
  final Future<bool> Function() _tryRestoreConnection;
  final Future<void> Function() _onConnectionLoss;

  Timer? _heartbeatTimer;
  int _consecutiveFailures = 0;

  HeartbeatManager({
    required ConnectionStateManager stateManager,
    required Future<ApiClient?> Function() apiClientProvider,
    required Future<String> Function() deviceIdProvider,
    required Future<bool> Function() isManualOfflineProvider,
    required Future<bool> Function() tryRestoreConnection,
    required Future<void> Function() onConnectionLoss,
  })  : _stateManager = stateManager,
        _apiClientProvider = apiClientProvider,
        _deviceIdProvider = deviceIdProvider,
        _isManualOfflineProvider = isManualOfflineProvider,
        _tryRestoreConnection = tryRestoreConnection,
        _onConnectionLoss = onConnectionLoss;

  bool get isRunning => _heartbeatTimer != null && _heartbeatTimer!.isActive;

  int get consecutiveFailures => _consecutiveFailures;

  void start() {
    stop();
    _heartbeatTimer = Timer.periodic(_defaultInterval, (_) => _sendHeartbeat());
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void resetFailureCount() {
    _consecutiveFailures = 0;
  }

  Future<void> _sendHeartbeat() async {
    if (_stateManager.isManuallyDisconnected) return;

    if (await _isManualOfflineProvider()) {
      return;
    }

    // Check if we're in auto offline mode (disconnected but should auto-reconnect)
    if (!_stateManager.isConnected) {
      await _handleAutoReconnect();
      return;
    }

    final apiClient = await _apiClientProvider();
    if (apiClient == null) return;

    try {
      final deviceId = await _deviceIdProvider();
      await apiClient.ping(deviceId: deviceId);

      if (_consecutiveFailures > 0) {
        _consecutiveFailures = 0;
      }
    } catch (e) {
      _consecutiveFailures++;

      if (_consecutiveFailures >= _maxFailures) {
        _consecutiveFailures = 0; // Reset for next time
        await _onConnectionLoss();
      }
    }
  }

  Future<void> _handleAutoReconnect() async {
    final restored = await _tryRestoreConnection();
    if (restored) {
    }
  }

  void dispose() {
    stop();
  }
}
