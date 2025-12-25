import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:bma_core/models/websocket_models.dart';

/// WebSocket service for web dashboard real-time updates
class WebWebSocketService {
  html.WebSocket? _socket;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();

  /// Stream of incoming WebSocket messages
  Stream<WsMessage> get messages => _messageController.stream;

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  void connect() {
    if (_isConnected) return;

    try {
      // Use relative URL - same origin as web app
      final wsUrl = 'ws://${html.window.location.host}/api/ws';
      print('[WebWS] Connecting to: $wsUrl');

      _socket = html.WebSocket(wsUrl);

      _socket!.onOpen.listen((_) {
        print('[WebWS] Connected');
        _isConnected = true;
        _reconnectTimer?.cancel();
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
        _handleDisconnect();
      });

      _socket!.onClose.listen((_) {
        print('[WebWS] Closed');
        _handleDisconnect();
      });
    } catch (e) {
      print('[WebWS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Handle disconnect
  void _handleDisconnect() {
    _isConnected = false;
    _socket = null;
    _scheduleReconnect();
  }

  /// Schedule reconnection
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    print('[WebWS] Reconnecting in 1 second...');

    _reconnectTimer = Timer(
      const Duration(seconds: 1),
      () => connect(),
    );
  }

  /// Disconnect from WebSocket
  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isConnected = false;
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
