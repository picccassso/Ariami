import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// A user's decision about a suggested playlist folder.
enum PlaylistFolderDecision {
  /// Treat the folder exactly like a `[PLAYLIST]` folder on every scan.
  import,

  /// Never suggest the folder again.
  ignore,
}

/// Parses a wire value ('import' / 'ignore') into a decision, or null.
PlaylistFolderDecision? playlistFolderDecisionFromName(String? name) {
  for (final decision in PlaylistFolderDecision.values) {
    if (decision.name == name) return decision;
  }
  return null;
}

/// One persisted decision, keyed by the folder's absolute path.
class PlaylistFolderDecisionRecord {
  const PlaylistFolderDecisionRecord({
    required this.folderPath,
    required this.decision,
    required this.decidedAt,
  });

  final String folderPath;
  final PlaylistFolderDecision decision;
  final DateTime decidedAt;

  Map<String, dynamic> toJson() => {
        'folderPath': folderPath,
        'decision': decision.name,
        'decidedAt': decidedAt.toUtc().toIso8601String(),
      };

  static PlaylistFolderDecisionRecord? fromJson(Map<String, dynamic> json) {
    final folderPath = json['folderPath'];
    final decision = playlistFolderDecisionFromName(
      json['decision'] is String ? json['decision'] as String : null,
    );
    if (folderPath is! String || folderPath.trim().isEmpty ||
        decision == null) {
      return null;
    }
    final decidedAt = json['decidedAt'] is String
        ? DateTime.tryParse(json['decidedAt'] as String)
        : null;
    return PlaylistFolderDecisionRecord(
      folderPath: folderPath,
      decision: decision,
      decidedAt: (decidedAt ?? DateTime.now()).toUtc(),
    );
  }
}

/// JSON-file persistence for playlist-suggestion decisions.
///
/// Maps absolute folder path -> {decision, decidedAt}. A decision is data
/// about a *path*, not the files inside it: renaming the folder leaves the
/// old decision stale (harmlessly unmatched) and the renamed folder is
/// evaluated fresh on the next scan. See PLAYLIST_DETECTION.md.
///
/// The file lives next to the metadata cache (see
/// [LibraryManager.setCachePath]) so decisions survive restarts. A missing or
/// malformed file never breaks startup — the store just starts empty.
class PlaylistDecisionStore {
  PlaylistDecisionStore({required this.filePath});

  static const int _schemaVersion = 1;
  static const int maxFolderPathLength = 4096;

  final String filePath;

  final Map<String, PlaylistFolderDecisionRecord> _recordsByPath = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Loads decisions from disk once; later calls are no-ops.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final file = File(filePath);
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final rawDecisions = decoded['decisions'];
      if (rawDecisions is! List) return;
      for (final rawRecord in rawDecisions) {
        if (rawRecord is! Map<String, dynamic>) continue;
        final record = PlaylistFolderDecisionRecord.fromJson(rawRecord);
        if (record == null) continue;
        _recordsByPath[_normalizePath(record.folderPath)] = record;
      }
    } catch (e) {
      _recordsByPath.clear();
      print('[PlaylistDecisionStore] Failed to load $filePath: $e');
    }
  }

  /// All decisions, path-sorted for deterministic output.
  List<PlaylistFolderDecisionRecord> get decisions {
    final records = _recordsByPath.values.toList()
      ..sort((a, b) => a.folderPath.compareTo(b.folderPath));
    return records;
  }

  /// Normalized paths the user chose to import as playlists.
  Set<String> get importedFolderPaths => _pathsFor(
        PlaylistFolderDecision.import,
      );

  /// Normalized paths the user chose to never suggest again.
  Set<String> get ignoredFolderPaths => _pathsFor(
        PlaylistFolderDecision.ignore,
      );

  PlaylistFolderDecisionRecord? decisionFor(String folderPath) =>
      _recordsByPath[_normalizePath(_validateFolderPath(folderPath))];

  /// Records [decision] for [folderPath] and persists it.
  Future<PlaylistFolderDecisionRecord> setDecision(
    String folderPath,
    PlaylistFolderDecision decision,
  ) async {
    final validated = _validateFolderPath(folderPath);
    final record = PlaylistFolderDecisionRecord(
      folderPath: validated,
      decision: decision,
      decidedAt: DateTime.now().toUtc(),
    );
    _recordsByPath[_normalizePath(validated)] = record;
    await _save();
    return record;
  }

  /// Clears any decision for [folderPath] so the next scan re-evaluates it.
  ///
  /// Returns true when a decision existed.
  Future<bool> clearDecision(String folderPath) async {
    final removed = _recordsByPath.remove(
      _normalizePath(_validateFolderPath(folderPath)),
    );
    if (removed == null) return false;
    await _save();
    return true;
  }

  Set<String> _pathsFor(PlaylistFolderDecision decision) => {
        for (final entry in _recordsByPath.entries)
          if (entry.value.decision == decision) entry.key,
      };

  String _validateFolderPath(String folderPath) {
    final trimmed = folderPath.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maxFolderPathLength ||
        !path.isAbsolute(trimmed)) {
      throw ArgumentError.value(
        folderPath,
        'folderPath',
        'Must be a non-empty absolute path',
      );
    }
    return trimmed;
  }

  String _normalizePath(String folderPath) => path.normalize(folderPath);

  Future<void> _save() async {
    final file = File(filePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = jsonEncode({
      'version': _schemaVersion,
      'decisions': decisions
          .map((record) => record.toJson())
          .toList(growable: false),
    });
    // Atomic write: never leave a torn file if the process dies mid-save.
    final tempFile = File('$filePath.tmp');
    await tempFile.writeAsString(payload, flush: true);
    await tempFile.rename(filePath);
  }
}
