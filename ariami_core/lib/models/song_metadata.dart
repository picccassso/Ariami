/// Represents metadata extracted from an audio file
class SongMetadata {
  /// The file path of the audio file
  final String filePath;

  /// Song title
  final String? title;

  /// Primary artist
  final String? artist;

  /// Album artist (may differ from artist for compilation albums)
  final String? albumArtist;

  /// Album name
  final String? album;

  /// Release year
  final int? year;

  /// Track number within the album
  final int? trackNumber;

  /// Disc number for multi-disc albums
  final int? discNumber;

  /// Music genre
  final String? genre;

  /// Duration in seconds
  final int? duration;

  /// Bitrate in kbps
  final int? bitrate;

  /// Comment or notes
  final String? comment;

  /// Binary image data for album artwork (JPEG or PNG)
  final List<int>? albumArt;

  /// File size in bytes
  final int? fileSize;

  /// Last modified time
  final DateTime? modifiedTime;

  const SongMetadata({
    required this.filePath,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.genre,
    this.duration,
    this.bitrate,
    this.comment,
    this.albumArt,
    this.fileSize,
    this.modifiedTime,
  });

  /// Creates a copy with updated fields
  SongMetadata copyWith({
    String? filePath,
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    int? year,
    int? trackNumber,
    int? discNumber,
    String? genre,
    int? duration,
    int? bitrate,
    String? comment,
    List<int>? albumArt,
    int? fileSize,
    DateTime? modifiedTime,
  }) {
    return SongMetadata(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArtist: albumArtist ?? this.albumArtist,
      album: album ?? this.album,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      bitrate: bitrate ?? this.bitrate,
      comment: comment ?? this.comment,
      albumArt: albumArt ?? this.albumArt,
      fileSize: fileSize ?? this.fileSize,
      modifiedTime: modifiedTime ?? this.modifiedTime,
    );
  }

  /// Returns true if this metadata has complete information
  bool get isComplete {
    return title != null &&
        artist != null &&
        album != null &&
        duration != null;
  }

  /// Returns true if metadata was likely parsed from filename
  bool get isParsedFromFilename {
    return title != null && artist == null && album == null;
  }

  /// Convert to JSON map for caching
  ///
  /// Note: albumArt is excluded to keep cache size manageable.
  /// Artwork is extracted lazily on demand.
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (album != null) 'album': album,
      if (year != null) 'year': year,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (discNumber != null) 'discNumber': discNumber,
      if (genre != null) 'genre': genre,
      if (duration != null) 'duration': duration,
      if (bitrate != null) 'bitrate': bitrate,
      if (comment != null) 'comment': comment,
      if (fileSize != null) 'fileSize': fileSize,
      if (modifiedTime != null) 'modifiedTime': modifiedTime!.toIso8601String(),
    };
  }

  /// Create from JSON map
  factory SongMetadata.fromJson(Map<String, dynamic> json) {
    return SongMetadata(
      filePath: json['filePath'] as String,
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      albumArtist: json['albumArtist'] as String?,
      album: json['album'] as String?,
      year: json['year'] as int?,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
      genre: json['genre'] as String?,
      duration: json['duration'] as int?,
      bitrate: json['bitrate'] as int?,
      comment: json['comment'] as String?,
      fileSize: json['fileSize'] as int?,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.parse(json['modifiedTime'] as String)
          : null,
      // albumArt is not cached - extracted lazily
    );
  }

  @override
  String toString() {
    return 'SongMetadata(title: $title, artist: $artist, album: $album, '
        'duration: ${duration}s)';
  }
}
