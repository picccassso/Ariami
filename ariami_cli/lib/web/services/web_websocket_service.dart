import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:ariami_core/models/websocket_models.dart';

/// WebSocket service for web dashboard real-time updates
class WebWebSocketService {
  html.WebSocket? _socket;
  bool _isConnected = false;
  bool _hasAuthFailure = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();

  /// Stream of incoming WebSocket messages
  Stream<WsMessage> get messages => _messageController.stream;

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  void connect({
    void Function()? onConnected,
    Future<String> Function()? deviceIdProvider,
    Future<String?> Function()? sessionTokenProvider,
    void Function()? onAuthRequired,
  }) {
    if (_isConnected) return;

    try {
      // Use relative URL - same origin as web app
      final wsUrl = 'ws://${html.window.location.host}/api/ws';
      print('[WebWS] Connecting to: $wsUrl');

      _socket = html.WebSocket(wsUrl);

      _socket!.onOpen.listen((_) async {
        print('[WebWS] Connected');
        _isConnected = true;
        _hasAuthFailure = false;
        _reconnectTimer?.cancel();
        final deviceId = deviceIdProvider != null
            ? await deviceIdProvider()
            : _generateDefaultDeviceId();
        final sessionToken =
            sessionTokenProvider != null ? await sessionTokenProvider() : null;
        final identify = IdentifyMessage(
          deviceId: deviceId,
          deviceName: 'Ariami CLI Web Dashboard',
          sessionToken: sessionToken,
        );
        _socket!.send(jsonEncode(identify.toJson()));
        _startPingTimer();
        onConnected?.call();
      });

      _socket!.onMessage.listen((event) {
        try {
          final message = WsMessage.fromJson(jsonDecode(event.data as String));
          _messageController.add(message);
        } catch (e) {
          print('[WebWS] Error parsing message: $e');
        }
      });

      _socket!.onError.listen((event) {
        print('[WebWS] Error: $event');
        _handleDisconnect(
          onConnected: onConnected,
          deviceIdProvider: deviceIdProvider,
          sessionTokenProvider: sessionTokenProvider,
          onAuthRequired: onAuthRequired,
        );
      });

      _socket!.onClose.listen((event) {
        final closeEvent = event;
        final isAuthFailure = closeEvent.code == 4001;
        print('[WebWS] Closed (code: ${closeEvent.code})');
        _handleDisconnect(
          isAuthFailure: isAuthFailure,
          onAuthRequired: onAuthRequired,
          onConnected: onConnected,
          deviceIdProvider: deviceIdProvider,
          sessionTokenProvider: sessionTokenProvider,
        );
      });
    } catch (e) {
      print('[WebWS] Connection failed: $e');
      _scheduleReconnect(
        onConnected: onConnected,
        deviceIdProvider: deviceIdProvider,
        sessionTokenProvider: sessionTokenProvider,
        onAuthRequired: onAuthRequired,
      );
    }
  }

  /// Handle disconnect
  void _handleDisconnect({
    bool isAuthFailure = false,
    void Function()? onAuthRequired,
    void Function()? onConnected,
    Future<String> Function()? deviceIdProvider,
    Future<String?> Function()? sessionTokenProvider,
  }) {
    _isConnected = false;
    _stopPingTimer();
    _socket = null;

    if (isAuthFailure) {
      _hasAuthFailure = true;
      onAuthRequired?.call();
      return;
    }

    _scheduleReconnect(
      onConnected: onConnected,
      deviceIdProvider: deviceIdProvider,
      sessionTokenProvider: sessionTokenProvider,
      onAuthRequired: onAuthRequired,
    );
  }

  /// Schedule reconnection
  void _scheduleReconnect({
    void Function()? onConnected,
    Future<String> Function()? deviceIdProvider,
    Future<String?> Function()? sessionTokenProvider,
    void Function()? onAuthRequired,
  }) {
    if (_hasAuthFailure) {
      return;
    }

    _reconnectTimer?.cancel();

    print('[WebWS] Reconnecting in 1 second...');

    _reconnectTimer = Timer(
      const Duration(seconds: 1),
      () => connect(
        onConnected: onConnected,
        deviceIdProvider: deviceIdProvider,
        sessionTokenProvider: sessionTokenProvider,
        onAuthRequired: onAuthRequired,
      ),
    );
  }

  /// Disconnect from WebSocket
  void disconnect() {
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _socket?.close();
    _socket = null;
    _isConnected = false;
    _hasAuthFailure = false;
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_isConnected || _socket == null) return;
      if (_socket!.readyState != html.WebSocket.OPEN) return;
      try {
        _socket!.send(jsonEncode(PingMessage().toJson()));
      } catch (e) {
        print('[WebWS] Ping failed: $e');
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  String _generateDefaultDeviceId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return 'cli_web_ws_$ms';
  }
}
