/// API request and response models for Ariami communication protocol
library;

import '../utils/encoding_utils.dart';

// ============================================================================
// CONNECTION MODELS
// ============================================================================

/// Request for connecting a mobile device
class ConnectRequest {
  final String deviceId;
  final String deviceName;
  final String appVersion;
  final String platform;

  ConnectRequest({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.platform,
  });

  factory ConnectRequest.fromJson(Map<String, dynamic> json) {
    return ConnectRequest(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      appVersion: json['appVersion'] as String,
      platform: json['platform'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'appVersion': appVersion,
      'platform': platform,
    };
  }
}

/// Response when device successfully connects
class ConnectResponse {
  final String status;
  final String sessionId;
  final String serverVersion;
  final List<String> features;
  final String? deviceId;

  ConnectResponse({
    required this.status,
    required this.sessionId,
    required this.serverVersion,
    required this.features,
    this.deviceId,
  });

  factory ConnectResponse.fromJson(Map<String, dynamic> json) {
    return ConnectResponse(
      status: json['status'] as String,
      sessionId: json['sessionId'] as String,
      serverVersion: json['serverVersion'] as String,
      features: (json['features'] as List<dynamic>? ?? []).cast<String>(),
      deviceId: json['deviceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'sessionId': sessionId,
      'serverVersion': serverVersion,
      'features': features,
      if (deviceId != null) 'deviceId': deviceId,
    };
  }
}

/// Request for disconnecting a device
class DisconnectRequest {
  final String? deviceId;

  DisconnectRequest({this.deviceId});

  factory DisconnectRequest.fromJson(Map<String, dynamic> json) {
    return DisconnectRequest(
      deviceId: json['deviceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (deviceId != null) 'deviceId': deviceId,
    };
  }
}

/// Response for disconnect request
class DisconnectResponse {
  final String status;

  DisconnectResponse({required this.status});

  factory DisconnectResponse.fromJson(Map<String, dynamic> json) {
    return DisconnectResponse(
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
    };
  }
}

// ============================================================================
// LIBRARY MODELS
// ============================================================================

/// Album information
class AlbumModel {
  final String id;
  final String title;
  final String artist;
  final String? coverArt;
  final int songCount;
  final int duration; // in seconds
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  AlbumModel({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArt,
    required this.songCount,
    required this.duration,
    this.createdAt,
    this.modifiedAt,
  });

  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    return AlbumModel(
      id: json['id'] as String,
      title: EncodingUtils.fixEncoding(json['title'] as String) ??
          json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ??
          json['artist'] as String,
      coverArt: json['coverArt'] as String?,
      songCount: json['songCount'] as int,
      duration: json['duration'] as int,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'coverArt': coverArt,
      'songCount': songCount,
      'duration': duration,
      'createdAt': createdAt?.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }

  AlbumModel copyWith({
    String? id,
    String? title,
    String? artist,
    String? coverArt,
    int? songCount,
    int? duration,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return AlbumModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverArt: coverArt ?? this.coverArt,
      songCount: songCount ?? this.songCount,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}

/// Song information
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final int duration; // in seconds
  final int? trackNumber;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    this.albumId,
    required this.duration,
    this.trackNumber,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] as String,
      title: EncodingUtils.fixEncoding(json['title'] as String) ??
          json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ??
          json['artist'] as String,
      albumId: json['albumId'] as String?,
      duration: json['duration'] as int,
      trackNumber: json['trackNumber'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumId': albumId,
      'duration': duration,
      'trackNumber': trackNumber,
    };
  }
}

/// Playlist information (full model for local storage)
class PlaylistModel {
  final String id;
  final String name;
  final String? description;

  /// Custom cover image path (user-selected photo)
  final String? customImagePath;
  final List<String> songIds;

  /// Map of songId to albumId for artwork lookup
  final Map<String, String> songAlbumIds;

  /// Map of songId to song title for offline display
  final Map<String, String> songTitles;

  /// Map of songId to artist name for offline display
  final Map<String, String> songArtists;

  /// Map of songId to duration (seconds) for offline display
  final Map<String, int> songDurations;
  final DateTime createdAt;
  final DateTime modifiedAt;

  PlaylistModel({
    required this.id,
    required this.name,
    this.description,
    this.customImagePath,
    required this.songIds,
    this.songAlbumIds = const {},
    this.songTitles = const {},
    this.songArtists = const {},
    this.songDurations = const {},
    required this.createdAt,
    required this.modifiedAt,
  });

