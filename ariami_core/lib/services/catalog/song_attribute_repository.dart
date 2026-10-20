import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// SQLite access for externally supplied per-song attributes.
///
/// Values are stored as JSON, so their type (bool, number or string list)
/// round-trips without a separate type column.
class SongAttributeRepository {
  /// Attribute that overrides the tag-derived instrumental badge.
  static const String instrumentalKey = 'instrumental';

  SongAttributeRepository({required Database database}) : _database = database;

  final Database _database;

  /// Every song's attributes, keyed by song id.
  Map<String, Map<String, Object>> readAll() {
    final result = <String, Map<String, Object>>{};
    final rows = _database
        .select('SELECT song_id, key, value_json FROM song_attributes;');
    for (final row in rows) {
      result.putIfAbsent(row['song_id'] as String,
              () => <String, Object>{})[row['key'] as String] =
          jsonDecode(row['value_json'] as String) as Object;
    }
    return result;
  }

  /// One attribute's value for every song that has it, keyed by song id.
  Map<String, Object> readKey(String key) => {
        for (final row in _database.select(
            'SELECT song_id, value_json FROM song_attributes WHERE key = ?;',
            <Object?>[key]))
          row['song_id'] as String:
              jsonDecode(row['value_json'] as String) as Object,
      };

  /// Merges [updates] (song id -> key -> value) in one transaction. A null
  /// value removes that key; keys not mentioned are left untouched.
  void apply(Map<String, Map<String, Object?>> updates) {
    final upsert = _database.prepare('''
INSERT INTO song_attributes (song_id, key, value_json) VALUES (?, ?, ?)
ON CONFLICT(song_id, key) DO UPDATE SET value_json = excluded.value_json;
''');
    final remove = _database
        .prepare('DELETE FROM song_attributes WHERE song_id = ? AND key = ?;');
    _database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final song in updates.entries) {
        for (final attribute in song.value.entries) {
          final value = attribute.value;
          if (value == null) {
            remove.execute(<Object?>[song.key, attribute.key]);
          } else {
            upsert
                .execute(<Object?>[song.key, attribute.key, jsonEncode(value)]);
          }
        }
      }
      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    } finally {
      upsert.close();
      remove.close();
    }
  }
}
