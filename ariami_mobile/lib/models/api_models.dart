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

  ConnectResponse({
    required this.status,
    required this.sessionId,
    required this.serverVersion,
    required this.features,
  });

  factory ConnectResponse.fromJson(Map<String, dynamic> json) {
    return ConnectResponse(
      status: json['status'] as String,
      sessionId: json['sessionId'] as String,
      serverVersion: json['serverVersion'] as String,
      features: (json['features'] as List<dynamic>? ?? []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'sessionId': sessionId,
      'serverVersion': serverVersion,
      'features': features,
    };
  }
}

/// Request for disconnecting a device
class DisconnectRequest {
  final String sessionId;

  DisconnectRequest({required this.sessionId});

  factory DisconnectRequest.fromJson(Map<String, dynamic> json) {
    return DisconnectRequest(
      sessionId: json['sessionId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
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

  AlbumModel({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArt,
    required this.songCount,
    required this.duration,
  });

  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    return AlbumModel(
      id: json['id'] as String,
      title: EncodingUtils.fixEncoding(json['title'] as String) ?? json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ?? json['artist'] as String,
      coverArt: json['coverArt'] as String?,
      songCount: json['songCount'] as int,
      duration: json['duration'] as int,
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
    };
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
      title: EncodingUtils.fixEncoding(json['title'] as String) ?? json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ?? json['artist'] as String,
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
      name: EncodingUtils.fixEncoding(json['name'] as String) ?? json['name'] as String,
      description: EncodingUtils.fixEncoding(json['description'] as String?),
      songIds: (json['songIds'] as List<dynamic>? ?? []).cast<String>(),
      songAlbumIds: (json['songAlbumIds'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
      songTitles: (json['songTitles'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, EncodingUtils.fixEncoding(v.toString()) ?? v.toString())),
      songArtists: (json['songArtists'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, EncodingUtils.fixEncoding(v.toString()) ?? v.toString())),
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
  PlaylistModel copyWith({
    String? id,
    String? name,
    String? description,
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
      name: EncodingUtils.fixEncoding(json['name'] as String) ?? json['name'] as String,
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

  LibraryResponse({
    required this.albums,
    required this.songs,
    required this.serverPlaylists,
    required this.lastUpdated,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'albums': albums.map((e) => e.toJson()).toList(),
      'songs': songs.map((e) => e.toJson()).toList(),
      'playlists': serverPlaylists.map((e) => e.toJson()).toList(),
      'lastUpdated': lastUpdated,
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
      title: EncodingUtils.fixEncoding(json['title'] as String) ?? json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ?? json['artist'] as String,
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
}
