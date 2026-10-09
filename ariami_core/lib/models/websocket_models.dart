/// WebSocket message models for real-time communication
library;

class WsMessageType {
  static const String identify = 'identify';
  static const String libraryUpdated = 'library_updated';
  static const String syncTokenAdvanced = 'sync_token_advanced';
  static const String songRemoved = 'song_removed';
  static const String albumRemoved = 'album_removed';
  static const String serverShutdown = 'server_shutdown';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String clientConnected = 'client_connected';
  static const String clientDisconnected = 'client_disconnected';
  static const String listeningStatsUpdated = 'listening_stats_updated';
  static const String pinsChanged = 'pins_changed';
  static const String hiddenChanged = 'hidden_changed';
  static const String playlistEditsChanged = 'playlist_edits_changed';
  static const String artistImagesChanged = 'artist_images_changed';
  static const String endpointAliasesChanged = 'endpoint_aliases_changed';
}

class WsMessage {
  final String type;
  final Map<String, dynamic>? data;
  final String timestamp;

  WsMessage({
    required this.type,
    this.data,
    String? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toIso8601String();

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    return WsMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
      'timestamp': timestamp,
    };
  }
}

class LibraryUpdatedMessage extends WsMessage {
  LibraryUpdatedMessage({
    super.data,
  }) : super(
          type: WsMessageType.libraryUpdated,
        );

  factory LibraryUpdatedMessage.fromWsMessage(WsMessage message) {
    return LibraryUpdatedMessage(data: message.data);
  }

  int? get albumCount => data?['albumCount'] as int?;
  int? get songCount => data?['songCount'] as int?;
}

class SyncTokenAdvancedMessage extends WsMessage {
  SyncTokenAdvancedMessage({
    required int latestToken,
    required String reason,
  }) : super(
          type: WsMessageType.syncTokenAdvanced,
          data: {
            'latestToken': latestToken,
            'reason': reason,
          },
        );

  factory SyncTokenAdvancedMessage.fromWsMessage(WsMessage message) {
    return SyncTokenAdvancedMessage(
      latestToken: message.data?['latestToken'] as int? ?? 0,
      reason: message.data?['reason'] as String? ?? '',
    );
  }

  int get latestToken => data?['latestToken'] as int? ?? 0;
  String get reason => data?['reason'] as String? ?? '';
}

/// Client identify message (sent by client after WebSocket connect)
class IdentifyMessage extends WsMessage {
  IdentifyMessage({
    required String deviceId,
    String? deviceName,
    String? sessionToken,
    String? clientType,
  }) : super(
          type: WsMessageType.identify,
          data: {
            'deviceId': deviceId,
            if (deviceName != null) 'deviceName': deviceName,
            if (sessionToken != null) 'sessionToken': sessionToken,
            if (clientType != null) 'clientType': clientType,
          },
        );

  factory IdentifyMessage.fromWsMessage(WsMessage message) {
    return IdentifyMessage(
      deviceId: message.data?['deviceId'] as String? ?? '',
      deviceName: message.data?['deviceName'] as String?,
      sessionToken: message.data?['sessionToken'] as String?,
      clientType: message.data?['clientType'] as String?,
    );
  }

  String get deviceId => data?['deviceId'] as String? ?? '';
  String? get deviceName => data?['deviceName'] as String?;
  String? get sessionToken => data?['sessionToken'] as String?;
  String? get clientType => data?['clientType'] as String?;
}

class PingMessage extends WsMessage {
  PingMessage() : super(type: WsMessageType.ping);
}

class PongMessage extends WsMessage {
  PongMessage() : super(type: WsMessageType.pong);
}

class ClientConnectedMessage extends WsMessage {
  ClientConnectedMessage({
    required int clientCount,
    String? deviceName,
  }) : super(
          type: WsMessageType.clientConnected,
          data: {
            'clientCount': clientCount,
            if (deviceName != null) 'deviceName': deviceName,
          },
        );

  factory ClientConnectedMessage.fromWsMessage(WsMessage message) =>
      ClientConnectedMessage(
        clientCount: message.data?['clientCount'] as int? ?? 0,
        deviceName: message.data?['deviceName'] as String?,
      );

  int get clientCount => data?['clientCount'] as int? ?? 0;
  String? get deviceName => data?['deviceName'] as String?;
}

class ClientDisconnectedMessage extends WsMessage {
  ClientDisconnectedMessage({
    required int clientCount,
    String? deviceName,
  }) : super(
          type: WsMessageType.clientDisconnected,
          data: {
            'clientCount': clientCount,
            if (deviceName != null) 'deviceName': deviceName,
          },
        );

  factory ClientDisconnectedMessage.fromWsMessage(WsMessage message) =>
      ClientDisconnectedMessage(
        clientCount: message.data?['clientCount'] as int? ?? 0,
        deviceName: message.data?['deviceName'] as String?,
      );

  int get clientCount => data?['clientCount'] as int? ?? 0;
  String? get deviceName => data?['deviceName'] as String?;
}
