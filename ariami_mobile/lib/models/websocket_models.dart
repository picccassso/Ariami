/// WebSocket message models for real-time communication
library;

// ============================================================================
// MESSAGE TYPES
// ============================================================================

class WsMessageType {
  static const String libraryUpdated = 'library_updated';
  static const String songAdded = 'song_added';
  static const String albumAdded = 'album_added';
  static const String songRemoved = 'song_removed';
  static const String albumRemoved = 'album_removed';
  static const String serverShutdown = 'server_shutdown';
  static const String ping = 'ping';
  static const String pong = 'pong';
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
