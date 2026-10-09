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
  final Future<void> Function(int? closeCode, String? closeReason)?
      _onSessionInvalidated;
  final Future<void> Function(int latestToken) _onSyncTokenAdvanced;
  final Future<void> Function()? _onEndpointAliasesChanged;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _deviceNameProvider;
  final Future<String?> Function() _sessionTokenProvider;

  WebSocketHandler({
    required WebSocketService webSocketService,
    required Future<void> Function() onReconnect,
    required Future<void> Function() onDisconnect,
    Future<void> Function(int? closeCode, String? closeReason)?
        onSessionInvalidated,
    required Future<void> Function(int latestToken) onSyncTokenAdvanced,
    Future<void> Function()? onEndpointAliasesChanged,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() deviceNameProvider,
    required Future<String?> Function() sessionTokenProvider,
  })  : _webSocketService = webSocketService,
        _onReconnect = onReconnect,
        _onDisconnect = onDisconnect,
        _onSessionInvalidated = onSessionInvalidated,
        _onSyncTokenAdvanced = onSyncTokenAdvanced,
        _onEndpointAliasesChanged = onEndpointAliasesChanged,
        _deviceIdProvider = deviceIdProvider,
        _deviceNameProvider = deviceNameProvider,
        _sessionTokenProvider = sessionTokenProvider;

  Stream<WsMessage> get messages => _webSocketService.messages;

  bool get isConnected => _webSocketService.isConnected;

  Future<void> connect(dynamic serverInfo) async {
    _webSocketService.onReconnected = _handleReconnect;
    _webSocketService.onDisconnected = _handleDisconnect;
    _webSocketService.onSessionInvalidated = _handleSessionInvalidated;
    _webSocketService.onMessage = _handleMessage;
    await _webSocketService.connect(serverInfo);
    await sendIdentify();
  }

  void disconnect() {
    _webSocketService.disconnect();
  }

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

  Future<void> _handleReconnect() async {
    await sendIdentify();
    await _onReconnect();
  }

  Future<void> _handleDisconnect() async {
    await _onDisconnect();
  }

  Future<void> _handleSessionInvalidated(
    int? closeCode,
    String? closeReason,
  ) async {
    final onSessionInvalidated = _onSessionInvalidated;
    if (onSessionInvalidated != null) {
      await onSessionInvalidated(closeCode, closeReason);
      return;
    }
    await _onDisconnect();
  }

  void _handleMessage(WsMessage message) {
    if (message.type == WsMessageType.endpointAliasesChanged) {
      final onEndpointAliasesChanged = _onEndpointAliasesChanged;
      if (onEndpointAliasesChanged != null) {
        unawaited(onEndpointAliasesChanged());
      }
      return;
    }

    if (message.type != WsMessageType.syncTokenAdvanced) {
      return;
    }

    final latestToken = _parseLatestToken(message.data?['latestToken']);
    if (latestToken > 0) {
      // Fire and forget - don't block message handling
      unawaited(_onSyncTokenAdvanced(latestToken));
    }
  }

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
