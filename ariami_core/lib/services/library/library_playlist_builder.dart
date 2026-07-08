import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/album_grouping.dart';
import 'package:ariami_core/services/library/m3u_playlist_parser.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:ariami_core/services/library/natural_path_order.dart';

typedef SongIdGenerator = String Function(String filePath);

/// Rebuilds [LibraryStructure] with folder playlists, mirroring full-scan behavior.
LibraryStructure buildLibraryWithPlaylists({
  required List<SongMetadata> allSongs,
  required List<FolderPlaylist> existingPlaylists,
  SongIdGenerator? generateSongId,
  Map<String, String>? duplicateToOriginalPath,
}) {
  final songIdForPath = generateSongId ?? defaultGenerateSongId;
  final duplicateMap = duplicateToOriginalPath ?? const <String, String>{};

  // M3U playlists are only (re)parsed during a full scan — the folder watcher
  // ignores non-audio files. Incremental rebuilds carry them through, only
  // dropping entries whose songs left the library.
  final m3uPlaylists = existingPlaylists
      .where((playlist) => M3uPlaylistParser.isM3uFile(playlist.folderPath))
      .toList();
  final folderBasedPlaylists = existingPlaylists
      .where((playlist) => !M3uPlaylistParser.isM3uFile(playlist.folderPath))
      .toList();

  final playlistFolders = buildPlaylistFolderMap(
    songs: allSongs,
    existingPlaylists: folderBasedPlaylists,
    duplicateFilePaths: duplicateMap.keys,
  );

  // Playlist membership is additive: songs inside [PLAYLIST] folders still
  // participate in normal album grouping (or become standalone) like any
  // other track. The one exception: album tags that are downloader
  // artifacts (a playlist name written into the album field) — those
  // tracks stay standalone. See [suspiciousPlaylistAlbumTagPaths].
  final suspiciousTagPaths = suspiciousPlaylistAlbumTagPaths(
    songs: allSongs,
    playlistFolders: playlistFolders,
  );
  final albumCandidateSongs = allSongs
      .where((song) => !suspiciousTagPaths.contains(song.filePath))
      .toList();
  final suppressedAlbumSongs = allSongs
      .where((song) => suspiciousTagPaths.contains(song.filePath))
      .toList();

  final baseLibrary = AlbumBuilder().buildLibrary(albumCandidateSongs);

  final folderPlaylistsList = <FolderPlaylist>[];
  for (final entry in playlistFolders.entries) {
    final folderPath = entry.key;
    final filePaths = entry.value;

    if (filePaths.isEmpty) {
      continue;
    }

    final sortedPaths = List<String>.from(filePaths)
      ..sort(compareNaturalPath);
    final songIds = sortedPaths.map((filePath) {
      final originalPath = duplicateMap[filePath] ?? filePath;
      return songIdForPath(originalPath);
    }).toList();

    folderPlaylistsList.add(
      FolderPlaylist(
        id: FolderPlaylist.generateId(folderPath),
        name: FolderPlaylist.extractName(path.basename(folderPath)),
        folderPath: folderPath,
        songIds: songIds,
      ),
    );
  }

  final liveSongIds = <String>{
    for (final song in allSongs) songIdForPath(song.filePath),
  };
  for (final playlist in m3uPlaylists) {
    final survivingIds = playlist.songIds
        .where(liveSongIds.contains)
        .toList(growable: false);
    if (survivingIds.isEmpty) continue;
    folderPlaylistsList.add(
      FolderPlaylist(
        id: playlist.id,
        name: playlist.name,
        folderPath: playlist.folderPath,
        songIds: survivingIds,
      ),
    );
  }

  folderPlaylistsList.sort((a, b) => a.folderPath.compareTo(b.folderPath));

  return LibraryStructure(
    albums: baseLibrary.albums,
    standaloneSongs: <SongMetadata>[
      ...baseLibrary.standaloneSongs,
      ...suppressedAlbumSongs,
    ],
    folderPlaylists: folderPlaylistsList,
    duplicateToOriginalPath: duplicateMap,
  );
}

