import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents a playlist derived from a [PLAYLIST] folder on the server
class FolderPlaylist {
  /// Unique identifier (MD5 hash of folder path)
  final String id;

  /// Display name (folder name without [PLAYLIST] prefix)
  final String name;

  /// Full path to the folder on the server
  final String folderPath;

  /// List of song IDs in this playlist (order matches folder order)
  final List<String> songIds;

  const FolderPlaylist({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.songIds,
  });

  /// Number of songs in the playlist
  int get songCount => songIds.length;

  /// Whether this playlist has any songs
  bool get isEmpty => songIds.isEmpty;

  /// Whether this playlist has songs (non-empty)
  bool get isNotEmpty => songIds.isNotEmpty;

  /// Generate a unique playlist ID from folder path
  static String generateId(String folderPath) {
    final bytes = utf8.encode(folderPath);
    final hash = md5.convert(bytes);
    return 'pl_${hash.toString().substring(0, 12)}';
  }

  /// Extract display name from folder name
  /// e.g., "[PLAYLIST] Summer Vibes" -> "Summer Vibes"
  static String extractName(String folderName) {
    const prefix = '[PLAYLIST]';
    if (folderName.startsWith(prefix)) {
      return folderName.substring(prefix.length).trim();
    }
    return folderName;
  }

  /// Check if a folder name indicates a playlist folder
  static bool isPlaylistFolder(String folderName) {
    return folderName.startsWith('[PLAYLIST]');
  }

  /// Convert to JSON for API response
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songIds': songIds,
      'songCount': songCount,
    };
  }

  /// Create from JSON (for potential future use)
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
