import 'dart:convert';
import 'dart:io';
import 'package:ariami_core/models/song_metadata.dart';

/// Cached metadata entry with file validation info
class CachedMetadataEntry {
  /// File modification time (milliseconds since epoch)
  final int mtime;

  /// File size in bytes
  final int size;

  /// The cached metadata
  final SongMetadata metadata;

  const CachedMetadataEntry({
    required this.mtime,
    required this.size,
    required this.metadata,
  });

  /// Create from JSON map
  factory CachedMetadataEntry.fromJson(Map<String, dynamic> json) {
    return CachedMetadataEntry(
      mtime: json['mtime'] as int,
      size: json['size'] as int,
      metadata: SongMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'mtime': mtime,
      'size': size,
      'metadata': metadata.toJson(),
    };
  }
}

/// Persistent metadata cache for fast re-scans
///
/// Stores extracted metadata on disk so subsequent scans can skip
/// unchanged files. Uses file mtime and size for validation.
class MetadataCache {
  /// Cache schema version - bump to invalidate all caches on breaking changes
  static const int schemaVersion = 1;

  /// Maximum number of entries (sanity limit ~50MB)
  static const int maxEntries = 100000;

  /// Path to the cache file
  final String cachePath;

  /// In-memory cache entries (filePath -> entry)
  final Map<String, CachedMetadataEntry> _entries = {};

  /// Whether the cache has been modified since last save
  bool _isDirty = false;

  MetadataCache(this.cachePath);

  /// Number of cached entries
  int get length => _entries.length;

  /// Check if cache has unsaved changes
  bool get isDirty => _isDirty;

  /// Load cache from disk
  ///
  /// Returns true if cache was loaded successfully, false if cache
  /// doesn't exist, is corrupted, or has wrong version.
  Future<bool> load() async {
    try {
      final file = File(cachePath);
      if (!await file.exists()) {
        print('[MetadataCache] No cache file found at $cachePath');
        return false;
      }

      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;

      // Check schema version
      final version = json['version'] as int?;
      if (version != schemaVersion) {
        print('[MetadataCache] Cache version mismatch (got $version, expected $schemaVersion) - invalidating');
        await clear();
        return false;
      }

      // Load entries
      final entriesJson = json['entries'] as Map<String, dynamic>?;
      if (entriesJson == null) {
        print('[MetadataCache] No entries in cache file');
        return false;
      }

      _entries.clear();
      for (final entry in entriesJson.entries) {
        try {
          _entries[entry.key] = CachedMetadataEntry.fromJson(
            entry.value as Map<String, dynamic>,
          );
        } catch (e) {
          // Skip corrupted entries
          print('[MetadataCache] Skipping corrupted entry: ${entry.key}');
        }
      }

      _isDirty = false;
      print('[MetadataCache] Loaded ${_entries.length} entries from cache');
      return true;
    } catch (e) {
      print('[MetadataCache] Failed to load cache: $e');
      return false;
    }
  }

  /// Save cache to disk
  Future<bool> save() async {
    if (!_isDirty && _entries.isNotEmpty) {
      print('[MetadataCache] Cache not dirty, skipping save');
      return true;
    }

    try {
      final json = {
        'version': schemaVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'entries': _entries.map((key, value) => MapEntry(key, value.toJson())),
      };

      final file = File(cachePath);

      // Ensure parent directory exists
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await file.writeAsString(jsonEncode(json));
      _isDirty = false;
      print('[MetadataCache] Saved ${_entries.length} entries to cache');
      return true;
    } catch (e) {
      print('[MetadataCache] Failed to save cache: $e');
      return false;
    }
  }

