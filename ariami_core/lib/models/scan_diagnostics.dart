import 'package:ariami_core/models/playlist_suggestion.dart';

/// A file that could not be processed during library scan.
class ScanFailedFile {
  const ScanFailedFile({
    required this.path,
    required this.reason,
  });

  final String path;
  final String reason;

  Map<String, dynamic> toJson() => {
        'path': path,
        'reason': reason,
      };
}

/// Structured diagnostics from the most recent library scan.
class ScanDiagnostics {
  static const int maxFailedFiles = 50;
  static const int maxPlaylistSuggestions = 25;

  const ScanDiagnostics({
    this.skippedFileCount = 0,
    this.failedFiles = const [],
    this.playlistSuggestions = const [],
    this.autoImportedPlaylistFolders = const [],
  });

  final int skippedFileCount;
  final List<ScanFailedFile> failedFiles;

  /// Folders that look like playlists but have no explicit marker.
  /// Advisory only — medium confidence, awaiting a user decision.
  final List<PlaylistSuggestion> playlistSuggestions;

  /// Unmarked folders with high-confidence playlist evidence that the scan
  /// imported automatically. Informational — the playlists themselves are
  /// already in the library.
  final List<PlaylistSuggestion> autoImportedPlaylistFolders;

  Map<String, dynamic> toJson() => {
        'skippedFileCount': skippedFileCount,
        'failedFiles': failedFiles.map((f) => f.toJson()).toList(),
        'playlistSuggestions':
            playlistSuggestions.map((s) => s.toJson()).toList(),
        'autoImportedPlaylistFolders':
            autoImportedPlaylistFolders.map((s) => s.toJson()).toList(),
      };
}
