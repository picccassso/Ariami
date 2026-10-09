import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Shared open/close lifecycle for the account-scoped SQLite stores: parent
/// directory, WAL pragmas, schema creation and the not-initialized guard.
abstract class SqliteStore {
  SqliteStore({required this.databasePath, required String storeName})
      : _storeName = storeName;

  final String databasePath;
  final String _storeName;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get db {
    final database = _database;
    if (database == null) {
      throw StateError('$_storeName is not initialized');
    }
    return database;
  }

  /// Creates the store's tables and indexes on a freshly opened [database].
  void createSchema(Database database);

  void initialize() {
    if (_database != null) return;
    final parent = File(databasePath).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    try {
      database.execute('PRAGMA journal_mode=WAL;');
      database.execute('PRAGMA synchronous=NORMAL;');
      database.execute('PRAGMA busy_timeout=5000;');
      createSchema(database);
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  void close() {
    _database?.close();
    _database = null;
  }
}
