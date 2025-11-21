import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../models/album.dart';
import '../../models/song_metadata.dart';
import '../../models/library_structure.dart';

/// Service for building album structures from song metadata
class AlbumBuilder {
  /// Groups songs into albums based on metadata
  ///
  /// Groups by:
  /// 1. Album name + Album Artist (preferred)
  /// 2. Album name + Artist (fallback)
  /// 3. Handles "Various Artists" compilations
  ///
  /// Returns a LibraryStructure with albums and standalone songs
  LibraryStructure buildLibrary(List<SongMetadata> songs) {
    final albumMap = <String, List<SongMetadata>>{};
    final standaloneSongs = <SongMetadata>[];

    // Group songs by album
    for (final song in songs) {
      final albumKey = _getAlbumKey(song);

      if (albumKey == null) {
        // No album info, treat as standalone
        standaloneSongs.add(song);
      } else {
        albumMap.putIfAbsent(albumKey, () => []);
        albumMap[albumKey]!.add(song);
      }
    }

    // Build albums from grouped songs
    final albums = <String, Album>{};

    for (final entry in albumMap.entries) {
      final albumSongs = entry.value;

      // Only create album if it has 2+ songs
      if (albumSongs.length >= 2) {
        final album = _buildAlbum(entry.key, albumSongs);
        albums[album.id] = album;
      } else {
        // Single song, add to standalone
        standaloneSongs.addAll(albumSongs);
      }
    }

    return LibraryStructure(
      albums: albums,
      standaloneSongs: standaloneSongs,
    );
  }

  /// Generates a unique key for grouping songs by album
  ///
  /// Priority:
  /// 1. Album + Album Artist
  /// 2. Album + Artist (fallback)
  /// 3. null if no album info
  String? _getAlbumKey(SongMetadata song) {
    final album = song.album?.trim();
    if (album == null || album.isEmpty) {
      return null;
    }

    // Prefer album artist, fallback to artist
    final artist = (song.albumArtist ?? song.artist)?.trim();
    if (artist == null || artist.isEmpty) {
      return null;
    }

    // Create a normalized key (lowercase for case-insensitive grouping)
    return '${album.toLowerCase()}|||${artist.toLowerCase()}';
  }

  /// Builds an Album object from grouped songs
  Album _buildAlbum(String key, List<SongMetadata> songs) {
    // Extract album info from first song
    final firstSong = songs.first;
    final albumTitle = firstSong.album ?? 'Unknown Album';
    final albumArtist = firstSong.albumArtist ?? firstSong.artist ?? 'Unknown Artist';

    // Determine if it's a compilation
    final isCompilation = _isCompilation(songs, albumArtist);
    final finalArtist = isCompilation ? 'Various Artists' : albumArtist;

    // Find the most common year
    final year = _getMostCommonYear(songs);

    // Use first song's file path as artwork source (artwork extracted lazily on demand)
    final artworkPath = songs.isNotEmpty ? songs.first.filePath : null;

    // Generate unique ID for the album
    final albumId = _generateAlbumId(albumTitle, finalArtist);

    return Album(
      id: albumId,
      title: albumTitle,
      artist: finalArtist,
      songs: songs,
      year: year,
      artworkPath: artworkPath,
    );
  }

  /// Determines if an album is a compilation (Various Artists)
  bool _isCompilation(List<SongMetadata> songs, String albumArtist) {
    final albumTitle = songs.first.album ?? 'Unknown';

    // Check if album artist is "Various Artists"
    if (albumArtist.toLowerCase().contains('various')) {
      print('[AlbumBuilder] "$albumTitle" -> Various Artists (albumArtist tag)');
      return true;
    }

    // Check if all songs have the same album artist
    // If they do, it's NOT a compilation (even if track artists differ due to features)
    final albumArtists = <String>{};
    for (final song in songs) {
      final songAlbumArtist = song.albumArtist?.trim().toLowerCase();
      if (songAlbumArtist != null && songAlbumArtist.isNotEmpty) {
        albumArtists.add(songAlbumArtist);
      }
    }

    // If all songs have the same album artist, it's not a compilation
    if (albumArtists.length == 1) {
      print('[AlbumBuilder] "$albumTitle" -> $albumArtist (consistent albumArtist)');
      return false;
    }

    // If album artists are inconsistent or missing, check track artists
    // Only mark as compilation if there are MANY different artists (5+)
    final artists = <String>{};
    for (final song in songs) {
      final artist = song.artist?.trim();
      if (artist != null && artist.isNotEmpty) {
        artists.add(artist.toLowerCase());
      }
    }

    final isCompilation = artists.length >= 5; // Increased threshold from 3 to 5
    if (isCompilation) {
      print('[AlbumBuilder] "$albumTitle" -> Various Artists (${artists.length} different track artists)');
      print('[AlbumBuilder]   Artists: $artists');
    } else {
      print('[AlbumBuilder] "$albumTitle" -> $albumArtist (${artists.length} track artists, not a compilation)');
    }

    return isCompilation;
  }

  /// Finds the most common year among songs
  int? _getMostCommonYear(List<SongMetadata> songs) {
    final yearCounts = <int, int>{};

    for (final song in songs) {
      if (song.year != null) {
        yearCounts[song.year!] = (yearCounts[song.year!] ?? 0) + 1;
      }
    }

    if (yearCounts.isEmpty) return null;

    // Return the year with the highest count
    return yearCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// Generates a unique ID for an album
  String _generateAlbumId(String title, String artist) {
    final input = '$title|||$artist'.toLowerCase();
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }
}