  /// Get cached metadata for a file if still valid
  ///
  /// Returns the cached metadata if:
  /// 1. Entry exists in cache
  /// 2. File mtime matches cached mtime
  /// 3. File size matches cached size
  ///
  /// Returns null if cache miss or validation fails.
  Future<SongMetadata?> get(String filePath) async {
    final entry = _entries[filePath];
    if (entry == null) return null;

    try {
      final file = File(filePath);
      final stat = await file.stat();

      // Validate mtime and size
      final currentMtime = stat.modified.millisecondsSinceEpoch;
      final currentSize = stat.size;

      if (currentMtime == entry.mtime && currentSize == entry.size) {
        return entry.metadata;
      }

      // File changed - remove stale entry
      _entries.remove(filePath);
      _isDirty = true;
      return null;
    } catch (e) {
      // File doesn't exist or can't be accessed - remove entry
      _entries.remove(filePath);
      _isDirty = true;
      return null;
    }
  }

  /// Check if a file has valid cached metadata without returning it
  ///
  /// Faster than get() when you only need to check validity.
  Future<bool> isValid(String filePath) async {
    final entry = _entries[filePath];
    if (entry == null) return false;

    try {
      final file = File(filePath);
      final stat = await file.stat();

      return stat.modified.millisecondsSinceEpoch == entry.mtime &&
          stat.size == entry.size;
    } catch (e) {
      return false;
    }
  }

  /// Store metadata in cache
  ///
  /// Automatically captures current file mtime and size.
  Future<void> put(String filePath, SongMetadata metadata) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();

      _entries[filePath] = CachedMetadataEntry(
        mtime: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
        metadata: metadata,
      );
      _isDirty = true;

      // Enforce max entries limit - remove oldest entries
      _enforceLimit();
    } catch (e) {
      // Can't stat file - don't cache
      print('[MetadataCache] Failed to cache $filePath: $e');
    }
  }

  /// Store metadata with known mtime and size (for batch operations)
  void putWithStats(String filePath, SongMetadata metadata, int mtime, int size) {
    _entries[filePath] = CachedMetadataEntry(
      mtime: mtime,
      size: size,
      metadata: metadata,
    );
    _isDirty = true;
    _enforceLimit();
  }

  /// Remove entry for a file
  void remove(String filePath) {
    if (_entries.remove(filePath) != null) {
      _isDirty = true;
    }
  }

  /// Remove entries for files that no longer exist
  Future<int> pruneDeleted() async {
    final toRemove = <String>[];

    for (final path in _entries.keys) {
      if (!await File(path).exists()) {
        toRemove.add(path);
      }
    }

    for (final path in toRemove) {
      _entries.remove(path);
    }

    if (toRemove.isNotEmpty) {
      _isDirty = true;
      print('[MetadataCache] Pruned ${toRemove.length} deleted files from cache');
    }

    return toRemove.length;
  }

  /// Clear all cached entries
  Future<void> clear() async {
    _entries.clear();
    _isDirty = true;

    // Also delete the cache file
    try {
      final file = File(cachePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('[MetadataCache] Failed to delete cache file: $e');
    }
  }

  /// Get all cached file paths
  Iterable<String> get cachedPaths => _entries.keys;

  /// Export cache data for passing to isolate (serializable format)
  Map<String, Map<String, dynamic>> exportForIsolate() {
    final data = <String, Map<String, dynamic>>{};
    for (final entry in _entries.entries) {
      data[entry.key] = {
        'mtime': entry.value.mtime,
        'size': entry.value.size,
        'metadata': entry.value.metadata.toJson(),
      };
    }
    return data;
  }

  /// Import cache data from isolate results
  void importFromIsolate(Map<String, Map<String, dynamic>> data) {
    _entries.clear();
    for (final entry in data.entries) {
      _entries[entry.key] = CachedMetadataEntry(
        mtime: entry.value['mtime'] as int,
        size: entry.value['size'] as int,
        metadata: SongMetadata.fromJson(entry.value['metadata'] as Map<String, dynamic>),
      );
    }
    _isDirty = true;
    _enforceLimit();
  }

  /// Enforce maximum entries limit
  void _enforceLimit() {
    if (_entries.length <= maxEntries) return;

    // Remove oldest entries (first entries in map)
    final keysToRemove = _entries.keys
        .take(_entries.length - maxEntries)
        .toList();

    for (final key in keysToRemove) {
      _entries.remove(key);
    }

    print('[MetadataCache] Enforced limit: removed ${keysToRemove.length} oldest entries');
  }
}
