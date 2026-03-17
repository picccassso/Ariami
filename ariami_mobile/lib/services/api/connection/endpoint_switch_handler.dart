import 'dart:async';
import '../../../models/server_info.dart';
import '../endpoint_resolver.dart';

/// Handles network endpoint switching between LAN and Tailscale.
///
/// Responsibilities:
/// - Monitor endpoint changes
/// - Handle endpoint switch requests
/// - Coordinate restoration after failed switches
class EndpointSwitchHandler {
  final EndpointResolver _endpointResolver;
  final Future<bool> Function(ServerInfo) _isServerReachable;
  final Future<void> Function(ServerInfo) _onSwitchEndpoint;
  final Future<void> Function(ServerInfo) _onRestoreAfterFailedSwitch;

  StreamSubscription<String>? _endpointSubscription;
  bool _isSwitchingEndpoint = false;

  /// Creates an EndpointSwitchHandler.
  EndpointSwitchHandler({
    EndpointResolver? endpointResolver,
    required Future<bool> Function(ServerInfo) isServerReachable,
    required Future<void> Function(ServerInfo) onSwitchEndpoint,
    required Future<void> Function(ServerInfo) onRestoreAfterFailedSwitch,
  })  : _endpointResolver = endpointResolver ?? EndpointResolver(),
        _isServerReachable = isServerReachable,
        _onSwitchEndpoint = onSwitchEndpoint,
        _onRestoreAfterFailedSwitch = onRestoreAfterFailedSwitch;

  /// Whether an endpoint switch is currently in progress
  bool get isSwitchingEndpoint => _isSwitchingEndpoint;

  /// Configure and start endpoint monitoring
  void configureMonitoring(ServerInfo serverInfo) {
    final primaryIp = serverInfo.tailscaleServer ?? serverInfo.server;
    _endpointSubscription?.cancel();
    _endpointResolver.configure(
      primaryIp: primaryIp,
      lanIp: serverInfo.lanServer,
      port: serverInfo.port,
      activeIp: serverInfo.server,
    );
    _endpointSubscription = _endpointResolver.endpointChangedStream.listen(
      (newIp) => _handleEndpointSwitch(newIp, serverInfo),
    );
    _endpointResolver.startMonitoring();
  }

  /// Stop endpoint monitoring
  void stopMonitoring() {
    _endpointSubscription?.cancel();
    _endpointSubscription = null;
    _endpointResolver.stopMonitoring();
  }

  /// Handle a request to switch to a new endpoint
  Future<void> _handleEndpointSwitch(
      String newIp, ServerInfo currentServerInfo) async {
    if (_isSwitchingEndpoint || currentServerInfo.server == newIp) {
      return;
    }

    _isSwitchingEndpoint = true;
    final nextServerInfo = currentServerInfo.withServer(newIp);

    try {
      // Verify the new endpoint is reachable
      final isReachable = await _isServerReachable(
        nextServerInfo,
      );
      if (!isReachable) {
        return;
      }

      // Perform the switch
      await _onSwitchEndpoint(nextServerInfo);
    } catch (e) {
      // Restore to previous endpoint
      await _onRestoreAfterFailedSwitch(currentServerInfo);
    } finally {
      _isSwitchingEndpoint = false;
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
  }
}
