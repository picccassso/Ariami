import 'dart:io';

import 'package:path/path.dart' as p;

/// Common sidecar cover art filenames (case-insensitive match).
const albumSidecarArtworkNames = <String>[
  'cover.jpg',
  'cover.jpeg',
  'cover.png',
  'folder.jpg',
  'folder.jpeg',
  'folder.png',
  'albumart.jpg',
  'albumart.jpeg',
  'albumart.png',
];

/// Returns the path to a sidecar artwork file in [albumDirectory], if present.
String? findAlbumSidecarArtworkPath(String albumDirectory) {
  final dir = Directory(albumDirectory);
  if (!dir.existsSync()) {
    return null;
  }

  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path).toLowerCase();
    if (albumSidecarArtworkNames.contains(name)) {
      return entity.path;
    }
  }
  return null;
}

/// Album directory inferred from the first track path in an album.
String? albumDirectoryFromSongPaths(Iterable<String> songPaths) {
  for (final songPath in songPaths) {
    final parent = p.dirname(songPath);
    if (parent.isNotEmpty) {
      return parent;
    }
  }
  return null;
}
