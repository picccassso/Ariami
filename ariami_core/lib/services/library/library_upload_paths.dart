import 'dart:io';

import 'package:ariami_core/services/library/file_scanner.dart';
import 'package:path/path.dart' as p;

/// File types the library upload accepts: audio, lyrics sidecars and cover art.
const Set<String> libraryUploadExtensions = {
  ...FileScanner.supportedExtensions,
  '.lrc',
  '.txt',
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
};

/// Resolves an upload of [relativePath] into [folder] (both `/`-separated,
/// relative to [root]) to an absolute path, or null when it would escape
/// [root], touches a hidden or `..` segment, or is not an accepted file type.
String? resolveLibraryUploadTarget(
  String root,
  String folder,
  String relativePath,
) {
  List<String> segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();
  final fileSegments = segments(relativePath);
  final all = [...segments(folder), ...fileSegments];
  if (fileSegments.isEmpty ||
      all.any((s) => s.startsWith('.') || s.contains('\\'))) {
    return null;
  }
  if (!libraryUploadExtensions.contains(p.extension(all.last).toLowerCase())) {
    return null;
  }
  final target = p.joinAll([root, ...all]);
  return p.isWithin(p.canonicalize(root), p.canonicalize(target))
      ? target
      : null;
}

/// Every folder under [root] as a `/`-separated relative path, sorted, with
/// hidden folders (and anything inside them) left out.
Future<List<String>> listLibraryFolders(String root) async {
  final folders = <String>[];
  await for (final entity
      in Directory(root).list(recursive: true, followLinks: false)) {
    if (entity is! Directory) continue;
    final parts = p.split(p.relative(entity.path, from: root));
    if (parts.any((s) => s.startsWith('.'))) continue;
    folders.add(parts.join('/'));
  }
  return folders..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}
