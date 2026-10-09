part of '../api_models.dart';

class PlaylistModel {
  final String id;
  final String name;
  final String? description;

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

/// Per-account edit overlay for a server-side playlist.
class ServerPlaylistEdit {
  final String playlistId;
  final String? name;
  final List<String> songIds;
  final List<String> baseSnapshot;

  ServerPlaylistEdit({
    required this.playlistId,
    required this.name,
    required this.songIds,
    required this.baseSnapshot,
  });

  factory ServerPlaylistEdit.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String?;
    return ServerPlaylistEdit(
      playlistId: json['playlistId'] as String,
      name: rawName == null ? null : EncodingUtils.fixEncoding(rawName),
      songIds: (json['songIds'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>(),
      baseSnapshot:
          (json['baseSnapshot'] as List<dynamic>? ?? const <dynamic>[])
              .cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playlistId': playlistId,
      'name': name,
      'songIds': songIds,
      'baseSnapshot': baseSnapshot,
    };
  }
}

/// Manifest entry for a synced custom playlist cover image.
class ServerPlaylistImage {
  final String playlistId;
  final String contentType;
  final int updatedAt;

  const ServerPlaylistImage({
    required this.playlistId,
    required this.contentType,
    required this.updatedAt,
  });

  static ServerPlaylistImage? fromJson(Map<String, dynamic> json) {
    final playlistId = json['playlistId'];
    final updatedAt = json['updatedAt'];
    if (playlistId is! String || updatedAt is! num) return null;
    return ServerPlaylistImage(
      playlistId: playlistId,
      contentType: json['contentType'] as String? ?? 'image/jpeg',
      updatedAt: updatedAt.toInt(),
    );
  }
}
