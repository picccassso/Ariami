import 'dart:async';
import '../../../models/websocket_models.dart';
import '../websocket_service.dart';

/// Handles WebSocket connection events and message processing.
///
/// Responsibilities:
/// - Handle WebSocket reconnect events
/// - Handle WebSocket disconnect events
/// - Process WebSocket messages (sync tokens)
/// - Send identify messages
class WebSocketHandler {
  final WebSocketService _webSocketService;
  final Future<void> Function() _onReconnect;
  final Future<void> Function() _onDisconnect;
  final Future<void> Function(int latestToken) _onSyncTokenAdvanced;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _deviceNameProvider;
  final Future<String?> Function() _sessionTokenProvider;

  /// Creates a WebSocketHandler.
  WebSocketHandler({
    required WebSocketService webSocketService,
    required Future<void> Function() onReconnect,
    required Future<void> Function() onDisconnect,
    required Future<void> Function(int latestToken) onSyncTokenAdvanced,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() deviceNameProvider,
    required Future<String?> Function() sessionTokenProvider,
  })  : _webSocketService = webSocketService,
        _onReconnect = onReconnect,
        _onDisconnect = onDisconnect,
        _onSyncTokenAdvanced = onSyncTokenAdvanced,
        _deviceIdProvider = deviceIdProvider,
        _deviceNameProvider = deviceNameProvider,
        _sessionTokenProvider = sessionTokenProvider;

  /// Get the WebSocket message stream
  Stream<WsMessage> get messages => _webSocketService.messages;

  /// Whether the WebSocket is currently connected
  bool get isConnected => _webSocketService.isConnected;

  /// Connect to the WebSocket server
  Future<void> connect(dynamic serverInfo) async {
    _webSocketService.onReconnected = _handleReconnect;
    _webSocketService.onDisconnected = _handleDisconnect;
    _webSocketService.onMessage = _handleMessage;
    await _webSocketService.connect(serverInfo);
    await sendIdentify();
  }

  /// Disconnect from the WebSocket server
  void disconnect() {
    _webSocketService.disconnect();
  }

  /// Send an identify message to the server
  Future<void> sendIdentify() async {
    if (!_webSocketService.isConnected) return;

    final deviceId = await _deviceIdProvider();
    final deviceName = await _deviceNameProvider();
    final sessionToken = await _sessionTokenProvider();

    _webSocketService.sendMessage(
      IdentifyMessage(
        deviceId: deviceId,
        deviceName: deviceName,
        sessionToken: sessionToken,
      ),
    );
  }

  /// Handle WebSocket reconnect event
  Future<void> _handleReconnect() async {
    // Ensure this socket is identified on the server
    await sendIdentify();
    await _onReconnect();
  }

  /// Handle WebSocket disconnect event
  Future<void> _handleDisconnect() async {
    await _onDisconnect();
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(WsMessage message) {
    if (message.type != WsMessageType.syncTokenAdvanced) {
      return;
    }

    final latestToken = _parseLatestToken(message.data?['latestToken']);
    if (latestToken > 0) {
      // Fire and forget - don't block message handling
      unawaited(_onSyncTokenAdvanced(latestToken));
    }
  }

  /// Parse the latest token from various possible formats
  int _parseLatestToken(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
