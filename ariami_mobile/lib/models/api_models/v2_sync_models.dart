part of '../api_models.dart';

// ============================================================================
// V2 SYNC MODELS
// ============================================================================

class V2PageInfo {
  final String? cursor;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  const V2PageInfo({
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  factory V2PageInfo.fromJson(Map<String, dynamic> json) {
    return V2PageInfo(
      cursor: json['cursor'] as String?,
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
      limit: json['limit'] as int? ?? 0,
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

class V2PlaylistModel {
  final String id;
  final String name;
  final int songCount;
  final int duration;
  final List<String> songIds;

  const V2PlaylistModel({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.songIds = const <String>[],
  });

  factory V2PlaylistModel.fromJson(Map<String, dynamic> json) {
    return V2PlaylistModel(
      id: json['id'] as String,
      name: EncodingUtils.fixEncoding(json['name'] as String) ??
          json['name'] as String,
      songCount: json['songCount'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      songIds: (json['songIds'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songCount': songCount,
      'duration': duration,
      'songIds': songIds,
    };
  }
}

class V2BootstrapResponse {
  final int syncToken;
  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<V2PlaylistModel> playlists;
  final V2PageInfo pageInfo;

  const V2BootstrapResponse({
    required this.syncToken,
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.pageInfo,
  });

  factory V2BootstrapResponse.fromJson(Map<String, dynamic> json) {
    return V2BootstrapResponse(
      syncToken: json['syncToken'] as int? ?? 0,
      albums: (json['albums'] as List<dynamic>? ?? [])
          .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      playlists: (json['playlists'] as List<dynamic>? ?? [])
          .map((e) => V2PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: V2PageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class V2AlbumsPageResponse {
  final int syncToken;
  final List<AlbumModel> albums;
  final V2PageInfo pageInfo;

  const V2AlbumsPageResponse({
    required this.syncToken,
    required this.albums,
    required this.pageInfo,
  });

  factory V2AlbumsPageResponse.fromJson(Map<String, dynamic> json) {
    return V2AlbumsPageResponse(
      syncToken: json['syncToken'] as int? ?? 0,
      albums: (json['albums'] as List<dynamic>? ?? [])
          .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: V2PageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class V2SongsPageResponse {
  final int syncToken;
  final List<SongModel> songs;
  final V2PageInfo pageInfo;

  const V2SongsPageResponse({
    required this.syncToken,
    required this.songs,
    required this.pageInfo,
  });

  factory V2SongsPageResponse.fromJson(Map<String, dynamic> json) {
    return V2SongsPageResponse(
      syncToken: json['syncToken'] as int? ?? 0,
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: V2PageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class V2PlaylistsPageResponse {
  final int syncToken;
  final List<V2PlaylistModel> playlists;
  final V2PageInfo pageInfo;

  const V2PlaylistsPageResponse({
    required this.syncToken,
    required this.playlists,
    required this.pageInfo,
  });

  factory V2PlaylistsPageResponse.fromJson(Map<String, dynamic> json) {
    return V2PlaylistsPageResponse(
      syncToken: json['syncToken'] as int? ?? 0,
      playlists: (json['playlists'] as List<dynamic>? ?? [])
          .map((e) => V2PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: V2PageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class V2ChangeOp {
  static const String upsert = 'upsert';
  static const String delete = 'delete';
}

class V2EntityType {
  static const String album = 'album';
  static const String song = 'song';
  static const String playlist = 'playlist';
  static const String playlistSong = 'playlist_song';
  static const String artwork = 'artwork';
}

class V2ChangeEvent {
  final int token;
  final String op;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? payload;
  final String occurredAt;

  const V2ChangeEvent({
    required this.token,
    required this.op,
    required this.entityType,
    required this.entityId,
    this.payload,
    required this.occurredAt,
  });

  factory V2ChangeEvent.fromJson(Map<String, dynamic> json) {
    return V2ChangeEvent(
      token: json['token'] as int? ?? 0,
      op: json['op'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      payload:
          (json['payload'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>(),
      occurredAt: json['occurredAt'] as String? ?? '',
    );
  }
}

class V2ChangesResponse {
  final int fromToken;
  final int toToken;
  final List<V2ChangeEvent> events;
  final bool hasMore;
  final int syncToken;

  const V2ChangesResponse({
    required this.fromToken,
    required this.toToken,
    required this.events,
    required this.hasMore,
    required this.syncToken,
  });

  factory V2ChangesResponse.fromJson(Map<String, dynamic> json) {
    return V2ChangesResponse(
      fromToken: json['fromToken'] as int? ?? 0,
      toToken: json['toToken'] as int? ?? 0,
      events: (json['events'] as List<dynamic>? ?? [])
          .map((e) => V2ChangeEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['hasMore'] as bool? ?? false,
      syncToken: json['syncToken'] as int? ?? 0,
    );
  }
}
