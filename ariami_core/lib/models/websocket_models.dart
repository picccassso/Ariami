/// WebSocket message models for real-time communication
library;

// ============================================================================
// MESSAGE TYPES
// ============================================================================

class WsMessageType {
  static const String identify = 'identify';
  static const String libraryUpdated = 'library_updated';
  static const String songAdded = 'song_added';
  static const String albumAdded = 'album_added';
  static const String songRemoved = 'song_removed';
  static const String albumRemoved = 'album_removed';
  static const String serverShutdown = 'server_shutdown';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String clientConnected = 'client_connected';
  static const String clientDisconnected = 'client_disconnected';
}

// ============================================================================
// BASE MESSAGE
// ============================================================================

/// Base WebSocket message
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

// ============================================================================
// SPECIFIC MESSAGE TYPES
// ============================================================================

/// Library updated notification
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

/// Client identify message (sent by client after WebSocket connect)
class IdentifyMessage extends WsMessage {
  IdentifyMessage({
    required String deviceId,
    String? deviceName,
  }) : super(
          type: WsMessageType.identify,
          data: {
            'deviceId': deviceId,
            if (deviceName != null) 'deviceName': deviceName,
          },
        );

  factory IdentifyMessage.fromWsMessage(WsMessage message) {
    return IdentifyMessage(
      deviceId: message.data?['deviceId'] as String? ?? '',
      deviceName: message.data?['deviceName'] as String?,
    );
  }

  String get deviceId => data?['deviceId'] as String? ?? '';
  String? get deviceName => data?['deviceName'] as String?;
}

/// Song added notification
class SongAddedMessage extends WsMessage {
  SongAddedMessage({
    required Map<String, dynamic> songData,
  }) : super(
          type: WsMessageType.songAdded,
          data: songData,
        );

  factory SongAddedMessage.fromWsMessage(WsMessage message) {
    return SongAddedMessage(songData: message.data ?? {});
  }

  String? get songId => data?['id'] as String?;
  String? get title => data?['title'] as String?;
}

/// Album added notification
class AlbumAddedMessage extends WsMessage {
  AlbumAddedMessage({
    required Map<String, dynamic> albumData,
  }) : super(
          type: WsMessageType.albumAdded,
          data: albumData,
        );

  factory AlbumAddedMessage.fromWsMessage(WsMessage message) {
    return AlbumAddedMessage(albumData: message.data ?? {});
  }

  String? get albumId => data?['id'] as String?;
  String? get title => data?['title'] as String?;
}

/// Ping message
class PingMessage extends WsMessage {
  PingMessage() : super(type: WsMessageType.ping);
}

/// Pong message
class PongMessage extends WsMessage {
  PongMessage() : super(type: WsMessageType.pong);
}

/// Client connected notification
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

/// Client disconnected notification
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
