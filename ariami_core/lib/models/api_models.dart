/// API request and response models for Ariami communication protocol
library;

import '../utils/encoding_utils.dart';

export 'sync_models.dart';

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
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
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

class SongModel {
  final String id;
  final String title;
  final String artist;
  final String? genre;
  final String? albumId;
  final int duration; // in seconds
  final int? trackNumber;
  final bool hasLyrics;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    this.genre,
    this.albumId,
    required this.duration,
    this.trackNumber,
    this.hasLyrics = false,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] as String,
      title: EncodingUtils.fixEncoding(json['title'] as String) ??
          json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ??
          json['artist'] as String,
      genre: EncodingUtils.fixEncoding(json['genre'] as String?),
      albumId: json['albumId'] as String?,
      duration: json['duration'] as int,
      trackNumber: json['trackNumber'] as int?,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      if (genre != null) 'genre': genre,
      'albumId': albumId,
      'duration': duration,
      'trackNumber': trackNumber,
      'hasLyrics': hasLyrics,
    };
  }
}

class PlaylistModel {
  final String id;
  final String name;
  final int songCount;
  final int duration; // in seconds
  final List<String> songIds;

  PlaylistModel({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.songIds = const <String>[],
  });

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: json['id'] as String,
      name: json['name'] as String,
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

class LibraryResponse {
  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<PlaylistModel> playlists;
  final String lastUpdated;
  final bool durationsReady;

  LibraryResponse({
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.lastUpdated,
    required this.durationsReady,
  });

  factory LibraryResponse.fromJson(Map<String, dynamic> json) {
    return LibraryResponse(
      albums: (json['albums'] as List<dynamic>)
          .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: (json['songs'] as List<dynamic>)
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      playlists: (json['playlists'] as List<dynamic>)
          .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastUpdated: json['lastUpdated'] as String,
      durationsReady: json['durationsReady'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'albums': albums.map((e) => e.toJson()).toList(),
      'songs': songs.map((e) => e.toJson()).toList(),
      'playlists': playlists.map((e) => e.toJson()).toList(),
      'lastUpdated': lastUpdated,
      'durationsReady': durationsReady,
    };
  }
}

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
      if (coverArt != null) 'coverArt': coverArt,
      'songs': songs.map((e) => e.toJson()).toList(),
    };
  }
}

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

class ApiErrorCodes {
  static const String invalidSession = 'INVALID_SESSION';
  static const String songNotFound = 'SONG_NOT_FOUND';
  static const String albumNotFound = 'ALBUM_NOT_FOUND';
  static const String libraryUpdating = 'LIBRARY_UPDATING';
  static const String serverError = 'SERVER_ERROR';
  static const String invalidRequest = 'INVALID_REQUEST';
  static const String unauthorized = 'UNAUTHORIZED';

  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String userExists = 'USER_EXISTS';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String streamTokenExpired = 'STREAM_TOKEN_EXPIRED';
  static const String authRequired = 'AUTH_REQUIRED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String alreadyLoggedInOtherDevice =
      'ALREADY_LOGGED_IN_OTHER_DEVICE';
}
