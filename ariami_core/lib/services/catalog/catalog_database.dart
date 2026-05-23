import 'dart:io';

import 'package:ariami_core/services/catalog/catalog_migrations.dart';
import 'package:sqlite3/sqlite3.dart';

/// Catalog database lifecycle wrapper.
class CatalogDatabase {
  CatalogDatabase({required this.databasePath});

  final String databasePath;
  Database? _database;

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

    final parentDirectory = File(databasePath).parent;
    if (!parentDirectory.existsSync()) {
      parentDirectory.createSync(recursive: true);
    }

    final db = sqlite3.open(databasePath);
    try {
      _applyRuntimePragmas(db);
      CatalogMigrations.migrate(db);
      _database = db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _applyRuntimePragmas(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');
    db.execute('PRAGMA temp_store=MEMORY;');
    db.execute('PRAGMA busy_timeout=5000;');
    db.execute('PRAGMA cache_size=-8192;');
  }

  void close() {
    _database?.close();
    _database = null;
  }
}
