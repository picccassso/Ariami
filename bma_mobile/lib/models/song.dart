/// Represents a song in the music library
class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final Duration duration;
  final String filePath;
  final int fileSize;
  final DateTime modifiedTime;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    required this.duration,
    required this.filePath,
    required this.fileSize,
    required this.modifiedTime,
  });

  /// Create from JSON
  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
      year: json['year'] as int?,
      genre: json['genre'] as String?,
      duration: Duration(milliseconds: json['duration'] as int),
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      modifiedTime: DateTime.parse(json['modifiedTime'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumArtist': albumArtist,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'year': year,
      'genre': genre,
      'duration': duration.inMilliseconds,
      'filePath': filePath,
      'fileSize': fileSize,
      'modifiedTime': modifiedTime.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    int? trackNumber,
    int? discNumber,
    int? year,
    String? genre,
    Duration? duration,
    String? filePath,
    int? fileSize,
    DateTime? modifiedTime,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      modifiedTime: modifiedTime ?? this.modifiedTime,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Song && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
