import 'dart:convert';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_task.dart';

/// Database layer for managing downloads persistence
class DownloadDatabase {
  static const String _downloadQueueKey = 'download_queue';
  static const String _autoResumeInterruptedOnLaunchKey =
      'download_auto_resume_interrupted_on_launch';
  static const String _sqliteMigrationKey = 'download_queue_sqlite_migrated_v1';
  static const String _databaseName = 'downloads.db';
  static const int _databaseVersion = 2;
  static const String _tasksTable = 'download_tasks';

  final SharedPreferences _prefs;
  Database? _database;

  DownloadDatabase._(this._prefs);

  /// Create instance from platform.
  static Future<DownloadDatabase> create() async {
    final prefs = await SharedPreferences.getInstance();
    final database = DownloadDatabase._(prefs);
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
      onUpgrade: _onUpgrade,
    );

    await _migrateFromSharedPreferencesIfNeeded(db);
    _database = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tasksTable (
        id TEXT PRIMARY KEY,
        song_id TEXT NOT NULL,
        server_id TEXT,
        user_id TEXT,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album_id TEXT,
        album_name TEXT,
        album_artist TEXT,
        album_art TEXT NOT NULL,
        download_url TEXT NOT NULL,
        download_quality TEXT NOT NULL,
        download_original INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        track_number INTEGER,
        status TEXT NOT NULL DEFAULT 'DownloadStatus.pending',
        progress REAL NOT NULL DEFAULT 0.0,
        bytes_downloaded INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        native_backend TEXT,
        native_task_id TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_download_tasks_status ON $_tasksTable(status)',
    );
    await db.execute(
      'CREATE INDEX idx_download_tasks_server_user ON $_tasksTable(server_id, user_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db
          .execute('ALTER TABLE $_tasksTable ADD COLUMN native_backend TEXT');
      await db
          .execute('ALTER TABLE $_tasksTable ADD COLUMN native_task_id TEXT');
    }
  }

  Future<void> _migrateFromSharedPreferencesIfNeeded(Database db) async {
    if (_prefs.getBool(_sqliteMigrationKey) == true) {
      return;
    }

    final existingCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tasksTable'),
        ) ??
        0;
    if (existingCount > 0) {
      await _prefs.remove(_downloadQueueKey);
      await _prefs.setBool(_sqliteMigrationKey, true);
      return;
    }

    final legacyJsonList = _prefs.getStringList(_downloadQueueKey) ?? const [];
    if (legacyJsonList.isNotEmpty) {
      await db.transaction((txn) async {
        for (final json in legacyJsonList) {
          try {
            final task = DownloadTask.fromJson(
              jsonDecode(json) as Map<String, dynamic>,
            );
            await txn.insert(
              _tasksTable,
              _taskToRow(task),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (_) {
            // Skip malformed legacy entries.
          }
        }
      });
    }

    await _prefs.remove(_downloadQueueKey);
    await _prefs.setBool(_sqliteMigrationKey, true);
  }

  Map<String, Object?> _taskToRow(DownloadTask task) {
    return {
      'id': task.id,
      'song_id': task.songId,
      'server_id': task.serverId,
      'user_id': task.userId,
      'title': task.title,
      'artist': task.artist,
      'album_id': task.albumId,
      'album_name': task.albumName,
      'album_artist': task.albumArtist,
      'album_art': task.albumArt,
      'download_url': task.downloadUrl,
      'download_quality': task.downloadQuality.name,
      'download_original': task.downloadOriginal ? 1 : 0,
      'duration': task.duration,
      'track_number': task.trackNumber,
      'status': task.status.toString(),
      'progress': task.progress,
      'bytes_downloaded': task.bytesDownloaded,
      'total_bytes': task.totalBytes,
      'error_message': task.errorMessage,
      'retry_count': task.retryCount,
      'native_backend': task.nativeBackend,
      'native_task_id': task.nativeTaskId,
    };
  }

  DownloadTask _taskFromRow(Map<String, Object?> row) {
    return DownloadTask.fromJson({
      'id': row['id'] as String,
      'songId': row['song_id'] as String,
      'serverId': row['server_id'] as String?,
      'userId': row['user_id'] as String?,
      'title': row['title'] as String,
      'artist': row['artist'] as String,
      'albumId': row['album_id'] as String?,
      'albumName': row['album_name'] as String?,
      'albumArtist': row['album_artist'] as String?,
      'albumArt': row['album_art'] as String,
      'downloadUrl': row['download_url'] as String,
      'downloadQuality': row['download_quality'] as String,
      'downloadOriginal': (row['download_original'] as int? ?? 0) == 1,
      'duration': row['duration'] as int? ?? 0,
      'trackNumber': row['track_number'] as int?,
      'status': row['status'] as String? ?? 'DownloadStatus.pending',
      'progress': (row['progress'] as num?)?.toDouble() ?? 0.0,
      'bytesDownloaded': row['bytes_downloaded'] as int? ?? 0,
      'totalBytes': row['total_bytes'] as int? ?? 0,
      'errorMessage': row['error_message'] as String?,
      'retryCount': row['retry_count'] as int? ?? 0,
      'nativeBackend': row['native_backend'] as String?,
      'nativeTaskId': row['native_task_id'] as String?,
    });
  }

  // ============================================================================
  // QUEUE MANAGEMENT
  // ============================================================================

  /// Load all download tasks from storage.
  Future<List<DownloadTask>> loadDownloadQueue() async {
    final db = await _ensureDatabase();
    final rows = await db.query(_tasksTable, orderBy: 'id ASC');
    return rows.map(_taskFromRow).toList();
  }

  /// Insert or update a single task.
  Future<void> upsertTask(DownloadTask task) async {
    final db = await _ensureDatabase();
    await db.insert(
      _tasksTable,
      _taskToRow(task),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a task by id.
  Future<void> deleteTask(String id) async {
    final db = await _ensureDatabase();
    await db.delete(_tasksTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Clear all downloads from queue.
  Future<void> clearDownloadQueue() async {
    final db = await _ensureDatabase();
    await db.delete(_tasksTable);
    await _prefs.remove(_downloadQueueKey);
  }

  /// Clear all download data including settings.
  Future<void> clearAllDownloads() async {
    await clearDownloadQueue();
  }

  // ============================================================================
  // DOWNLOAD SETTINGS
  // ============================================================================

  /// Set WiFi-only download toggle
  Future<void> setWifiOnly(bool wifiOnly) async {
    await _prefs.setBool('download_wifi_only', wifiOnly);
  }

  /// Get WiFi-only setting
  bool getWifiOnly() {
    return _prefs.getBool('download_wifi_only') ?? true;
  }

  /// Set auto-download favorites toggle
  Future<void> setAutoDownloadFavorites(bool auto) async {
    await _prefs.setBool('download_auto_favorites', auto);
  }

  /// Get auto-download setting
  bool getAutoDownloadFavorites() {
    return _prefs.getBool('download_auto_favorites') ?? false;
  }

  /// Set storage limit in MB (null = unlimited)
  Future<void> setStorageLimit(int? limitMB) async {
    if (limitMB == null) {
      await _prefs.remove('download_storage_limit');
    } else {
      await _prefs.setInt('download_storage_limit', limitMB);
    }
  }

  /// Get storage limit in MB
  int? getStorageLimit() {
    return _prefs.getInt('download_storage_limit');
  }

  /// Set whether interrupted downloads should auto-resume on app launch.
  Future<void> setAutoResumeInterruptedOnLaunch(bool enabled) async {
    await _prefs.setBool(_autoResumeInterruptedOnLaunchKey, enabled);
  }

  /// Get whether interrupted downloads auto-resume on launch.
  bool getAutoResumeInterruptedOnLaunch() {
    return _prefs.getBool(_autoResumeInterruptedOnLaunchKey) ?? false;
  }
}
