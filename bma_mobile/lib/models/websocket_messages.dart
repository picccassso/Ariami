/// WebSocket message models for real-time communication
/// Defines message types: library_update, now_playing, server_notification

/// Base class for all WebSocket messages
abstract class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;

  WebSocketMessage({required this.type, required this.data});

  /// Parse a JSON message and return the appropriate subclass
  static WebSocketMessage? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final data = json['data'] as Map<String, dynamic>?;

    if (type == null || data == null) return null;

    switch (type) {
      case 'library_update':
        return LibraryUpdateMessage.fromData(data);
      case 'now_playing':
        return NowPlayingMessage.fromData(data);
      case 'server_notification':
        return ServerNotificationMessage.fromData(data);
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
      };
}

/// Message for library updates (songs added/removed/changed)
class LibraryUpdateMessage extends WebSocketMessage {
  final String updateType; // songs_added, songs_removed, metadata_changed
  final List<String> affectedIds;
  final DateTime timestamp;

  LibraryUpdateMessage({
    required this.updateType,
    required this.affectedIds,
    required this.timestamp,
  }) : super(
          type: 'library_update',
          data: {
            'updateType': updateType,
            'affectedIds': affectedIds,
            'timestamp': timestamp.toIso8601String(),
          },
        );

  factory LibraryUpdateMessage.fromData(Map<String, dynamic> data) {
    return LibraryUpdateMessage(
      updateType: data['updateType'] as String,
      affectedIds: (data['affectedIds'] as List<dynamic>).cast<String>(),
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}

/// Message for now playing status from other clients
class NowPlayingMessage extends WebSocketMessage {
  final String deviceId;
  final String songId;
  final String status; // playing, paused, stopped

  NowPlayingMessage({
    required this.deviceId,
    required this.songId,
    required this.status,
  }) : super(
          type: 'now_playing',
          data: {
            'deviceId': deviceId,
            'songId': songId,
            'status': status,
          },
        );

  factory NowPlayingMessage.fromData(Map<String, dynamic> data) {
    return NowPlayingMessage(
      deviceId: data['deviceId'] as String,
      songId: data['songId'] as String,
      status: data['status'] as String,
    );
  }
}

/// Message for server notifications (info/warning/error)
class ServerNotificationMessage extends WebSocketMessage {
  final String severity; // info, warning, error
  final String message;

  ServerNotificationMessage({
    required this.severity,
    required this.message,
  }) : super(
          type: 'server_notification',
          data: {
            'severity': severity,
            'message': message,
          },
        );

  factory ServerNotificationMessage.fromData(Map<String, dynamic> data) {
    return ServerNotificationMessage(
      severity: data['severity'] as String,
      message: data['message'] as String,
    );
  }
}
