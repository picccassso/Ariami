library;

import 'package:ariami_core/utils/format.dart';

enum CacheType {
  artwork,
  song,
}

class CacheEntry {
  final String id;
  final CacheType type;
  final String path;
  final int size; // Size in bytes
  final DateTime lastAccessed;
  final DateTime createdAt;
  final String? etag;

  CacheEntry({
    required this.id,
    required this.type,
    required this.path,
    required this.size,
    required this.lastAccessed,
    DateTime? createdAt,
    this.etag,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'path': path,
      'size': size,
      'lastAccessed': lastAccessed.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'etag': etag,
    };
  }

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
      etag: json['etag'] as String?,
    );
  }

  static CacheType _parseType(String typeString) {
    return CacheType.values.firstWhere(
      (type) => type.toString() == typeString,
      orElse: () => CacheType.artwork,
    );
  }

  CacheEntry copyWith({
    String? id,
    CacheType? type,
    String? path,
    int? size,
    DateTime? lastAccessed,
    DateTime? createdAt,
    String? etag,
  }) {
    return CacheEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      size: size ?? this.size,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      createdAt: createdAt ?? this.createdAt,
      etag: etag ?? this.etag,
    );
  }

  String getFormattedSize() => formatBytes(size);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheEntry && other.id == id && other.type == type;
  }

  @override
  int get hashCode => id.hashCode ^ type.hashCode;
}
