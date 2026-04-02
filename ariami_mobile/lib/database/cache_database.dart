import 'dart:convert';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cache_entry.dart';

/// Database layer for managing cache metadata persistence
class CacheDatabase {
  static const String _cacheEntriesKey = 'cache_entries';
  static const String _sqliteMigrationKey = 'cache_entries_sqlite_migrated_v1';
  static const String _cacheLimitKey = 'cache_limit_mb';
  static const String _cacheEnabledKey = 'cache_enabled';
  static const String _databaseName = 'cache_metadata.db';
  static const int _databaseVersion = 1;
  static const String _entriesTable = 'cache_entries';

  final SharedPreferences _prefs;
  Database? _database;

  CacheDatabase._(this._prefs);

  /// Create instance
  static Future<CacheDatabase> create() async {
    final prefs = await SharedPreferences.getInstance();
    final database = CacheDatabase._(prefs);
    await database._ensureDatabase();
    return database;
  }

  Future<Database> _ensureDatabase() async {
    if (_database != null) {
      return _database!;
    }

    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );

    await _migrateFromSharedPreferencesIfNeeded(db);
    _database = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_entriesTable (
        id TEXT NOT NULL,
        type TEXT NOT NULL,
        path TEXT NOT NULL,
        size INTEGER NOT NULL,
        last_accessed TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (id, type)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_cache_entries_type ON $_entriesTable(type)',
    );
    await db.execute(
      'CREATE INDEX idx_cache_entries_last_accessed ON $_entriesTable(last_accessed)',
    );
  }

  Future<void> _migrateFromSharedPreferencesIfNeeded(Database db) async {
    if (_prefs.getBool(_sqliteMigrationKey) == true) {
      return;
    }

    final existingCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_entriesTable'),
        ) ??
        0;
    if (existingCount > 0) {
      await _prefs.remove(_cacheEntriesKey);
      await _prefs.setBool(_sqliteMigrationKey, true);
      return;
    }

    final legacyJsonList = _prefs.getStringList(_cacheEntriesKey) ?? const [];
    if (legacyJsonList.isNotEmpty) {
      await db.transaction((txn) async {
        for (final json in legacyJsonList) {
          try {
            final entry = CacheEntry.fromJson(
              jsonDecode(json) as Map<String, dynamic>,
            );
            await txn.insert(
              _entriesTable,
              _entryToRow(entry),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (_) {
            // Skip malformed legacy entries.
          }
        }
      });
    }

    await _prefs.remove(_cacheEntriesKey);
    await _prefs.setBool(_sqliteMigrationKey, true);
  }

  Map<String, Object?> _entryToRow(CacheEntry entry) {
    return {
      'id': entry.id,
      'type': entry.type.toString(),
      'path': entry.path,
      'size': entry.size,
      'last_accessed': entry.lastAccessed.toIso8601String(),
      'created_at': entry.createdAt.toIso8601String(),
    };
  }

  CacheEntry _entryFromRow(Map<String, Object?> row) {
    return CacheEntry(
      id: row['id'] as String,
      type: _parseType(row['type'] as String),
      path: row['path'] as String,
      size: row['size'] as int? ?? 0,
      lastAccessed: DateTime.parse(row['last_accessed'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  CacheType _parseType(String typeString) {
    return CacheType.values.firstWhere(
      (type) => type.toString() == typeString,
      orElse: () => CacheType.artwork,
    );
  }

  // ============================================================================
  // CACHE ENTRIES MANAGEMENT
  // ============================================================================

  /// Load all cache entries from storage
  Future<List<CacheEntry>> loadCacheEntries() async {
    final db = await _ensureDatabase();
    final rows = await db.query(_entriesTable, orderBy: 'id ASC');
    return rows.map(_entryFromRow).toList();
  }

  /// Get a single cache entry by ID and type
  Future<CacheEntry?> getCacheEntry(String id, CacheType type) async {
    final db = await _ensureDatabase();
    final rows = await db.query(
      _entriesTable,
      where: 'id = ? AND type = ?',
      whereArgs: [id, type.toString()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryFromRow(rows.first);
  }

  /// Add or update a cache entry
  Future<void> upsertCacheEntry(CacheEntry entry) async {
    final db = await _ensureDatabase();
    await db.insert(
      _entriesTable,
      _entryToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove a cache entry
  Future<void> removeCacheEntry(String id, CacheType type) async {
    final db = await _ensureDatabase();
    await db.delete(
      _entriesTable,
      where: 'id = ? AND type = ?',
      whereArgs: [id, type.toString()],
    );
  }

  /// Update last accessed time for an entry
  Future<void> touchCacheEntry(String id, CacheType type) async {
    final db = await _ensureDatabase();
    await db.update(
      _entriesTable,
      {'last_accessed': DateTime.now().toIso8601String()},
      where: 'id = ? AND type = ?',
      whereArgs: [id, type.toString()],
    );
  }

  /// Get entries sorted by last accessed time (oldest first) for LRU eviction
  Future<List<CacheEntry>> getEntriesForEviction() async {
    final db = await _ensureDatabase();
    final rows = await db.query(
      _entriesTable,
      orderBy: 'last_accessed ASC',
    );
    return rows.map(_entryFromRow).toList();
  }

  /// Get all entries of a specific type
  Future<List<CacheEntry>> getEntriesByType(CacheType type) async {
    final db = await _ensureDatabase();
    final rows = await db.query(
      _entriesTable,
      where: 'type = ?',
      whereArgs: [type.toString()],
      orderBy: 'last_accessed ASC',
    );
    return rows.map(_entryFromRow).toList();
  }

  /// Clear all cache entries
  Future<void> clearAllCacheEntries() async {
    final db = await _ensureDatabase();
    await db.delete(_entriesTable);
    await _prefs.remove(_cacheEntriesKey);
  }

  /// Clear entries of a specific type
  Future<void> clearEntriesByType(CacheType type) async {
    final db = await _ensureDatabase();
    await db.delete(
      _entriesTable,
      where: 'type = ?',
      whereArgs: [type.toString()],
    );
  }

  // ============================================================================
  // CACHE STATISTICS
  // ============================================================================

  /// Get total cache size in bytes
  Future<int> getTotalCacheSize() async {
    final db = await _ensureDatabase();
    final rows =
        await db.rawQuery('SELECT COALESCE(SUM(size), 0) AS total FROM $_entriesTable');
    return (rows.first['total'] as int?) ?? 0;
  }

  /// Get cache size by type in bytes
  Future<int> getCacheSizeByType(CacheType type) async {
    final db = await _ensureDatabase();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(size), 0) AS total FROM $_entriesTable WHERE type = ?',
      [type.toString()],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  /// Get total cache size in MB
  Future<double> getTotalCacheSizeMB() async {
    final bytes = await getTotalCacheSize();
    return bytes / (1024 * 1024);
  }

  /// Get count of cached items
  Future<int> getCacheCount() async {
    final db = await _ensureDatabase();
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $_entriesTable');
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Get count by type
  Future<int> getCacheCountByType(CacheType type) async {
    final db = await _ensureDatabase();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_entriesTable WHERE type = ?',
      [type.toString()],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  // ============================================================================
  // CACHE SETTINGS
  // ============================================================================

  /// Set cache limit in MB (default 500MB)
  Future<void> setCacheLimit(int limitMB) async {
    await _prefs.setInt(_cacheLimitKey, limitMB);
  }

  /// Get cache limit in MB
  int getCacheLimit() {
    return _prefs.getInt(_cacheLimitKey) ?? 500; // Default 500MB
  }

  /// Get cache limit in bytes
  int getCacheLimitBytes() {
    return getCacheLimit() * 1024 * 1024;
  }

  /// Set whether caching is enabled
  Future<void> setCacheEnabled(bool enabled) async {
    await _prefs.setBool(_cacheEnabledKey, enabled);
  }

  /// Get whether caching is enabled
  bool isCacheEnabled() {
    return _prefs.getBool(_cacheEnabledKey) ?? true; // Default enabled
  }

  // ============================================================================
  // UTILITY
  // ============================================================================

  /// Check if an item is cached
  Future<bool> isCached(String id, CacheType type) async {
    final entry = await getCacheEntry(id, type);
    return entry != null;
  }
}







