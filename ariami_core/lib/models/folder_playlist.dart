import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents a playlist derived from a [PLAYLIST] folder on the server
class FolderPlaylist {
  /// Unique identifier (MD5 hash of folder path)
  final String id;

  /// Display name (folder name without [PLAYLIST] prefix)
  final String name;

  final String folderPath;

  /// List of song IDs in this playlist (order matches folder order)
  final List<String> songIds;

  const FolderPlaylist({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.songIds,
  });

  int get songCount => songIds.length;

  bool get isEmpty => songIds.isEmpty;

  bool get isNotEmpty => songIds.isNotEmpty;

  static String generateId(String folderPath) {
    final bytes = utf8.encode(folderPath);
    final hash = md5.convert(bytes);
    return 'pl_${hash.toString().substring(0, 12)}';
  }

  /// The playlist folder marker, matched case-insensitively at the start
  /// of the folder name.
  static const String _markerPrefix = '[PLAYLIST]';

  /// Extract display name from folder name
  /// e.g., "[PLAYLIST] Summer Vibes" -> "Summer Vibes"
  static String extractName(String folderName) {
    if (isPlaylistFolder(folderName)) {
      return folderName.substring(_markerPrefix.length).trim();
    }
    return folderName;
  }

  static bool isPlaylistFolder(String folderName) =>
      folderName.toUpperCase().startsWith(_markerPrefix);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songIds': songIds,
      'songCount': songCount,
    };
  }

  factory FolderPlaylist.fromJson(Map<String, dynamic> json) {
    return FolderPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folderPath'] as String? ?? '',
      songIds: (json['songIds'] as List<dynamic>).cast<String>(),
    );
  }

  @override
  String toString() {
    return 'FolderPlaylist(name: $name, songs: $songCount)';
  }
}
