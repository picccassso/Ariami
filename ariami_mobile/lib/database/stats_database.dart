import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/song_stats.dart';

/// SQLite database layer for managing streaming statistics persistence
class StatsDatabase {
  static const String _databaseName = 'streaming_stats.db';
  static const int _databaseVersion = 2;
  static const String _tableName = 'song_stats';

  Database? _database;

  /// Get database instance (lazy initialization)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        song_id TEXT PRIMARY KEY,
        song_title TEXT,
        song_artist TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        total_seconds INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        album_id TEXT,
        album TEXT,
        album_artist TEXT
      )
    ''');

    // Create index for sorting by play count
    await db.execute('''
      CREATE INDEX idx_play_count ON $_tableName (play_count DESC)
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add album columns for version 2
      await db.execute('ALTER TABLE $_tableName ADD COLUMN album_id TEXT');
      await db.execute('ALTER TABLE $_tableName ADD COLUMN album TEXT');
      await db.execute('ALTER TABLE $_tableName ADD COLUMN album_artist TEXT');
      print('[StatsDatabase] Migrated to version 2: Added album columns');
    }
  }

  /// Create instance from platform
  static Future<StatsDatabase> create() async {
    final db = StatsDatabase();
    await db.database; // Initialize database
    return db;
  }

  // ============================================================================
  // SONG STATS MANAGEMENT
  // ============================================================================

  /// Save or update stats for a single song (upsert with transaction)
  Future<void> saveSongStats(SongStats stats) async {
    final db = await database;

    try {
      await db.insert(
        _tableName,
        {
          'song_id': stats.songId,
          'song_title': stats.songTitle,
          'song_artist': stats.songArtist,
          'play_count': stats.playCount,
          'total_seconds': stats.totalTime.inSeconds,
          'first_played': stats.firstPlayed?.millisecondsSinceEpoch,
          'last_played': stats.lastPlayed?.millisecondsSinceEpoch,
          'album_id': stats.albumId,
          'album': stats.album,
          'album_artist': stats.albumArtist,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Log error but don't throw - graceful degradation
      print('Error saving song stats: $e');
    }
  }

  /// Save multiple stats at once (batch operation with transaction)
  Future<void> saveAllStats(List<SongStats> statsList) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final batch = txn.batch();

        for (final stats in statsList) {
          batch.insert(
            _tableName,
            {
              'song_id': stats.songId,
              'song_title': stats.songTitle,
              'song_artist': stats.songArtist,
              'play_count': stats.playCount,
              'total_seconds': stats.totalTime.inSeconds,
              'first_played': stats.firstPlayed?.millisecondsSinceEpoch,
              'last_played': stats.lastPlayed?.millisecondsSinceEpoch,
              'album_id': stats.albumId,
              'album': stats.album,
              'album_artist': stats.albumArtist,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        await batch.commit(noResult: true);
      });
    } catch (e) {
      print('Error saving all stats: $e');
    }
  }

  /// Get stats for a single song (returns null if not found)
  Future<SongStats?> getSongStats(String songId) async {
    final db = await database;

    try {
      final results = await db.query(
        _tableName,
        where: 'song_id = ?',
        whereArgs: [songId],
        limit: 1,
      );

      if (results.isEmpty) return null;
      return _songStatsFromMap(results.first);
    } catch (e) {
      print('Error getting song stats: $e');
      return null;
    }
  }

  /// Get all songs with stats (only songs with play_count > 0)
  Future<List<SongStats>> getAllStats() async {
    final db = await database;

    try {
      final results = await db.query(
        _tableName,
        where: 'play_count > 0',
        orderBy: 'play_count DESC',
      );

      return results.map(_songStatsFromMap).toList();
    } catch (e) {
      print('Error getting all stats: $e');
      return [];
    }
  }

  /// Get top songs by play count (limited to top N)
  Future<List<SongStats>> getTopSongs({int limit = 20}) async {
    final db = await database;

    try {
      final results = await db.query(
        _tableName,
        where: 'play_count > 0',
        orderBy: 'play_count DESC',
        limit: limit,
      );

      return results.map(_songStatsFromMap).toList();
    } catch (e) {
      print('Error getting top songs: $e');
      return [];
    }
  }

  /// Get total stats across all songs (aggregate query)
  Future<({int totalSongsPlayed, Duration totalTimeStreamed})> getTotalStats() async {
    final db = await database;

    try {
      final result = await db.rawQuery('''
        SELECT
          COUNT(*) as song_count,
          SUM(total_seconds) as total_seconds
        FROM $_tableName
        WHERE play_count > 0
      ''');

      if (result.isEmpty) {
        return (totalSongsPlayed: 0, totalTimeStreamed: Duration.zero);
      }

      final row = result.first;
      final songCount = row['song_count'] as int? ?? 0;
      final totalSeconds = row['total_seconds'] as int? ?? 0;

      return (
        totalSongsPlayed: songCount,
        totalTimeStreamed: Duration(seconds: totalSeconds),
      );
    } catch (e) {
      print('Error getting total stats: $e');
      return (totalSongsPlayed: 0, totalTimeStreamed: Duration.zero);
    }
  }

  /// Get average listening time per day (calendar days since first use)
  Future<Duration> getAverageDailyTime() async {
    final total = await getTotalStats();
    if (total.totalSongsPlayed == 0) return Duration.zero;

    final dateRange = await getDateRange();
    if (dateRange.firstPlayed == null || dateRange.lastPlayed == null) {
      // Fallback: no date data available
      return Duration.zero;
    }

    // Calculate days between first and last play (inclusive)
    final daysSinceStart = dateRange.lastPlayed!.difference(dateRange.firstPlayed!).inDays + 1;

    // Prevent division by zero
    if (daysSinceStart <= 0) return total.totalTimeStreamed;

    // Use regular division for precision, round to nearest second
    final avgSeconds = (total.totalTimeStreamed.inSeconds / daysSinceStart).round();
    return Duration(seconds: avgSeconds);
  }

  /// Get date range of listening activity (earliest to latest play)
  Future<({DateTime? firstPlayed, DateTime? lastPlayed})> getDateRange() async {
    final db = await database;

    try {
      final result = await db.rawQuery('''
        SELECT
          MIN(first_played) as earliest,
          MAX(last_played) as latest
        FROM $_tableName
        WHERE play_count > 0 AND first_played IS NOT NULL AND last_played IS NOT NULL
      ''');

      if (result.isEmpty || result.first['earliest'] == null) {
        return (firstPlayed: null, lastPlayed: null);
      }

      final row = result.first;
      return (
        firstPlayed: DateTime.fromMillisecondsSinceEpoch(row['earliest'] as int),
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(row['latest'] as int),
      );
    } catch (e) {
      print('Error getting date range: $e');
      return (firstPlayed: null, lastPlayed: null);
    }
  }

  /// Count number of unique days where music was played
  Future<int> getActiveDaysCount() async {
    final db = await database;

    try {
      final result = await db.rawQuery('''
        SELECT COUNT(DISTINCT DATE(last_played / 1000, 'unixepoch')) as active_days
        FROM $_tableName
        WHERE play_count > 0 AND last_played IS NOT NULL
      ''');

      if (result.isEmpty) return 0;
      return result.first['active_days'] as int? ?? 0;
    } catch (e) {
      print('Error counting active days: $e');
      return 0;
    }
  }

  /// Reset all statistics (delete all records)
  Future<void> resetAllStats() async {
    final db = await database;

    try {
      await db.delete(_tableName);
    } catch (e) {
      print('Error resetting all stats: $e');
    }
  }

  /// Delete stats for a single song
  Future<void> deleteSongStats(String songId) async {
    final db = await database;

    try {
      await db.delete(
        _tableName,
        where: 'song_id = ?',
        whereArgs: [songId],
      );
    } catch (e) {
      print('Error deleting song stats: $e');
    }
  }

  /// Check if a song has been played
  Future<bool> hasBeenPlayed(String songId) async {
    final stats = await getSongStats(songId);
    return stats != null && stats.playCount > 0;
  }

  /// Close database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Convert database map to SongStats object
  SongStats _songStatsFromMap(Map<String, dynamic> map) {
    return SongStats(
      songId: map['song_id'] as String,
      playCount: map['play_count'] as int? ?? 0,
      totalTime: Duration(seconds: map['total_seconds'] as int? ?? 0),
      firstPlayed: map['first_played'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['first_played'] as int)
          : null,
      lastPlayed: map['last_played'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int)
          : null,
      songTitle: map['song_title'] as String?,
      songArtist: map['song_artist'] as String?,
      albumId: map['album_id'] as String?,
      album: map['album'] as String?,
      albumArtist: map['album_artist'] as String?,
    );
  }
}
