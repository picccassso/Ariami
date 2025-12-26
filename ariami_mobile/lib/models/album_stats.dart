/// Statistics for an album's playback (aggregated from songs)
class AlbumStats {
  final String albumId;
  final String? albumName;
  final String? albumArtist;
  final int playCount;
  final Duration totalTime;
  final DateTime? firstPlayed;
  final DateTime? lastPlayed;
  final int uniqueSongsCount;

  const AlbumStats({
    required this.albumId,
    this.albumName,
    this.albumArtist,
    required this.playCount,
    required this.totalTime,
    this.firstPlayed,
    this.lastPlayed,
    required this.uniqueSongsCount,
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

  /// Create a copy with updated fields
  AlbumStats copyWith({
    String? albumId,
    String? albumName,
    String? albumArtist,
    int? playCount,
    Duration? totalTime,
    DateTime? firstPlayed,
    DateTime? lastPlayed,
    int? uniqueSongsCount,
  }) {
    return AlbumStats(
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      playCount: playCount ?? this.playCount,
      totalTime: totalTime ?? this.totalTime,
      firstPlayed: firstPlayed ?? this.firstPlayed,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      uniqueSongsCount: uniqueSongsCount ?? this.uniqueSongsCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlbumStats && other.albumId == albumId;
  }

  @override
  int get hashCode => albumId.hashCode;
}
