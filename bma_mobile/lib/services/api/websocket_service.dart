import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/websocket_messages.dart';

/// WebSocket service for real-time communication with desktop server
/// Handles connection, reconnection, and message routing
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const List<int> _reconnectDelays = [2, 4, 6]; // seconds

  String? _wsUrl;
  String? _sessionId;

  // Stream controllers for different message types
  final _libraryUpdatesController =
      StreamController<LibraryUpdateMessage>.broadcast();
  final _nowPlayingController =
      StreamController<NowPlayingMessage>.broadcast();
  final _notificationsController =
      StreamController<ServerNotificationMessage>.broadcast();

  // Public streams for consumers
  Stream<LibraryUpdateMessage> get libraryUpdates =>
      _libraryUpdatesController.stream;
  Stream<NowPlayingMessage> get nowPlaying => _nowPlayingController.stream;
  Stream<ServerNotificationMessage> get notifications =>
      _notificationsController.stream;

  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<bool> connect({
    required String wsUrl,
    required String sessionId,
  }) async {
    try {
      _wsUrl = wsUrl;
      _sessionId = sessionId;

      // Add session ID as query parameter
      final uri = Uri.parse('$wsUrl?session=$sessionId');

      _channel = WebSocketChannel.connect(uri);

      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnect,
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      notifyListeners();

      debugPrint('[WebSocket] Connected to $wsUrl');
      return true;
    } catch (e) {
      debugPrint('[WebSocket] Connection failed: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from WebSocket server
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _channel?.sink.close();
    _channel = null;

    _isConnected = false;
    _wsUrl = null;
    _sessionId = null;
    _reconnectAttempts = 0;

    notifyListeners();
    debugPrint('[WebSocket] Disconnected');
  }

  /// Handle incoming messages
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final wsMessage = WebSocketMessage.fromJson(data);

      if (wsMessage == null) {
        debugPrint('[WebSocket] Unknown message type: $data');
        return;
      }

      // Route message to appropriate stream
      if (wsMessage is LibraryUpdateMessage) {
        _libraryUpdatesController.add(wsMessage);
        debugPrint('[WebSocket] Library update: ${wsMessage.updateType}');
      } else if (wsMessage is NowPlayingMessage) {
        _nowPlayingController.add(wsMessage);
        debugPrint('[WebSocket] Now playing: ${wsMessage.songId}');
      } else if (wsMessage is ServerNotificationMessage) {
        _notificationsController.add(wsMessage);
        debugPrint(
            '[WebSocket] Notification [${wsMessage.severity}]: ${wsMessage.message}');
      }
    } catch (e) {
      debugPrint('[WebSocket] Message parsing error: $e');
    }
  }

  /// Handle WebSocket errors
  void _onError(dynamic error) {
    debugPrint('[WebSocket] Error: $error');
    _isConnected = false;
    notifyListeners();
  }

  /// Handle disconnection
  void _onDisconnect() {
    debugPrint('[WebSocket] Connection closed');
    _isConnected = false;
    notifyListeners();

    // Attempt reconnection
    _attemptReconnect();
  }

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint(
          '[WebSocket] Max reconnection attempts reached ($_maxReconnectAttempts)');
      return;
    }

    if (_wsUrl == null || _sessionId == null) {
      debugPrint('[WebSocket] Cannot reconnect: missing connection info');
      return;
    }

    final delay = _reconnectDelays[_reconnectAttempts];
    debugPrint(
        '[WebSocket] Reconnecting in $delay seconds (attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      _reconnectAttempts++;
      final success = await connect(
        wsUrl: _wsUrl!,
        sessionId: _sessionId!,
      );

      if (!success) {
        _attemptReconnect();
      }
    });
  }

  /// Send a message to the server (for future use)
  void sendMessage(WebSocketMessage message) {
    if (!_isConnected) {
      debugPrint('[WebSocket] Cannot send message: not connected');
      return;
    }

    try {
      final json = jsonEncode(message.toJson());
      _channel?.sink.add(json);
    } catch (e) {
      debugPrint('[WebSocket] Failed to send message: $e');
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _libraryUpdatesController.close();
    _nowPlayingController.close();
    _notificationsController.close();
    super.dispose();
  }
}