  /// Computed property: number of songs
  int get songCount => songIds.length;

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: json['id'] as String,
      name: EncodingUtils.fixEncoding(json['name'] as String) ??
          json['name'] as String,
      description: EncodingUtils.fixEncoding(json['description'] as String?),
      customImagePath: json['customImagePath'] as String?,
      songIds: (json['songIds'] as List<dynamic>? ?? []).cast<String>(),
      songAlbumIds: (json['songAlbumIds'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
      songTitles: (json['songTitles'] as Map<String, dynamic>? ?? {}).map((k,
              v) =>
          MapEntry(k, EncodingUtils.fixEncoding(v.toString()) ?? v.toString())),
      songArtists: (json['songArtists'] as Map<String, dynamic>? ?? {}).map((k,
              v) =>
          MapEntry(k, EncodingUtils.fixEncoding(v.toString()) ?? v.toString())),
      songDurations: (json['songDurations'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as int)),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'customImagePath': customImagePath,
      'songIds': songIds,
      'songAlbumIds': songAlbumIds,
      'songTitles': songTitles,
      'songArtists': songArtists,
      'songDurations': songDurations,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  /// Note: Use clearCustomImagePath: true to explicitly remove the custom image
  PlaylistModel copyWith({
    String? id,
    String? name,
    String? description,
    String? customImagePath,
    bool clearCustomImagePath = false,
    List<String>? songIds,
    Map<String, String>? songAlbumIds,
    Map<String, String>? songTitles,
    Map<String, String>? songArtists,
    Map<String, int>? songDurations,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      customImagePath: clearCustomImagePath
          ? null
          : (customImagePath ?? this.customImagePath),
      songIds: songIds ?? this.songIds,
      songAlbumIds: songAlbumIds ?? this.songAlbumIds,
      songTitles: songTitles ?? this.songTitles,
      songArtists: songArtists ?? this.songArtists,
      songDurations: songDurations ?? this.songDurations,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}

/// Server-side playlist (from [PLAYLIST] folders)
/// Simpler than PlaylistModel - just contains song IDs, no local metadata
class ServerPlaylist {
  final String id;
  final String name;
  final List<String> songIds;
  final int songCount;

  ServerPlaylist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.songCount,
  });

  factory ServerPlaylist.fromJson(Map<String, dynamic> json) {
    return ServerPlaylist(
      id: json['id'] as String,
      name: EncodingUtils.fixEncoding(json['name'] as String) ??
          json['name'] as String,
      songIds: (json['songIds'] as List<dynamic>? ?? []).cast<String>(),
      songCount: json['songCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songIds': songIds,
      'songCount': songCount,
    };
  }
}

/// Complete library response
class LibraryResponse {
  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<ServerPlaylist> serverPlaylists;
  final String lastUpdated;
  final bool durationsReady;

  LibraryResponse({
    required this.albums,
    required this.songs,
    required this.serverPlaylists,
    required this.lastUpdated,
    required this.durationsReady,
  });

  factory LibraryResponse.fromJson(Map<String, dynamic> json) {
    return LibraryResponse(
      albums: (json['albums'] as List<dynamic>? ?? [])
          .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      serverPlaylists: (json['playlists'] as List<dynamic>? ?? [])
          .map((e) => ServerPlaylist.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastUpdated: json['lastUpdated'] as String? ?? '',
      durationsReady: json['durationsReady'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'albums': albums.map((e) => e.toJson()).toList(),
      'songs': songs.map((e) => e.toJson()).toList(),
      'playlists': serverPlaylists.map((e) => e.toJson()).toList(),
      'lastUpdated': lastUpdated,
      'durationsReady': durationsReady,
    };
  }
}

/// Detailed album response with songs
class AlbumDetailResponse {
  final String id;
  final String title;
  final String artist;
  final String? year;
  final String? coverArt;
  final List<SongModel> songs;

  AlbumDetailResponse({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.coverArt,
    required this.songs,
  });

  factory AlbumDetailResponse.fromJson(Map<String, dynamic> json) {
    return AlbumDetailResponse(
      id: json['id'] as String,
      title: EncodingUtils.fixEncoding(json['title'] as String) ??
          json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ??
          json['artist'] as String,
      year: json['year'] as String?,
      coverArt: json['coverArt'] as String?,
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'year': year,
      'coverArt': coverArt,
      'songs': songs.map((e) => e.toJson()).toList(),
    };
  }
}

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

// ============================================================================
// V2 DOWNLOAD JOB MODELS
// ============================================================================

class DownloadJobCreateRequest {
  final List<String> songIds;
  final List<String> albumIds;
  final List<String> playlistIds;
  final String quality;
  final bool downloadOriginal;

  const DownloadJobCreateRequest({
    this.songIds = const <String>[],
    this.albumIds = const <String>[],
    this.playlistIds = const <String>[],
    this.quality = 'high',
    this.downloadOriginal = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'songIds': songIds,
      'albumIds': albumIds,
      'playlistIds': playlistIds,
      'quality': quality,
      'downloadOriginal': downloadOriginal,
    };
  }
}

class DownloadJobCreateResponse {
  final String jobId;
  final String status;
  final String quality;
  final bool downloadOriginal;
  final int itemCount;
  final String createdAt;
  final String updatedAt;

  const DownloadJobCreateResponse({
    required this.jobId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadJobCreateResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobCreateResponse(
      jobId: json['jobId'] as String,
      status: json['status'] as String? ?? '',
      quality: json['quality'] as String? ?? 'high',
      downloadOriginal: json['downloadOriginal'] as bool? ?? false,
      itemCount: json['itemCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class DownloadJobStatusResponse {
  final String jobId;
  final String userId;
  final String status;
  final String quality;
  final bool downloadOriginal;
  final int itemCount;
  final int pendingCount;
  final int cancelledCount;
  final String createdAt;
  final String updatedAt;

  const DownloadJobStatusResponse({
    required this.jobId,
    required this.userId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.itemCount,
    required this.pendingCount,
    required this.cancelledCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadJobStatusResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobStatusResponse(
      jobId: json['jobId'] as String,
      userId: json['userId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      quality: json['quality'] as String? ?? 'high',
      downloadOriginal: json['downloadOriginal'] as bool? ?? false,
      itemCount: json['itemCount'] as int? ?? 0,
      pendingCount: json['pendingCount'] as int? ?? 0,
      cancelledCount: json['cancelledCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class DownloadJobItemModel {
  final int itemOrder;
  final String songId;
  final String status;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumName;
  final String? albumArtist;
  final int? trackNumber;
  final int durationSeconds;
  final int? fileSizeBytes;
  final String? errorCode;
  final int? retryAfterEpochMs;

  const DownloadJobItemModel({
    required this.itemOrder,
    required this.songId,
    required this.status,
    required this.title,
    required this.artist,
    this.albumId,
    this.albumName,
    this.albumArtist,
    this.trackNumber,
    required this.durationSeconds,
    this.fileSizeBytes,
    this.errorCode,
    this.retryAfterEpochMs,
  });

  factory DownloadJobItemModel.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemModel(
      itemOrder: json['itemOrder'] as int? ?? 0,
      songId: json['songId'] as String,
      status: json['status'] as String? ?? '',
      title: EncodingUtils.fixEncoding(json['title'] as String? ?? '') ??
          (json['title'] as String? ?? ''),
      artist: EncodingUtils.fixEncoding(json['artist'] as String? ?? '') ??
          (json['artist'] as String? ?? ''),
      albumId: json['albumId'] as String?,
      albumName: EncodingUtils.fixEncoding(json['albumName'] as String?),
      albumArtist: EncodingUtils.fixEncoding(json['albumArtist'] as String?),
      trackNumber: json['trackNumber'] as int?,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      fileSizeBytes: json['fileSizeBytes'] as int?,
      errorCode: json['errorCode'] as String?,
      retryAfterEpochMs: json['retryAfterEpochMs'] as int?,
    );
  }
}

class DownloadJobItemsPageInfo {
  final String? cursor;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  const DownloadJobItemsPageInfo({
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  factory DownloadJobItemsPageInfo.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemsPageInfo(
      cursor: json['cursor'] as String?,
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
      limit: json['limit'] as int? ?? 0,
    );
  }
}

class DownloadJobItemsResponse {
  final String jobId;
  final List<DownloadJobItemModel> items;
  final DownloadJobItemsPageInfo pageInfo;

  const DownloadJobItemsResponse({
    required this.jobId,
    required this.items,
    required this.pageInfo,
  });

  factory DownloadJobItemsResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemsResponse(
      jobId: json['jobId'] as String,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => DownloadJobItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: DownloadJobItemsPageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class DownloadJobCancelResponse {
  final String jobId;
  final String status;
  final String cancelledAt;

  const DownloadJobCancelResponse({
    required this.jobId,
    required this.status,
    required this.cancelledAt,
  });

  factory DownloadJobCancelResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobCancelResponse(
      jobId: json['jobId'] as String,
      status: json['status'] as String? ?? '',
      cancelledAt: json['cancelledAt'] as String? ?? '',
    );
  }
}

// ============================================================================
// ERROR MODELS
// ============================================================================

/// Error response format
class ApiError {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  ApiError({
    required this.code,
    required this.message,
    this.details,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
    };
  }
}

/// Error response wrapper
class ErrorResponse {
  final ApiError error;

  ErrorResponse({required this.error});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    return ErrorResponse(
      error: ApiError.fromJson(json['error'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'error': error.toJson(),
    };
  }
}

// ============================================================================
// ERROR CODES
// ============================================================================

class ApiErrorCodes {
  static const String invalidSession = 'INVALID_SESSION';
  static const String songNotFound = 'SONG_NOT_FOUND';
  static const String albumNotFound = 'ALBUM_NOT_FOUND';
  static const String libraryUpdating = 'LIBRARY_UPDATING';
  static const String serverError = 'SERVER_ERROR';
  static const String invalidRequest = 'INVALID_REQUEST';
  static const String unauthorized = 'UNAUTHORIZED';

  // Auth error codes
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String userExists = 'USER_EXISTS';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String streamTokenExpired = 'STREAM_TOKEN_EXPIRED';
  static const String authRequired = 'AUTH_REQUIRED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String alreadyLoggedInOtherDevice =
      'ALREADY_LOGGED_IN_OTHER_DEVICE';
}
