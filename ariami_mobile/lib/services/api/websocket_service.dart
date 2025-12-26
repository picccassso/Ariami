import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/websocket_models.dart';
import '../../models/server_info.dart';
import '../offline/offline_playback_service.dart';

/// WebSocket service for real-time updates
class WebSocketService {
  // Use lazy getter to avoid circular dependency during construction
  OfflinePlaybackService get _offlineService => OfflinePlaybackService();
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ServerInfo? _serverInfo;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  /// Callback for when WebSocket reconnects after being disconnected
  /// Used to notify ConnectionService to restore full connection
  void Function()? onReconnected;

  /// Callback for when WebSocket disconnects
  /// Used to notify ConnectionService immediately
  void Function()? onDisconnected;

  /// Stream controller for incoming messages
  final StreamController<WsMessage> _messageController =
      StreamController<WsMessage>.broadcast();

  /// Stream of incoming WebSocket messages
  Stream<WsMessage> get messages => _messageController.stream;

  /// Check if WebSocket is connected
  bool get isConnected => _isConnected;

  // ============================================================================
  // CONNECTION MANAGEMENT
  // ============================================================================

  /// Connect to WebSocket server
  Future<void> connect(ServerInfo serverInfo) async {
    if (_isConnected) {
      print('WebSocket already connected');
      return;
    }

    _serverInfo = serverInfo;

    try {
      final wsUrl = Uri.parse('${serverInfo.wsUrl}/api/ws');
      print('Connecting to WebSocket: $wsUrl');

      _channel = WebSocketChannel.connect(wsUrl);

      // Listen to messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _startPingTimer();

      print('WebSocket connected');
    } catch (e) {
      print('WebSocket connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    print('Disconnecting WebSocket');

    _stopPingTimer();
    _stopReconnectTimer();

    _subscription?.cancel();
    _subscription = null;

    _channel?.sink.close();
    _channel = null;

    _isConnected = false;
    _serverInfo = null;
  }

  // ============================================================================
  // MESSAGE HANDLING
  // ============================================================================

  /// Handle incoming message
  void _handleMessage(dynamic rawMessage) {
    try {
      final jsonMessage = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final message = WsMessage.fromJson(jsonMessage);

      print('WebSocket received: ${message.type}');

      // Handle pong
      if (message.type == WsMessageType.pong) {
        // Pong received, connection is alive
        return;
      }

      // Emit message to stream
      _messageController.add(message);
    } catch (e) {
      print('Error parsing WebSocket message: $e');
    }
  }

  /// Handle WebSocket error
  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    
    // Only skip reconnect if in MANUAL offline mode
    // Auto offline should still attempt reconnection
    if (!_offlineService.isManualOfflineModeEnabled) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    print('WebSocket disconnected');
    _isConnected = false;

    // Notify ConnectionService immediately (which will enable offline mode)
    if (onDisconnected != null) {
      onDisconnected!();
    }

    // Schedule reconnect for auto-offline mode (manual offline won't reconnect)
    _scheduleReconnect();
  }

  // ============================================================================
  // SENDING MESSAGES
  // ============================================================================

  /// Send message to server
  void sendMessage(WsMessage message) {
    if (!_isConnected || _channel == null) {
      print('Cannot send message: WebSocket not connected');
      return;
    }

    try {
      final jsonString = jsonEncode(message.toJson());
      _channel!.sink.add(jsonString);
    } catch (e) {
      print('Error sending WebSocket message: $e');
    }
  }

  /// Send ping to server
  void _sendPing() {
    sendMessage(PingMessage());
  }

  // ============================================================================
  // PING/PONG MECHANISM
  // ============================================================================

  /// Start ping timer
  void _startPingTimer() {
    _stopPingTimer();

    _pingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendPing(),
    );
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ============================================================================
  // RECONNECTION
  // ============================================================================

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_serverInfo == null) return;
    
    // Don't reconnect if MANUAL offline mode is enabled
    // Auto offline should still attempt reconnection
    if (_offlineService.isManualOfflineModeEnabled) {
      print('Manual offline mode enabled - skipping WebSocket reconnect');
      return;
    }

    _stopReconnectTimer();

    print('Scheduling WebSocket reconnect in 5 seconds...');

    _reconnectTimer = Timer(
      const Duration(seconds: 5),
      () => _attemptReconnect(),
    );
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (_serverInfo == null) return;
    
    // Check again in case MANUAL offline mode was enabled while waiting
    // Auto offline should still attempt reconnection
    if (_offlineService.isManualOfflineModeEnabled) {
      print('Manual offline mode enabled - aborting WebSocket reconnect');
      return;
    }

    print('Attempting WebSocket reconnect...');

    final wasConnected = _isConnected;
    await connect(_serverInfo!);

    // If we successfully reconnected, notify ConnectionService
    if (_isConnected && !wasConnected && onReconnected != null) {
      print('WebSocket reconnected - notifying ConnectionService');
      onReconnected!();
    }
  }

  /// Stop reconnect timer
  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
