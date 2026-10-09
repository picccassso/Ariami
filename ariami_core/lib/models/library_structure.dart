import 'album.dart';
import 'folder_playlist.dart';
import 'song_metadata.dart';

class LibraryStructure {
  final Map<String, Album> albums;

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

  int get totalSongs {
    int count = standaloneSongs.length;
    for (final album in albums.values) {
      count += album.songs.length;
    }
    return count;
  }

  /// Total number of valid albums (2+ songs)
  int get totalAlbums => albums.values.where((a) => a.isValid).length;

  Duration get totalDuration {
    int totalSeconds = 0;

    for (final album in albums.values) {
      totalSeconds += album.totalDuration.inSeconds;
    }

    for (final song in standaloneSongs) {
      if (song.duration != null) {
        totalSeconds += song.duration!;
      }
    }

    return Duration(seconds: totalSeconds);
  }

  int get totalPlaylists => folderPlaylists.length;

  @override
  String toString() {
    return 'LibraryStructure(albums: $totalAlbums, standalone: ${standaloneSongs.length}, playlists: $totalPlaylists, total: $totalSongs songs)';
  }
}
