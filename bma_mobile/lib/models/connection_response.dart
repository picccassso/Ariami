class ConnectionResponse {
  final String status;
  final String sessionId;
  final String serverVersion;
  final List<String> features;

  ConnectionResponse({
    required this.status,
    required this.sessionId,
    required this.serverVersion,
    required this.features,
  });

  factory ConnectionResponse.fromJson(Map<String, dynamic> json) {
    return ConnectionResponse(
      status: json['status'],
      sessionId: json['sessionId'],
      serverVersion: json['serverVersion'],
      features: List<String>.from(json['features']),
    );
  }
}

class LibraryResponse {
  final List<AlbumInfo> albums;
  final List<SongInfo> songs;
  final List<PlaylistInfo> playlists;
  final DateTime lastUpdated;

  LibraryResponse({
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.lastUpdated,
  });

  factory LibraryResponse.fromJson(Map<String, dynamic> json) {
    return LibraryResponse(
      albums: (json['albums'] as List)
          .map((a) => AlbumInfo.fromJson(a))
          .toList(),
      songs:
          (json['songs'] as List).map((s) => SongInfo.fromJson(s)).toList(),
      playlists: (json['playlists'] as List)
          .map((p) => PlaylistInfo.fromJson(p))
          .toList(),
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }
}

class AlbumInfo {
  final String id;
  final String title;
  final String artist;
  final String coverArt;
  final int songCount;
  final int duration;
  final String? year;
  final List<SongInfo>? songs;

  AlbumInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverArt,
    required this.songCount,
    required this.duration,
    this.year,
    this.songs,
  });

  factory AlbumInfo.fromJson(Map<String, dynamic> json) {
    return AlbumInfo(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      coverArt: json['coverArt'],
      songCount: json['songCount'],
      duration: json['duration'],
      year: json['year'],
      songs: json['songs'] != null
          ? (json['songs'] as List).map((s) => SongInfo.fromJson(s)).toList()
          : null,
    );
  }
}

class SongInfo {
  final String id;
  final String title;
  final String artist;
  final String albumId;
  final int duration;
  final int trackNumber;

  SongInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.duration,
    required this.trackNumber,
  });

  factory SongInfo.fromJson(Map<String, dynamic> json) {
    return SongInfo(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      albumId: json['albumId'],
      duration: json['duration'],
      trackNumber: json['trackNumber'],
    );
  }
}

class PlaylistInfo {
  final String id;
  final String name;
  final int songCount;
  final int duration;

  PlaylistInfo({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
  });

  factory PlaylistInfo.fromJson(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['id'],
      name: json['name'],
      songCount: json['songCount'],
      duration: json['duration'],
    );
  }
}