/// File paths inside playlist folders whose album tag is a downloader
/// artifact (a playlist name written into every track's album field) rather
/// than a real album. Grouping on it would shatter the folder into fake
/// per-artist "albums" all carrying the same name, so these tracks are kept
/// out of album grouping (they remain standalone and in the playlist).
///
/// Signals, any one suffices:
/// 1. The album tag equals the playlist's own display name
///    (case-insensitive).
/// 2. The album tag *contains* the playlist's display name once both are
///    normalized to letters/digits — catches prefixed artifacts like
///    `album="AIENP's Elvis' Playlist"` in `[PLAYLIST] Elvis Playlist`.
///    Only applied when the normalized playlist name is at least 8
///    characters, so a short folder like `[PLAYLIST] Elvis` can never
///    swallow a real album such as "Elvis' Golden Records".
/// 3. Within one playlist folder, the same album tag is shared by tracks
///    from 3+ different album-grouping artists. Real albums have one
///    grouping artist and real compilations share a single "Various
///    Artists" album artist, so neither is affected — but a renamed
///    playlist folder full of `album=<original playlist name>` files
///    (each with its own album artist) is caught.
Set<String> suspiciousPlaylistAlbumTagPaths({
  required List<SongMetadata> songs,
  required Map<String, List<String>> playlistFolders,
}) {
  if (playlistFolders.isEmpty) return const <String>{};

  const int minArtistsForArtifact = 3;
  const int minNameLengthForContainment = 8;

  final folderByFile = <String, String>{};
  final displayNameByFolder = <String, String>{};
  for (final entry in playlistFolders.entries) {
    displayNameByFolder[entry.key] =
        FolderPlaylist.extractName(path.basename(entry.key))
            .trim()
            .toLowerCase();
    for (final filePath in entry.value) {
      folderByFile[filePath] = entry.key;
    }
  }

  // Group playlist-folder tracks by (folder, normalized album tag).
  final groupsByFolderAndAlbum = <String, Map<String, List<SongMetadata>>>{};
  for (final song in songs) {
    final folder = folderByFile[song.filePath];
    if (folder == null) continue;
    final albumTag = normalizeAlbumTitle(song.album)?.toLowerCase();
    if (albumTag == null) continue;
    groupsByFolderAndAlbum
        .putIfAbsent(folder, () => {})
        .putIfAbsent(albumTag, () => [])
        .add(song);
  }

  // Letters/digits only (any script), so "Elvis' Playlist" ~ "Elvis Playlist".
  String normalizeForContainment(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  final matches = <String>{};
  groupsByFolderAndAlbum.forEach((folder, albumGroups) {
    final displayName = displayNameByFolder[folder] ?? '';
    final normalizedName = normalizeForContainment(displayName);

    albumGroups.forEach((albumTag, groupSongs) {
      final matchesPlaylistName = albumTag == displayName;

      final containsPlaylistName =
          normalizedName.length >= minNameLengthForContainment &&
              normalizeForContainment(albumTag).contains(normalizedName);

      final groupingArtists = <String>{
        for (final song in groupSongs)
          if (albumGroupingArtist(song) case final String artist)
            artist.toLowerCase(),
      };
      final spansManyArtists =
          groupingArtists.length >= minArtistsForArtifact;

      if (matchesPlaylistName || containsPlaylistName || spansManyArtists) {
        matches.addAll(groupSongs.map((song) => song.filePath));
      }
    });
  });
  return matches;
}

/// Async variant that also detects embedded album artwork after rebuild.
Future<LibraryStructure> buildLibraryWithPlaylistsAsync({
  required List<SongMetadata> allSongs,
  required List<FolderPlaylist> existingPlaylists,
  SongIdGenerator? generateSongId,
  Map<String, String>? duplicateToOriginalPath,
  MetadataExtractor? metadataExtractor,
}) async {
  final structure = buildLibraryWithPlaylists(
    allSongs: allSongs,
    existingPlaylists: existingPlaylists,
    generateSongId: generateSongId,
    duplicateToOriginalPath: duplicateToOriginalPath,
  );

  final enrichedAlbums = await AlbumBuilder.enrichAlbumsWithEmbeddedArtwork(
    structure.albums,
    metadataExtractor ?? MetadataExtractor(),
  );

  return LibraryStructure(
    albums: enrichedAlbums,
    standaloneSongs: structure.standaloneSongs,
    folderPlaylists: structure.folderPlaylists,
    duplicateToOriginalPath: structure.duplicateToOriginalPath,
  );
}

/// Builds playlist folder path -> audio file paths from songs and known folders.
///
/// [duplicateFilePaths] are files that were filtered out as duplicates but
/// still live inside playlist folders on disk; they keep their playlist
/// membership (their song IDs are remapped to the surviving copy later).
Map<String, List<String>> buildPlaylistFolderMap({
  required List<SongMetadata> songs,
  required Iterable<FolderPlaylist> existingPlaylists,
  Iterable<String> duplicateFilePaths = const <String>[],
}) {
  final folderPaths = <String>{
    for (final playlist in existingPlaylists) playlist.folderPath,
  };

  final memberFilePaths = <String>[
    for (final song in songs) song.filePath,
    ...duplicateFilePaths,
  ];

  for (final filePath in memberFilePaths) {
    final playlistPath = detectPlaylistFolderPath(filePath);
    if (playlistPath != null) {
      folderPaths.add(playlistPath);
    }
  }

  final topLevelPaths = folderPaths.where((candidate) {
    return !folderPaths.any(
      (other) =>
          other != candidate &&
          candidate.startsWith('$other${Platform.pathSeparator}'),
    );
  }).toList()
    ..sort();

  final playlistFolders = {
    for (final folderPath in topLevelPaths) folderPath: <String>[],
  };

  for (final filePath in memberFilePaths) {
    for (final folderPath in topLevelPaths) {
      if (filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
        playlistFolders[folderPath]!.add(filePath);
        break;
      }
    }
  }

  return playlistFolders;
}

/// Returns the nearest ancestor folder whose name starts with `[PLAYLIST]`.
String? detectPlaylistFolderPath(String filePath) {
  var directoryPath = path.dirname(filePath);
  final rootPrefix = Platform.isWindows ? '' : '/';

  while (directoryPath.isNotEmpty && directoryPath != rootPrefix) {
    if (FolderPlaylist.isPlaylistFolder(path.basename(directoryPath))) {
      return directoryPath;
    }

    final parentPath = path.dirname(directoryPath);
    if (parentPath == directoryPath) {
      break;
    }
    directoryPath = parentPath;
  }

  return null;
}

/// Default song ID generation (matches [LibraryScannerIsolate] / [ChangeProcessor]).
String defaultGenerateSongId(String filePath) {
  return md5.convert(utf8.encode(filePath)).toString().substring(0, 12);
}
