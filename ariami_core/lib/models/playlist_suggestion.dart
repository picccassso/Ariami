/// A folder that looks like a playlist but has no explicit marker.
///
/// Suggestions are advisory only: the scanner NEVER creates a playlist from
/// one automatically. They surface in scan diagnostics so a user (or a future
/// dashboard approval UI) can decide to import, ignore, or permanently mark
/// the folder. See PLAYLIST_DETECTION.md for the classification rules.
class PlaylistSuggestion {
  const PlaylistSuggestion({
    required this.folderPath,
    required this.name,
    required this.songCount,
    required this.artistCount,
    required this.albumCount,
    this.missingTags = false,
    this.reasons = const [],
  });

  /// Absolute path of the suggested folder.
  final String folderPath;

  /// Display name (the folder's base name).
  final String name;

  /// Number of audio files directly inside the folder.
  final int songCount;

  /// Distinct artists among the folder's tagged tracks.
  final int artistCount;

  /// Distinct album tags among the folder's tagged tracks.
  final int albumCount;

  /// True when most tracks lack tags, so the suggestion is based mainly on
  /// the folder name and needs manual review before importing.
  final bool missingTags;

  /// Human-readable signals that triggered the suggestion.
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
        'folderPath': folderPath,
        'name': name,
        'songCount': songCount,
        'artistCount': artistCount,
        'albumCount': albumCount,
        'missingTags': missingTags,
        'reasons': reasons,
      };

  factory PlaylistSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaylistSuggestion(
      folderPath: json['folderPath'] as String? ?? '',
      name: json['name'] as String? ?? '',
      songCount: json['songCount'] as int? ?? 0,
      artistCount: json['artistCount'] as int? ?? 0,
      albumCount: json['albumCount'] as int? ?? 0,
      missingTags: json['missingTags'] as bool? ?? false,
      reasons: (json['reasons'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
