import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

class PlaylistEdit {
  const PlaylistEdit({
    required this.playlistId,
    required this.name,
    required this.songIds,
    required this.baseSnapshot,
    required this.updatedAt,
    this.sourceDeviceId,
  });

  final String playlistId;
  final String? name;
  final List<String>? songIds;
  final List<String> baseSnapshot;
  final DateTime updatedAt;
  final String? sourceDeviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playlistId': playlistId,
        'name': name,
        'songIds': songIds,
        'baseSnapshot': baseSnapshot,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
      };
}

/// SQLite persistence for account-scoped server playlist edits.
///
/// The HTTP layer supplies [userId] and [sourceDeviceId] from a validated
/// session. Client payloads never select the account that is read or written.
class PlaylistEditStore {
  PlaylistEditStore({required this.databasePath});

  static const int maxPlaylistIdLength = 512;
  static const int maxSongIds = 10000;

  final String databasePath;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('PlaylistEditStore is not initialized');
    }
    return database;
  }

  void initialize() {
    if (_database != null) return;
    final parent = File(databasePath).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    try {
      database.execute('PRAGMA journal_mode=WAL;');
      database.execute('PRAGMA synchronous=NORMAL;');
      database.execute('PRAGMA busy_timeout=5000;');
      database.execute('''
        CREATE TABLE IF NOT EXISTS playlist_edits (
          user_id TEXT NOT NULL,
          playlist_id TEXT NOT NULL,
          name TEXT,
          song_ids_json TEXT,
          base_snapshot_json TEXT,
          updated_at INTEGER NOT NULL,
          source_device_id TEXT,
          PRIMARY KEY (user_id, playlist_id)
        )
      ''');
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  List<PlaylistEdit> list(String userId) {
    final rows = _db.select('''
      SELECT playlist_id, name, song_ids_json, base_snapshot_json, updated_at,
             source_device_id
      FROM playlist_edits
      WHERE user_id = ?
      ORDER BY updated_at DESC, playlist_id ASC
    ''', <Object?>[userId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  PlaylistEdit put(
    String userId,
    String playlistId, {
    required List<String> songIds,
    String? name,
    required List<String> baseSnapshot,
    String? sourceDeviceId,
  }) {
    final normalizedPlaylistId = _validatePlaylistId(playlistId);
    final normalizedSongIds = _normalizeSongIds(songIds, 'songIds');
    final normalizedBaseSnapshot =
        _normalizeSongIds(baseSnapshot, 'baseSnapshot');
    final normalizedName = name;
    final now = DateTime.now().toUtc();

    _db.execute('''
      INSERT INTO playlist_edits (
        user_id, playlist_id, name, song_ids_json, base_snapshot_json,
        updated_at, source_device_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, playlist_id) DO UPDATE SET
        name = excluded.name,
        song_ids_json = excluded.song_ids_json,
        base_snapshot_json = excluded.base_snapshot_json,
        updated_at = excluded.updated_at,
        source_device_id = excluded.source_device_id
    ''', <Object?>[
      userId,
      normalizedPlaylistId,
      normalizedName,
      jsonEncode(normalizedSongIds),
      jsonEncode(normalizedBaseSnapshot),
      now.millisecondsSinceEpoch,
      sourceDeviceId,
    ]);
    return _find(userId, normalizedPlaylistId)!;
  }

  bool delete(String userId, String playlistId) {
    final normalizedPlaylistId = _validatePlaylistId(playlistId);
    _db.execute(
      'DELETE FROM playlist_edits WHERE user_id = ? AND playlist_id = ?',
      <Object?>[userId, normalizedPlaylistId],
    );
    return _db.updatedRows > 0;
  }

  /// Imports backup rows without ever accepting a user id from the file.
  /// Existing `(user,playlist)` rows win in merge mode, making repeated
  /// imports idempotent. Replace mode is atomic.
  int import(
    String userId,
    Iterable<Map<String, dynamic>> rows, {
    required bool replace,
    String? sourceDeviceId,
  }) {
    final normalized = <({
      String playlistId,
      String? name,
      List<String> songIds,
      List<String> baseSnapshot,
      DateTime? updatedAt,
    })>[];
    final seen = <String>{};
    for (final row in rows) {
      try {
        final rawPlaylistId = row['playlistId'];
        final rawSongIds = row['songIds'];
        final rawBaseSnapshot = row['baseSnapshot'];
        final rawName = row['name'];
        if (rawPlaylistId is! String ||
            rawSongIds is! List ||
            rawBaseSnapshot is! List ||
            (rawName != null && rawName is! String)) {
          continue;
        }
        final playlistId = _validatePlaylistId(rawPlaylistId);
        if (!seen.add(playlistId)) continue;
        normalized.add((
          playlistId: playlistId,
          name: rawName as String?,
          songIds: _normalizeSongIds(rawSongIds, 'songIds'),
          baseSnapshot: _normalizeSongIds(rawBaseSnapshot, 'baseSnapshot'),
          updatedAt: row['updatedAt'] is String
              ? DateTime.tryParse(row['updatedAt'] as String)
              : null,
        ));
      } on ArgumentError {
        continue;
      }
    }

    _db.execute('BEGIN IMMEDIATE');
    try {
      if (replace) {
        _db.execute(
          'DELETE FROM playlist_edits WHERE user_id = ?',
          <Object?>[userId],
        );
      }
      for (final row in normalized) {
        if (!replace && _find(userId, row.playlistId) != null) continue;
        _insertImported(
          userId,
          row.playlistId,
          name: row.name,
          songIds: row.songIds,
          baseSnapshot: row.baseSnapshot,
          updatedAt: row.updatedAt,
          sourceDeviceId: sourceDeviceId,
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return normalized.length;
  }

  void _insertImported(
    String userId,
    String playlistId, {
    required String? name,
    required List<String> songIds,
    required List<String> baseSnapshot,
    required DateTime? updatedAt,
    String? sourceDeviceId,
  }) {
    final timestamp =
        (updatedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    _db.execute('''
      INSERT INTO playlist_edits (
        user_id, playlist_id, name, song_ids_json, base_snapshot_json,
        updated_at, source_device_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, playlist_id) DO UPDATE SET
        name = excluded.name,
        song_ids_json = excluded.song_ids_json,
        base_snapshot_json = excluded.base_snapshot_json,
        updated_at = excluded.updated_at,
        source_device_id = excluded.source_device_id
    ''', <Object?>[
      userId,
      playlistId,
      name,
      jsonEncode(songIds),
      jsonEncode(baseSnapshot),
      timestamp,
      sourceDeviceId,
    ]);
  }

  PlaylistEdit? _find(String userId, String playlistId) {
    final rows = _db.select('''
      SELECT playlist_id, name, song_ids_json, base_snapshot_json, updated_at,
             source_device_id
      FROM playlist_edits
      WHERE user_id = ? AND playlist_id = ?
      LIMIT 1
    ''', <Object?>[userId, playlistId]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  String _validatePlaylistId(String playlistId) {
    if (playlistId.trim().isEmpty || playlistId.length > maxPlaylistIdLength) {
      throw ArgumentError.value(
          playlistId, 'playlistId', 'Invalid playlist id');
    }
    return playlistId.trim();
  }

  List<String> _normalizeSongIds(Iterable<dynamic> rawSongIds, String name) {
    final songIds = <String>[];
    final seen = <String>{};
    for (final rawSongId in rawSongIds) {
      if (rawSongId is! String || rawSongId.trim().isEmpty) {
        throw ArgumentError.value(rawSongId, name, 'Invalid song id');
      }
      final songId = rawSongId.trim();
      if (seen.add(songId)) songIds.add(songId);
      if (songIds.length > maxSongIds) {
        throw ArgumentError.value(rawSongIds, name, 'Too many song ids');
      }
    }
    return List<String>.unmodifiable(songIds);
  }

  PlaylistEdit _fromRow(Row row) => PlaylistEdit(
        playlistId: row['playlist_id'] as String,
        name: row['name'] as String?,
        songIds: _decodeNullableStringList(row['song_ids_json'] as String?),
        baseSnapshot: _decodeStringList(row['base_snapshot_json'] as String?),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int,
          isUtc: true,
        ),
        sourceDeviceId: row['source_device_id'] as String?,
      );

  List<String>? _decodeNullableStringList(String? value) =>
      value == null ? null : _decodeStringList(value);

  List<String> _decodeStringList(String? value) {
    if (value == null) return const <String>[];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
  }

  void close() {
    _database?.close();
    _database = null;
  }
}
