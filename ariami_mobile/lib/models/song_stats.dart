/// Statistics for a song's playback
class SongStats {
  final String songId;
  final int playCount;
  final Duration totalTime;
  final DateTime? firstPlayed;
  final DateTime? lastPlayed;
  final String? songTitle;
  final String? songArtist;
  final String? albumId;
  final String? album;
  final String? albumArtist;

  const SongStats({
    required this.songId,
    required this.playCount,
    required this.totalTime,
    this.firstPlayed,
    this.lastPlayed,
    this.songTitle,
    this.songArtist,
    this.albumId,
    this.album,
    this.albumArtist,
  });

  /// Format total time as "1h 20m" or "20m" (no leading zeros)
  String get formattedTime {
    final hours = totalTime.inHours;
    final minutes = totalTime.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Create from JSON
  factory SongStats.fromJson(Map<String, dynamic> json) {
    return SongStats(
      songId: json['songId'] as String,
      playCount: json['playCount'] as int? ?? 0,
      totalTime: Duration(seconds: json['totalSeconds'] as int? ?? 0),
      firstPlayed: json['firstPlayed'] != null
          ? DateTime.parse(json['firstPlayed'] as String)
          : null,
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.parse(json['lastPlayed'] as String)
          : null,
      songTitle: json['songTitle'] as String?,
      songArtist: json['songArtist'] as String?,
      albumId: json['albumId'] as String?,
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'playCount': playCount,
      'totalSeconds': totalTime.inSeconds,
      'firstPlayed': firstPlayed?.toIso8601String(),
      'lastPlayed': lastPlayed?.toIso8601String(),
      'songTitle': songTitle,
      'songArtist': songArtist,
      'albumId': albumId,
      'album': album,
      'albumArtist': albumArtist,
    };
  }

  /// Create a copy with updated fields
  SongStats copyWith({
    String? songId,
    int? playCount,
    Duration? totalTime,
    DateTime? firstPlayed,
    DateTime? lastPlayed,
    String? songTitle,
    String? songArtist,
    String? albumId,
    String? album,
    String? albumArtist,
  }) {
    return SongStats(
      songId: songId ?? this.songId,
      playCount: playCount ?? this.playCount,
      totalTime: totalTime ?? this.totalTime,
      firstPlayed: firstPlayed ?? this.firstPlayed,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      songTitle: songTitle ?? this.songTitle,
      songArtist: songArtist ?? this.songArtist,
      albumId: albumId ?? this.albumId,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SongStats && other.songId == songId;
  }

  @override
  int get hashCode => songId.hashCode;
}
