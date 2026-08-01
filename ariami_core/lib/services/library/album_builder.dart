import 'package:path/path.dart' as p;

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

  // Lowest path, not `songs.first`: a merged compilation's song order follows
  // file enumeration, and artwork must not change between scans.
  final lazyPath = songs.isEmpty
      ? null
      : songs
          .map((song) => song.filePath)
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  return (artworkPath: lazyPath, hasArtwork: false);
}

/// Service for building album structures from song metadata
class AlbumBuilder {
  AlbumBuilder({MetadataExtractor? metadataExtractor})
      : _metadataExtractor = metadataExtractor ?? MetadataExtractor();

  final MetadataExtractor _metadataExtractor;

  /// Groups songs into albums, in three passes of decreasing authority.
  ///
  /// 1. `[ALBUM]` folders ([detectAlbumFolderPath]) — an explicit user
  ///    override; everything under one becomes a single album, tags ignored.
  /// 2. Compilations ([_detectCompilations]) — one album title spread over
  ///    many artists in one folder. This must run *before* the per-artist
  ///    split below, or every bucket holds a single artist and
  ///    [_isCompilation] can never fire.
  /// 3. Tags — [albumGroupingKey] (album + album artist, or normalized track
  ///    artist), needing 2+ songs to form an album.
  ///
  /// Returns a LibraryStructure with albums and standalone songs
  LibraryStructure buildLibrary(List<SongMetadata> songs) {
    final albums = <String, Album>{};
    final standaloneSongs = <SongMetadata>[];

    /// Albums are keyed by [generateAlbumId], which hashes title+artist only.
    /// Two groups can legitimately land on the same identity — the two discs
    /// of one compilation, an `[ALBUM]` folder named after a tagged album —
    /// so collisions merge. Overwriting would drop the loser's songs out of
    /// the library entirely, taking their pins and listening stats with them.
    void addAlbum(Album album) {
      final existing = albums[album.id];
      albums[album.id] = existing == null
          ? album
          : existing.copyWith(songs: [...existing.songs, ...album.songs]);
    }

    // Pass 1: explicit [ALBUM] folders. The user already said "this folder is
    // one album", so neither the tags nor the 2-song minimum get a vote.
    final markedFolders = <String, List<SongMetadata>>{};
    final unmarkedSongs = <SongMetadata>[];
    for (final song in songs) {
      final folderPath = detectAlbumFolderPath(song.filePath);
      if (folderPath == null) {
        unmarkedSongs.add(song);
      } else {
        markedFolders.putIfAbsent(folderPath, () => []).add(song);
      }
    }

    for (final entry in markedFolders.entries) {
      final folderTitle = albumFolderDisplayName(p.basename(entry.key));
      final album = _buildAlbum(
        entry.value,
        titleOverride: folderTitle.isEmpty ? null : folderTitle,
      );
      addAlbum(album);
    }

    // Pass 2: compilations the tags describe as many one-artist albums.
    final compilations = _detectCompilations(unmarkedSongs);
    final compilationPaths = <String>{
      for (final group in compilations)
        for (final song in group) song.filePath,
    };
    for (final group in compilations) {
      addAlbum(_buildAlbum(group, forcedCompilation: true));
    }

    // Pass 3: ordinary tag grouping for everything left over.
    final albumMap = <String, List<SongMetadata>>{};
    for (final song in unmarkedSongs) {
      if (compilationPaths.contains(song.filePath)) continue;
      final albumKey = albumGroupingKey(song);

      if (albumKey == null) {
        // No album info, treat as standalone
        standaloneSongs.add(song);
      } else {
        albumMap.putIfAbsent(albumKey, () => []);
        albumMap[albumKey]!.add(song);
      }
    }

    for (final entry in albumMap.entries) {
      final albumSongs = entry.value;

      // Only create album if it has 2+ songs
      if (albumSongs.length >= 2) {
        addAlbum(_buildAlbum(albumSongs));
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

  /// Minimum distinct grouping artists before one shared album title reads as
  /// a compilation rather than several same-titled albums. Matches the
  /// threshold [_isCompilation] applies once songs are already grouped.
  static const int _minArtistsForCompilation = 5;

  /// Groups of tracks that are really one compilation split across artists.
  ///
  /// YouTube-sourced rips are the common case: every track carries the
  /// compilation's album tag but its *own* artist as album artist, so
  /// [albumGroupingKey] shatters a 50-track compilation into ~45 buckets and
  /// most of them fall under the 2-song minimum into standalone songs.
  ///
  /// Candidates are grouped by **containing folder plus album title**, never
  /// by title alone: a compilation is a folder of files, and matching on the
  /// title across the library would merge unrelated albums that happen to
  /// share a name (every library has more than one "Greatest Hits"). Grouping
  /// per folder also keeps the decision local — one stray file elsewhere
  /// carrying the same tag cannot silently collapse a real compilation.
  ///
  /// A folder's title group qualifies when it holds 2+ tracks spanning
  /// [_minArtistsForCompilation]+ grouping artists and never repeats a
  /// disc/track position (restarting numbering means separate albums that
  /// merely share a title). A compilation foldered as `Disc 1`/`Disc 2`
  /// yields one qualifying group per disc; both build the same album identity
  /// and are merged by `addAlbum` in [buildLibrary].
  static List<List<SongMetadata>> _detectCompilations(
    List<SongMetadata> candidates,
  ) {
    final byFolderAndTitle = <String, List<SongMetadata>>{};
    for (final song in candidates) {
      final title = normalizeAlbumTitle(song.album)?.toLowerCase();
      if (title == null) continue;
      byFolderAndTitle
          .putIfAbsent('${p.dirname(song.filePath)}|||$title', () => [])
          .add(song);
    }

    return byFolderAndTitle.values
        .where(_isCompilationGroup)
        .toList(growable: false);
  }

  static bool _isCompilationGroup(List<SongMetadata> group) {
    if (group.length < 2) return false;

    final artists = <String>{
      for (final song in group)
        if (albumGroupingArtist(song) case final String artist)
          artist.toLowerCase(),
    };
    if (artists.length < _minArtistsForCompilation) return false;

    final positions = <String>[
      for (final song in group)
        if (song.trackNumber != null)
          '${song.discNumber ?? 1}/${song.trackNumber}',
    ];
    return positions.toSet().length == positions.length;
  }

  /// Most common non-empty value, ties broken alphabetically.
  ///
  /// Album identity must not depend on file enumeration order: a group whose
  /// tags disagree (an `[ALBUM]` folder, a compilation) would otherwise pick a
  /// different title/artist per scan and churn its [generateAlbumId].
  static String? _dominantValue(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value == null || value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    final ranked = counts.entries.toList()
      ..sort((a, b) => a.value != b.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    return ranked.first.key;
  }

  /// Builds an Album object from grouped songs
  ///
  /// [titleOverride] names the album explicitly (an `[ALBUM]` folder's own
  /// name). [forcedCompilation] marks a group that [_detectCompilations]
  /// already proved spans many artists, so it does not have to clear
  /// [_isCompilation]'s raw-track-artist bar a second time.
  Album _buildAlbum(
    List<SongMetadata> songs, {
    String? titleOverride,
    bool forcedCompilation = false,
  }) {
    final albumTitle = titleOverride ??
        _dominantValue(songs.map((song) => normalizeAlbumTitle(song.album))) ??
        'Unknown Album';
    final albumArtist =
        _dominantValue(songs.map(albumGroupingArtist)) ?? 'Unknown Artist';

    // Determine if it's a compilation
    final isCompilation =
        forcedCompilation || _isCompilation(songs, albumArtist);
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

    // Most common year, earliest winning ties — a compilation spans decades,
    // and file enumeration order must not decide what clients sync.
    return yearCounts.entries
        .reduce((a, b) => a.value != b.value
            ? (a.value > b.value ? a : b)
            : (a.key <= b.key ? a : b))
        .key;
  }
}
