/// Statistics for an artist's playback (aggregated from songs)
class ArtistStats {
  final String artistName;
  final int playCount;
  final Duration totalTime;
  final DateTime? firstPlayed;
  final DateTime? lastPlayed;
  final String? randomAlbumId; // For displaying artwork
  final int uniqueSongsCount;

  const ArtistStats({
    required this.artistName,
    required this.playCount,
    required this.totalTime,
    this.firstPlayed,
    this.lastPlayed,
    this.randomAlbumId,
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
  ArtistStats copyWith({
    String? artistName,
    int? playCount,
    Duration? totalTime,
    DateTime? firstPlayed,
    DateTime? lastPlayed,
    String? randomAlbumId,
    int? uniqueSongsCount,
  }) {
    return ArtistStats(
      artistName: artistName ?? this.artistName,
      playCount: playCount ?? this.playCount,
      totalTime: totalTime ?? this.totalTime,
      firstPlayed: firstPlayed ?? this.firstPlayed,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      randomAlbumId: randomAlbumId ?? this.randomAlbumId,
      uniqueSongsCount: uniqueSongsCount ?? this.uniqueSongsCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArtistStats && other.artistName == artistName;
  }

  @override
  int get hashCode => artistName.hashCode;
}
