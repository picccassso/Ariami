import 'dart:io';
import 'dart:ffi';

import 'package:ariami_core/services/catalog/catalog_migrations.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

/// Catalog database lifecycle wrapper.
class CatalogDatabase {
  CatalogDatabase({required this.databasePath});

  final String databasePath;
  Database? _database;
  static bool _sqliteOverrideConfigured = false;

  bool get isInitialized => _database != null;

  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError(
        'CatalogDatabase is not initialized. Call initialize() first.',
      );
    }

    return db;
  }

  /// Opens the database file and applies forward-only migrations.
  void initialize() {
    if (_database != null) {
      return;
    }

    _configureSqliteDynamicLibraryLoader();

    final parentDirectory = File(databasePath).parent;
    if (!parentDirectory.existsSync()) {
      parentDirectory.createSync(recursive: true);
    }

    final db = sqlite3.open(databasePath);
    try {
      CatalogMigrations.migrate(db);
      _database = db;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  void close() {
    _database?.dispose();
    _database = null;
  }

  static void _configureSqliteDynamicLibraryLoader() {
    if (!Platform.isLinux || _sqliteOverrideConfigured) {
      return;
    }

    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.linux,
      _openLinuxSqliteLibraryWithFallback,
    );
    _sqliteOverrideConfigured = true;
  }

  static DynamicLibrary _openLinuxSqliteLibraryWithFallback() {
    Object? lastError;
    for (final candidate in _linuxSqliteLibraryCandidates) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object catch (error) {
        lastError = error;
      }
    }

    throw ArgumentError(
      "Failed to load dynamic library 'libsqlite3'. "
      'Tried: ${_linuxSqliteLibraryCandidates.join(', ')}. '
      'Last error: $lastError',
    );
  }
}

const List<String> _linuxSqliteLibraryCandidates = [
  'libsqlite3.so',
  'libsqlite3.so.0',
  '/lib/aarch64-linux-gnu/libsqlite3.so.0',
  '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
  '/lib/arm-linux-gnueabihf/libsqlite3.so.0',
  '/usr/lib/arm-linux-gnueabihf/libsqlite3.so.0',
  '/lib/x86_64-linux-gnu/libsqlite3.so.0',
  '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
  '/lib/i386-linux-gnu/libsqlite3.so.0',
  '/usr/lib/i386-linux-gnu/libsqlite3.so.0',
  '/lib64/libsqlite3.so.0',
  '/usr/lib64/libsqlite3.so.0',
];
