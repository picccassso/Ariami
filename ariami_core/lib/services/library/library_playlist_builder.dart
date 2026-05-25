import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';

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

  final playlistFolders = buildPlaylistFolderMap(
    songs: allSongs,
    existingPlaylists: existingPlaylists,
  );

  final playlistFolderSongPaths =
      playlistFolders.values.expand((paths) => paths).toSet();
  final albumCandidateSongs = allSongs
      .where((song) => !playlistFolderSongPaths.contains(song.filePath))
      .toList();
  final forcedStandaloneSongs = allSongs
      .where((song) => playlistFolderSongPaths.contains(song.filePath))
      .toList();

  final baseLibrary = AlbumBuilder().buildLibrary(albumCandidateSongs);

  final folderPlaylistsList = <FolderPlaylist>[];
  for (final entry in playlistFolders.entries) {
    final folderPath = entry.key;
    final filePaths = entry.value;

    if (filePaths.isEmpty) {
      continue;
    }

    final sortedPaths = List<String>.from(filePaths)..sort();
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

  folderPlaylistsList.sort((a, b) => a.folderPath.compareTo(b.folderPath));

  return LibraryStructure(
    albums: baseLibrary.albums,
    standaloneSongs: <SongMetadata>[
      ...baseLibrary.standaloneSongs,
      ...forcedStandaloneSongs,
    ],
    folderPlaylists: folderPlaylistsList,
  );
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
  );
}

/// Builds playlist folder path -> audio file paths from songs and known folders.
Map<String, List<String>> buildPlaylistFolderMap({
  required List<SongMetadata> songs,
  required Iterable<FolderPlaylist> existingPlaylists,
}) {
  final folderPaths = <String>{
    for (final playlist in existingPlaylists) playlist.folderPath,
  };

  for (final song in songs) {
    final playlistPath = detectPlaylistFolderPath(song.filePath);
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

  for (final song in songs) {
    for (final folderPath in topLevelPaths) {
      if (song.filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
        playlistFolders[folderPath]!.add(song.filePath);
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
