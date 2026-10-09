import 'dart:math';
import 'dart:typed_data';

import 'sqlite_store.dart';

/// The fields of a stored image that [SqliteImageStore.shrinkImages] needs.
typedef StoredImage = ({
  String key,
  Uint8List bytes,
  String contentType,
  int updatedAt,
});

/// Shared persistence for account-scoped image blobs keyed by
/// `(user_id, [keyColumn])` in [table].
abstract class SqliteImageStore extends SqliteStore {
  SqliteImageStore({
    required super.databasePath,
    required super.storeName,
    required this.table,
    required this.keyColumn,
  });

  final String table;
  final String keyColumn;

  /// The stored image for [key] as a [StoredImage], or null.
  StoredImage? findStoredImage(String userId, String key);

  /// Strictly monotonic per key so a replaced image always gets a new
  /// version, even within one clock millisecond.
  int nextUpdatedAt(String userId, String key) {
    final rows = db.select(
      'SELECT updated_at FROM $table '
      'WHERE user_id = ? AND $keyColumn = ? LIMIT 1',
      <Object?>[userId, key],
    );
    final previous = rows.isEmpty ? null : rows.first['updated_at'] as int;
    var updatedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (previous != null && updatedAt <= previous) {
      updatedAt = previous + 1;
    }
    return updatedAt;
  }

  bool deleteByKey(String userId, String key) {
    db.execute(
      'DELETE FROM $table WHERE user_id = ? AND $keyColumn = ?',
      <Object?>[userId, key],
    );
    return db.updatedRows > 0;
  }

  /// Replaces each stored image for which [shrink] returns new bytes, with a
  /// fresh `updated_at` so client caches keyed on it refresh. A row replaced
  /// by an upload while [shrink] ran is left alone. Returns how many rows
  /// were shrunk.
  Future<int> shrinkImages(
    Future<({Uint8List bytes, String contentType})?> Function(
      Uint8List bytes,
      String contentType,
    ) shrink,
  ) async {
    final keys = db.select('SELECT user_id, $keyColumn FROM $table');
    var shrunkCount = 0;
    for (final key in keys) {
      final userId = key['user_id'] as String;
      final record = findStoredImage(userId, key[keyColumn] as String);
      if (record == null) continue;
      final shrunk = await shrink(record.bytes, record.contentType);
      if (shrunk == null) continue;
      db.execute(
        'UPDATE $table '
        'SET bytes = ?, content_type = ?, updated_at = ? '
        'WHERE user_id = ? AND $keyColumn = ? AND updated_at = ?',
        <Object?>[
          shrunk.bytes,
          shrunk.contentType,
          max(DateTime.now().toUtc().millisecondsSinceEpoch,
              record.updatedAt + 1),
          userId,
          record.key,
          record.updatedAt,
        ],
      );
      if (db.updatedRows > 0) shrunkCount++;
    }
    return shrunkCount;
  }
}
