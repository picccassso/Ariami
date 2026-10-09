import 'song_metadata.dart';

class Album {
  final String id;

  final String title;

  /// Album artist (or "Various Artists" for compilations)
  final String artist;

  final List<SongMetadata> songs;

  final int? year;

  /// Internal lazy-extraction source path (first track or sidecar file).
  final String? artworkPath;

  /// Whether embedded or sidecar artwork is known to exist for this album.
  final bool hasArtwork;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
    this.year,
    this.artworkPath,
    this.hasArtwork = false,
  });

  Album copyWith({
    String? id,
    String? title,
    String? artist,
    List<SongMetadata>? songs,
    int? year,
    String? artworkPath,
    bool? hasArtwork,
    bool clearArtworkPath = false,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      songs: songs ?? this.songs,
      year: year ?? this.year,
      artworkPath: clearArtworkPath ? null : (artworkPath ?? this.artworkPath),
      hasArtwork: hasArtwork ?? this.hasArtwork,
    );
  }

  /// Whether this album is valid (has at least 2 songs)
  bool get isValid => songs.length >= 2;

  Duration get totalDuration {
    int totalSeconds = 0;
    for (final song in songs) {
      if (song.duration != null) {
        totalSeconds += song.duration!;
      }
    }
    return Duration(seconds: totalSeconds);
  }

  int get songCount => songs.length;

  bool get isCompilation => artist.toLowerCase() == 'various artists';

  List<SongMetadata> get sortedSongs {
    final sorted = List<SongMetadata>.from(songs);
    sorted.sort((a, b) {
      final discA = a.discNumber ?? 1;
      final discB = b.discNumber ?? 1;
      if (discA != discB) {
        return discA.compareTo(discB);
      }

      final trackA = a.trackNumber ?? 9999;
      final trackB = b.trackNumber ?? 9999;
      if (trackA != trackB) {
        return trackA.compareTo(trackB);
      }

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
