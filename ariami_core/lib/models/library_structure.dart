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

  /// Total number of folder playlists
  int get totalPlaylists => folderPlaylists.length;

  @override
  String toString() {
    return 'LibraryStructure(albums: $totalAlbums, standalone: ${standaloneSongs.length}, playlists: $totalPlaylists, total: $totalSongs songs)';
  }
}
