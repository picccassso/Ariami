import 'album.dart';
import 'folder_playlist.dart';
import 'song_metadata.dart';

/// Represents the complete library structure with albums and standalone songs
class LibraryStructure {
  /// Map of album ID to Album
  final Map<String, Album> albums;

  /// List of standalone songs (not part of any album)
  final List<SongMetadata> standaloneSongs;

  /// List of folder-based playlists (from [PLAYLIST] folders)
  final List<FolderPlaylist> folderPlaylists;

  /// Maps file paths that were filtered as duplicates during the full scan
  /// to the canonical (surviving) file path. Incremental rebuilds need this
  /// so a playlist-folder copy that was deduped keeps its playlist entry
  /// pointing at the surviving song ID. In-memory only; rebuilt on rescan.
  final Map<String, String> duplicateToOriginalPath;

  const LibraryStructure({
    required this.albums,
    required this.standaloneSongs,
    this.folderPlaylists = const [],
    this.duplicateToOriginalPath = const {},
  });

  /// Total number of songs across all albums and standalone
  int get totalSongs {
    int count = standaloneSongs.length;
    for (final album in albums.values) {
      count += album.songs.length;
    }
    return count;
  }

  /// Total number of valid albums (2+ songs)
  int get totalAlbums => albums.values.where((a) => a.isValid).length;

  /// Total duration of all songs in the library
  Duration get totalDuration {
    int totalSeconds = 0;

    // Add album durations
    for (final album in albums.values) {
      totalSeconds += album.totalDuration.inSeconds;
    }

    // Add standalone song durations
    for (final song in standaloneSongs) {
      if (song.duration != null) {
        totalSeconds += song.duration!;
      }
    }

    return Duration(seconds: totalSeconds);
  }

  /// Get all albums sorted by artist, then year
  List<Album> get sortedAlbums {
    final albumList = albums.values.where((a) => a.isValid).toList();
    albumList.sort((a, b) {
      // First sort by artist
      final artistCompare = a.artist.compareTo(b.artist);
      if (artistCompare != 0) return artistCompare;

      // Then sort by year (newer first, nulls last)
      if (a.year == null && b.year == null) return 0;
      if (a.year == null) return 1;
      if (b.year == null) return -1;
      return b.year!.compareTo(a.year!);
    });
    return albumList;
  }

  /// Get standalone songs sorted by artist, then title
  List<SongMetadata> get sortedStandaloneSongs {
    final sorted = List<SongMetadata>.from(standaloneSongs);
    sorted.sort((a, b) {
      // First sort by artist
      final artistA = a.artist ?? '';
      final artistB = b.artist ?? '';
      final artistCompare = artistA.compareTo(artistB);
      if (artistCompare != 0) return artistCompare;

      // Then sort by title
      final titleA = a.title ?? '';
      final titleB = b.title ?? '';
      return titleA.compareTo(titleB);
    });
    return sorted;
  }

  /// Get all artists in the library
  Set<String> get allArtists {
    final artists = <String>{};

    // Add artists from albums
    for (final album in albums.values) {
      if (album.artist.isNotEmpty) {
        artists.add(album.artist);
      }
    }

    // Add artists from standalone songs
    for (final song in standaloneSongs) {
      if (song.artist != null && song.artist!.isNotEmpty) {
        artists.add(song.artist!);
      }
    }

    return artists;
  }

  /// Total number of folder playlists
  int get totalPlaylists => folderPlaylists.length;

  @override
  String toString() {
    return 'LibraryStructure(albums: $totalAlbums, standalone: ${standaloneSongs.length}, playlists: $totalPlaylists, total: $totalSongs songs)';
  }
}
