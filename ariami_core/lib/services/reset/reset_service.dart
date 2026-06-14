import 'dart:io';

import 'package:path/path.dart' as p;

/// How much of Ariami's local state a reset should clear.
enum ResetScope {
  /// Clears setup/config and pairing state only. Keeps the catalog database,
  /// accounts and caches so the library does not need to be rescanned.
  setupOnly,

  /// Clears all Ariami-owned data (database, accounts, sessions, caches and
  /// setup state). Never touches the user's music files.
  factoryReset,
}

/// Outcome for a single path the reset attempted to remove.
enum ResetEntryStatus {
  /// The path existed and was removed.
  deleted,

  /// The path did not exist; nothing to do.
  skippedMissing,

  /// The path was refused because it overlapped the configured music library.
  blockedMusicGuard,

  /// Deletion was attempted but failed (see [ResetEntryResult.error]).
  failed,
}

/// Result for one path processed by [ResetService.execute].
class ResetEntryResult {
  const ResetEntryResult({
    required this.path,
    required this.status,
    this.error,
  });

  final String path;
  final ResetEntryStatus status;
  final String? error;
}

/// The explicit, Ariami-owned paths a reset is allowed to remove.
///
/// Callers must pass leaf paths only. [ResetService] never walks to a parent
/// directory and never deletes anything that is not listed here.
class ResetPlan {
  const ResetPlan({
    this.files = const [],
    this.directories = const [],
    this.musicFolderPathGuard,
  });

  /// Individual files to remove (e.g. `config.json`, `catalog.db`).
  final List<String> files;

  /// Directories to remove recursively (e.g. `artwork_cache/`).
  final List<String> directories;

  /// The configured music library path, if known. Used as a safety guard:
  /// any target equal to, containing, or contained by this path is refused.
  final String? musicFolderPathGuard;
}

/// Aggregate result of a reset run.
class ResetResult {
  const ResetResult(this.entries);

  final List<ResetEntryResult> entries;

  Iterable<ResetEntryResult> get deleted =>
      entries.where((e) => e.status == ResetEntryStatus.deleted);

  Iterable<ResetEntryResult> get failures =>
      entries.where((e) => e.status == ResetEntryStatus.failed);

  Iterable<ResetEntryResult> get blocked =>
      entries.where((e) => e.status == ResetEntryStatus.blockedMusicGuard);

  bool get hasFailures => failures.isNotEmpty;
}

/// Safely removes a fixed list of Ariami-owned paths.
///
/// Safety rules (enforced for every target):
///   - Only the explicit paths in the [ResetPlan] are ever touched. There is no
///     "delete parent folder" logic anywhere.
///   - The configured music library ([ResetPlan.musicFolderPathGuard]) is never
///     deleted: a target that equals it, is an ancestor of it, or lives inside
///     it is refused.
///   - Symlinks are deleted as links; the link target is never followed.
///   - Missing paths are skipped silently.
class ResetService {
  const ResetService();

  Future<ResetResult> execute(ResetPlan plan) async {
    final guard = _canonicalGuard(plan.musicFolderPathGuard);
    final results = <ResetEntryResult>[];
    for (final path in [...plan.files, ...plan.directories]) {
      results.add(await _deleteEntry(path, guard));
    }
    return ResetResult(results);
  }

  Future<ResetEntryResult> _deleteEntry(
    String rawPath,
    String? canonicalGuard,
  ) async {
    if (_violatesGuard(p.canonicalize(rawPath), canonicalGuard)) {
      return ResetEntryResult(
        path: rawPath,
        status: ResetEntryStatus.blockedMusicGuard,
      );
    }

    try {
      // followLinks: false so a symlink reports as a link, never as its target.
      final type = await FileSystemEntity.type(rawPath, followLinks: false);

      switch (type) {
        case FileSystemEntityType.notFound:
          return ResetEntryResult(
            path: rawPath,
            status: ResetEntryStatus.skippedMissing,
          );
        case FileSystemEntityType.link:
          // Remove the link itself only; do not follow into the target.
          await Link(rawPath).delete();
        case FileSystemEntityType.directory:
          await Directory(rawPath).delete(recursive: true);
        default:
          await File(rawPath).delete();
      }

      return ResetEntryResult(path: rawPath, status: ResetEntryStatus.deleted);
    } catch (e) {
      return ResetEntryResult(
        path: rawPath,
        status: ResetEntryStatus.failed,
        error: e.toString(),
      );
    }
  }

  /// True when [canonicalTarget] overlaps the music library guard in any way:
  /// it is the guard, an ancestor of it, or a descendant of it.
  bool _violatesGuard(String canonicalTarget, String? canonicalGuard) {
    if (canonicalGuard == null) {
      return false;
    }
    return p.equals(canonicalTarget, canonicalGuard) ||
        // guard within target => target is an ancestor of the music library.
        p.isWithin(canonicalTarget, canonicalGuard) ||
        // target within guard => target lives inside the music library.
        p.isWithin(canonicalGuard, canonicalTarget);
  }

  String? _canonicalGuard(String? guard) {
    if (guard == null || guard.trim().isEmpty) {
      return null;
    }
    return p.canonicalize(guard.trim());
  }
}
