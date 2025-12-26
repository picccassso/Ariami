import 'song_metadata.dart';

/// Represents an album containing multiple songs
class Album {
  /// Unique identifier for the album
  final String id;

  /// Album title
  final String title;

  /// Album artist (or "Various Artists" for compilations)
  final String artist;

  /// List of songs in this album
  final List<SongMetadata> songs;

  /// Album release year
  final int? year;

  /// Path to album artwork (if available)
  final String? artworkPath;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
    this.year,
    this.artworkPath,
  });

  /// Whether this album is valid (has at least 2 songs)
  bool get isValid => songs.length >= 2;

  /// Total duration of all songs in the album
  Duration get totalDuration {
    int totalSeconds = 0;
    for (final song in songs) {
      if (song.duration != null) {
        totalSeconds += song.duration!;
      }
    }
    return Duration(seconds: totalSeconds);
  }

  /// Number of songs in the album
  int get songCount => songs.length;

  /// Whether this is a compilation album (Various Artists)
  bool get isCompilation => artist.toLowerCase() == 'various artists';

  /// Get sorted songs by disc and track number
  List<SongMetadata> get sortedSongs {
    final sorted = List<SongMetadata>.from(songs);
    sorted.sort((a, b) {
      // First sort by disc number
      final discA = a.discNumber ?? 1;
      final discB = b.discNumber ?? 1;
      if (discA != discB) {
        return discA.compareTo(discB);
      }

      // Then sort by track number
      final trackA = a.trackNumber ?? 9999;
      final trackB = b.trackNumber ?? 9999;
      if (trackA != trackB) {
        return trackA.compareTo(trackB);
      }

      // Finally sort alphabetically by title
      final titleA = a.title ?? '';
      final titleB = b.title ?? '';
      return titleA.compareTo(titleB);
    });
    return sorted;
  }

  @override
  String toString() {
    return 'Album(title: $title, artist: $artist, songs: ${songs.length})';
  }
}
