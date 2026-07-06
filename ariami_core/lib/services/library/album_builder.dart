import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/services/library/album_art_detection.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:ariami_core/services/library/album_identity.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';

/// Resolves artwork source path and whether artwork is confirmed present.
({String? artworkPath, bool hasArtwork}) resolveAlbumArtworkSources(
  List<SongMetadata> songs,
) {
  final albumDir = albumDirectoryFromSongPaths(songs.map((s) => s.filePath));
  if (albumDir != null) {
    final sidecarPath = findAlbumSidecarArtworkPath(albumDir);
    if (sidecarPath != null) {
      return (artworkPath: sidecarPath, hasArtwork: true);
    }
  }

  final lazyPath = songs.isNotEmpty ? songs.first.filePath : null;
  return (artworkPath: lazyPath, hasArtwork: false);
}

/// Service for building album structures from song metadata
class AlbumBuilder {
  AlbumBuilder({MetadataExtractor? metadataExtractor})
      : _metadataExtractor = metadataExtractor ?? MetadataExtractor();

  final MetadataExtractor _metadataExtractor;

  /// Groups songs into albums based on metadata
  ///
  /// Uses [albumGroupingKey] (album + album artist, or normalized track artist).
  /// Handles "Various Artists" compilations via [_isCompilation].
  ///
  /// Returns a LibraryStructure with albums and standalone songs
  LibraryStructure buildLibrary(List<SongMetadata> songs) {
    final albumMap = <String, List<SongMetadata>>{};
    final standaloneSongs = <SongMetadata>[];

    // Group songs by album
    for (final song in songs) {
      final albumKey = albumGroupingKey(song);

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

  /// Builds library structure and cheaply detects embedded artwork per album.
  Future<LibraryStructure> buildLibraryAsync(List<SongMetadata> songs) async {
    final structure = buildLibrary(songs);
    final enrichedAlbums = await enrichAlbumsWithEmbeddedArtwork(
      structure.albums,
      _metadataExtractor,
    );
    return LibraryStructure(
      albums: enrichedAlbums,
      standaloneSongs: structure.standaloneSongs,
      folderPlaylists: structure.folderPlaylists,
    );
  }

  /// Confirms embedded artwork for albums that only had sidecar-less lazy paths.
  static Future<Map<String, Album>> enrichAlbumsWithEmbeddedArtwork(
    Map<String, Album> albums,
    MetadataExtractor extractor,
  ) async {
    final enriched = <String, Album>{};

    for (final entry in albums.entries) {
      var album = entry.value;
      if (!album.hasArtwork) {
        for (final song in album.songs) {
          if (await extractor.hasEmbeddedArtwork(song.filePath)) {
            album = album.copyWith(
              hasArtwork: true,
              artworkPath: song.filePath,
            );
            break;
          }
        }
      }
      enriched[entry.key] = album;
    }

    return enriched;
  }

  /// Builds an Album object from grouped songs
  Album _buildAlbum(String key, List<SongMetadata> songs) {
    // Extract album info from first song
    final firstSong = songs.first;
    final albumTitle = normalizeAlbumTitle(firstSong.album) ?? 'Unknown Album';
    final albumArtist = albumGroupingArtist(firstSong) ?? 'Unknown Artist';

    // Determine if it's a compilation
    final isCompilation = _isCompilation(songs, albumArtist);
    final finalArtist = isCompilation ? 'Various Artists' : albumArtist;

    // Find the most common year
    final year = _getMostCommonYear(songs);

    final artwork = resolveAlbumArtworkSources(songs);

    // Generate unique ID for the album
    final albumId = generateAlbumId(albumTitle, finalArtist);

    return Album(
      id: albumId,
      title: albumTitle,
      artist: finalArtist,
      songs: songs,
      year: year,
      artworkPath: artwork.artworkPath,
      hasArtwork: artwork.hasArtwork,
    );
  }

  /// Determines if an album is a compilation (Various Artists)
  bool _isCompilation(List<SongMetadata> songs, String albumArtist) {
    // Check if album artist is "Various Artists"
    if (albumArtist.toLowerCase().contains('various')) {
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

    return artists.length >= 5;
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
    return yearCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}
