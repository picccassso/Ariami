/// Cache entry model for tracking cached files (artwork and songs)
library;

/// Type of cached content
enum CacheType {
  artwork,
  song,
}

/// Represents a cached file entry
class CacheEntry {
  final String id;
  final CacheType type;
  final String path;
  final int size; // Size in bytes
  final DateTime lastAccessed;
  final DateTime createdAt;

  CacheEntry({
    required this.id,
    required this.type,
    required this.path,
    required this.size,
    required this.lastAccessed,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'path': path,
      'size': size,
      'lastAccessed': lastAccessed.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      id: json['id'] as String,
      type: _parseType(json['type'] as String),
      path: json['path'] as String,
      size: json['size'] as int,
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  /// Parse type string to enum
  static CacheType _parseType(String typeString) {
    return CacheType.values.firstWhere(
      (type) => type.toString() == typeString,
      orElse: () => CacheType.artwork,
    );
  }

  /// Create a copy with updated lastAccessed time
  CacheEntry touch() {
    return CacheEntry(
      id: id,
      type: type,
      path: path,
      size: size,
      lastAccessed: DateTime.now(),
      createdAt: createdAt,
    );
  }

  /// Create a copy with updated fields
  CacheEntry copyWith({
    String? id,
    CacheType? type,
    String? path,
    int? size,
    DateTime? lastAccessed,
    DateTime? createdAt,
  }) {
    return CacheEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      size: size ?? this.size,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get formatted size string
  String getFormattedSize() {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheEntry && other.id == id && other.type == type;
  }

  @override
  int get hashCode => id.hashCode ^ type.hashCode;
}






