import 'dart:io';

import 'package:path/path.dart' as p;

/// Error codes returned when validating a music folder path.
enum MusicFolderPathError {
  empty,
  missing,
  permissionDenied,
  notDirectory,
}

/// Result of validating a single music folder candidate path.
class MusicFolderPathValidation {
  const MusicFolderPathValidation({
    required this.path,
    required this.exists,
    required this.readable,
    this.error,
  });

  final String path;
  final bool exists;
  final bool readable;
  final MusicFolderPathError? error;

  bool get isValid => exists && readable && error == null;

  String? get errorCode => error?.name;

  String get message {
    switch (error) {
      case MusicFolderPathError.empty:
        return 'Path is required';
      case MusicFolderPathError.missing:
        return 'Path does not exist on the server';
      case MusicFolderPathError.permissionDenied:
        return 'Permission denied: cannot read this folder';
      case MusicFolderPathError.notDirectory:
        return 'Path is not a directory';
      case null:
        return readable ? 'Folder is accessible' : 'Folder is not accessible';
    }
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'exists': exists,
        'readable': readable,
        if (error != null) 'error': error!.name,
        'message': message,
        'isValid': isValid,
      };
}

/// Builds common music-folder candidates and validates directory access.
class MusicFolderPathHelper {
  MusicFolderPathHelper._();

  static String? get _homeDirectory =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  static String? get _username =>
      Platform.environment['USER'] ?? Platform.environment['USERNAME'];

  /// Build ordered, de-duplicated candidate paths for music library setup.
  static List<String> buildCandidatePaths({
    String? configuredPath,
    String? username,
    String? homeDirectory,
  }) {
    final home = homeDirectory ?? _homeDirectory;
    final user = username ?? _username;
    final candidates = <String>[];

    void addCandidate(String? candidate) {
      if (candidate == null || candidate.trim().isEmpty) {
        return;
      }
      final normalized = p.normalize(candidate.trim());
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    addCandidate(configuredPath);
    if (home != null) {
      addCandidate(p.join(home, 'Music'));
    }
    if (user != null) {
      addCandidate('/home/$user/Music');
      addCandidate('/media/$user');
    }
    addCandidate('/mnt');
    addCandidate('/media');
    addCandidate('/srv/music');

    return candidates;
  }

  /// Validate that [path] exists, is a directory, and is readable.
  static Future<MusicFolderPathValidation> validate(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return const MusicFolderPathValidation(
        path: '',
        exists: false,
        readable: false,
        error: MusicFolderPathError.empty,
      );
    }

    try {
      final entityType =
          await FileSystemEntity.type(trimmed, followLinks: false);
      if (entityType == FileSystemEntityType.notFound) {
        return MusicFolderPathValidation(
          path: trimmed,
          exists: false,
          readable: false,
          error: MusicFolderPathError.missing,
        );
      }

      if (entityType != FileSystemEntityType.directory) {
        return MusicFolderPathValidation(
          path: trimmed,
          exists: true,
          readable: false,
          error: MusicFolderPathError.notDirectory,
        );
      }

      final dir = Directory(trimmed);
      try {
        await dir.list(followLinks: false).take(1).toList();
        return MusicFolderPathValidation(
          path: trimmed,
          exists: true,
          readable: true,
        );
      } on FileSystemException catch (e) {
        if (_isPermissionDenied(e)) {
          return MusicFolderPathValidation(
            path: trimmed,
            exists: true,
            readable: false,
            error: MusicFolderPathError.permissionDenied,
          );
        }
        rethrow;
      }
    } on FileSystemException catch (e) {
      if (_isPermissionDenied(e)) {
        return MusicFolderPathValidation(
          path: trimmed,
          exists: true,
          readable: false,
          error: MusicFolderPathError.permissionDenied,
        );
      }
      return MusicFolderPathValidation(
        path: trimmed,
        exists: false,
        readable: false,
        error: MusicFolderPathError.missing,
      );
    }
  }

  static Future<List<MusicFolderPathValidation>> validateCandidates(
    List<String> candidates,
  ) async {
    final results = <MusicFolderPathValidation>[];
    for (final candidate in candidates) {
      results.add(await validate(candidate));
    }
    return results;
  }

  static Future<List<Map<String, dynamic>>> buildSuggestionPayload({
    String? configuredPath,
    String? username,
    String? homeDirectory,
  }) async {
    final candidates = buildCandidatePaths(
      configuredPath: configuredPath,
      username: username,
      homeDirectory: homeDirectory,
    );
    final validations = await validateCandidates(candidates);
    return validations.map((result) => result.toJson()).toList();
  }

  static bool _isPermissionDenied(FileSystemException exception) {
    final osError = exception.osError;
    if (osError == null) {
      return false;
    }

    if (osError.errorCode == 13 || osError.errorCode == 1) {
      return true;
    }

    final message = osError.message.toLowerCase();
    return message.contains('permission denied') ||
        message.contains('access is denied');
  }
}
