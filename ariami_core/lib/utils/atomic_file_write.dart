import 'dart:io';

import 'secure_file_permissions.dart';

/// Writes [contents] to `$filePath.tmp` and renames it over [filePath] so a
/// crash mid-write never leaves a torn file. [flush] forces the bytes to disk
/// first; [ownerOnly] restricts the temp file to the owner before it becomes
/// the real file (rename preserves the permissions).
Future<void> writeFileAtomically(
  String filePath,
  String contents, {
  bool flush = false,
  bool ownerOnly = false,
}) async {
  final tempFile = File('$filePath.tmp');
  await tempFile.writeAsString(contents, flush: flush);
  if (ownerOnly) await SecureFilePermissions.restrictFile(tempFile.path);
  await tempFile.rename(filePath);
}
