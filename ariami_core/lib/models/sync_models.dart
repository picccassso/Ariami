/// V2 sync API models for versioned incremental library synchronization.
library;

import 'api_models.dart';

enum V2EntityType {
  album,
  song,
  playlist,
  playlistSong,
  artwork,
}

enum V2ChangeOperation {
  upsert,
  delete,
}

String _entityTypeToJson(V2EntityType value) {
  switch (value) {
    case V2EntityType.album:
      return 'album';
    case V2EntityType.song:
      return 'song';
    case V2EntityType.playlist:
      return 'playlist';
    case V2EntityType.playlistSong:
      return 'playlist_song';
    case V2EntityType.artwork:
      return 'artwork';
  }
}

V2EntityType _entityTypeFromJson(String value) {
  switch (value) {
    case 'album':
      return V2EntityType.album;
    case 'song':
      return V2EntityType.song;
    case 'playlist':
      return V2EntityType.playlist;
    case 'playlist_song':
      return V2EntityType.playlistSong;
    case 'artwork':
      return V2EntityType.artwork;
    default:
      throw FormatException('Unsupported V2EntityType: $value');
  }
}

String _changeOperationToJson(V2ChangeOperation value) {
  switch (value) {
    case V2ChangeOperation.upsert:
      return 'upsert';
    case V2ChangeOperation.delete:
      return 'delete';
  }
}

V2ChangeOperation _changeOperationFromJson(String value) {
  switch (value) {
    case 'upsert':
      return V2ChangeOperation.upsert;
    case 'delete':
      return V2ChangeOperation.delete;
    default:
      throw FormatException('Unsupported V2ChangeOperation: $value');
  }
}

class V2PageInfo {
  final String? cursor;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  V2PageInfo({
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  factory V2PageInfo.fromJson(Map<String, dynamic> json) {
    return V2PageInfo(
      cursor: json['cursor'] as String?,
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool,
      limit: json['limit'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cursor': cursor,
      'nextCursor': nextCursor,
      'hasMore': hasMore,
      'limit': limit,
    };
  }
}

class V2BootstrapResponse {
  final int syncToken;
  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<PlaylistModel> playlists;
  final V2PageInfo pageInfo;

  V2BootstrapResponse({
    required this.syncToken,
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.pageInfo,
  });

  factory V2BootstrapResponse.fromJson(Map<String, dynamic> json) {
    return V2BootstrapResponse(
      syncToken: json['syncToken'] as int,
      albums: (json['albums'] as List<dynamic>)
          .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: (json['songs'] as List<dynamic>)
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      playlists: (json['playlists'] as List<dynamic>)
          .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: V2PageInfo.fromJson(json['pageInfo'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'syncToken': syncToken,
      'albums': albums.map((e) => e.toJson()).toList(),
      'songs': songs.map((e) => e.toJson()).toList(),
      'playlists': playlists.map((e) => e.toJson()).toList(),
      'pageInfo': pageInfo.toJson(),
    };
  }
}

class V2ChangeEvent {
  final int token;
  final V2ChangeOperation op;
  final V2EntityType entityType;
  final String entityId;
  final Map<String, dynamic>? payload;
  final String occurredAt;

  V2ChangeEvent({
    required this.token,
    required this.op,
    required this.entityType,
    required this.entityId,
    this.payload,
    required this.occurredAt,
  });

  factory V2ChangeEvent.fromJson(Map<String, dynamic> json) {
    return V2ChangeEvent(
      token: json['token'] as int,
      op: _changeOperationFromJson(json['op'] as String),
      entityType: _entityTypeFromJson(json['entityType'] as String),
      entityId: json['entityId'] as String,
      payload: (json['payload'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>(),
      occurredAt: json['occurredAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'op': _changeOperationToJson(op),
      'entityType': _entityTypeToJson(entityType),
      'entityId': entityId,
      'payload': payload,
      'occurredAt': occurredAt,
    };
  }
}

class V2ChangesResponse {
  final int fromToken;
  final int toToken;
  final List<V2ChangeEvent> events;
  final bool hasMore;

  V2ChangesResponse({
    required this.fromToken,
    required this.toToken,
    required this.events,
    required this.hasMore,
  });

  factory V2ChangesResponse.fromJson(Map<String, dynamic> json) {
    return V2ChangesResponse(
      fromToken: json['fromToken'] as int,
      toToken: json['toToken'] as int,
      events: (json['events'] as List<dynamic>)
          .map((e) => V2ChangeEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['hasMore'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromToken': fromToken,
      'toToken': toToken,
      'events': events.map((e) => e.toJson()).toList(),
      'hasMore': hasMore,
    };
  }
}
