class Song {
  final String id;
  final String title;
  final String artist;
  final String albumId;
  final int duration; // in seconds
  final int trackNumber;
  final String? filePath;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.duration,
    required this.trackNumber,
    this.filePath,
  });

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

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      albumId: json['albumId'],
      duration: json['duration'],
      trackNumber: json['trackNumber'],
      filePath: json['filePath'],
    );
  }
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? year;
  final int songCount;
  final int duration; // total duration in seconds
  final List<Song>? songs;
  final String? coverArtPath;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    required this.songCount,
    required this.duration,
    this.songs,
    this.coverArtPath,
  });

  Map<String, dynamic> toJson({bool includeSongs = false}) {
    final json = {
      'id': id,
      'title': title,
      'artist': artist,
      'coverArt': '/api/artwork/$id',
      'songCount': songCount,
      'duration': duration,
    };

    if (year != null) {
      json['year'] = year!;
    }

    if (includeSongs && songs != null) {
      json['songs'] = songs!.map((s) => s.toJson()).toList();
    }

    return json;
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      year: json['year'],
      songCount: json['songCount'],
      duration: json['duration'],
      coverArtPath: json['coverArtPath'],
      songs: json['songs'] != null
          ? (json['songs'] as List).map((s) => Song.fromJson(s)).toList()
          : null,
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final int songCount;
  final int duration; // total duration in seconds
  final List<String>? songIds;

  Playlist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.songIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songCount': songCount,
      'duration': duration,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      songCount: json['songCount'],
      duration: json['duration'],
      songIds: json['songIds'] != null
          ? List<String>.from(json['songIds'])
          : null,
    );
  }
}

class Library {
  final List<Album> albums;
  final List<Song> songs;
  final List<Playlist> playlists;
  final DateTime lastUpdated;

  Library({
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'albums': albums.map((a) => a.toJson()).toList(),
      'songs': songs.map((s) => s.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}
