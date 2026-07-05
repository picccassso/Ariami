import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/pinned_item.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite persistence for account-scoped pins.
///
/// The HTTP layer supplies [userId] and [sourceDeviceId] from a validated
/// session. Client payloads never select the account that is read or written.
class PinnedItemStore {
  PinnedItemStore({required this.databasePath});

  final String databasePath;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('PinnedItemStore is not initialized');
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
        CREATE TABLE IF NOT EXISTS pinned_items (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('album', 'playlist')),
          target_id TEXT NOT NULL,
          sort_order INTEGER NOT NULL,
          pinned_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          source_device_id TEXT,
          UNIQUE (user_id, type, target_id)
        )
      ''');
      database.execute('''
        CREATE INDEX IF NOT EXISTS idx_pinned_items_user_order
          ON pinned_items (user_id, sort_order, pinned_at, id)
      ''');
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  List<PinnedItem> list(String userId) {
    final rows = _db.select('''
      SELECT id, user_id, type, target_id, sort_order, pinned_at, updated_at,
             source_device_id
      FROM pinned_items
      WHERE user_id = ?
      ORDER BY sort_order ASC, pinned_at ASC, id ASC
    ''', <Object?>[userId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  PinnedItem pin(
    String userId,
    String type,
    String targetId, {
    String? sourceDeviceId,
    int? sortOrder,
    DateTime? pinnedAt,
  }) {
    _validate(type, targetId);
    final existing = _find(userId, type, targetId);
    if (existing != null) return existing;

    final now = DateTime.now().toUtc();
    final order = sortOrder != null && sortOrder >= 0
        ? sortOrder
        : (_db.select(
                    'SELECT MAX(sort_order) AS max_order FROM pinned_items WHERE user_id = ?',
                    <Object?>[userId]).first['max_order'] as int? ??
                -1) +
            1;
    final id = sha256
        .convert(utf8.encode('$userId\u0000$type\u0000$targetId'))
        .toString();
    final pinned = (pinnedAt ?? now).toUtc();
    _db.execute('''
      INSERT OR IGNORE INTO pinned_items (
        id, user_id, type, target_id, sort_order, pinned_at, updated_at,
        source_device_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', <Object?>[
      id,
      userId,
      type,
      targetId.trim(),
      order,
      pinned.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
      sourceDeviceId,
    ]);
    return _find(userId, type, targetId)!;
  }

  bool unpin(String userId, String type, String targetId) {
    _validate(type, targetId);
    _db.execute(
      'DELETE FROM pinned_items WHERE user_id = ? AND type = ? AND target_id = ?',
      <Object?>[userId, type, targetId.trim()],
    );
    return _db.updatedRows > 0;
  }

  /// Imports backup rows without ever accepting a user id from the file.
  /// Existing `(user,type,target)` rows win in merge mode, making repeated
  /// imports idempotent. Replace mode is atomic and preserves supplied order.
  int import(
    String userId,
    Iterable<Map<String, dynamic>> rows, {
    required bool replace,
    String? sourceDeviceId,
  }) {
    final normalized = <({
      String type,
      String targetId,
      int? sortOrder,
      DateTime? pinnedAt
    })>[];
    final seen = <String>{};
    for (final row in rows) {
      final rawType = row['type'];
      final rawTargetId = row['targetId'];
      if (rawType is! String ||
          rawTargetId is! String ||
          !PinnedItem.supportedTypes.contains(rawType) ||
          rawTargetId.trim().isEmpty) {
        continue;
      }
      final type = rawType;
      final targetId = rawTargetId;
      if (!seen.add('$type\u0000${targetId.trim()}')) continue;
      final rawOrder = row['sortOrder'];
      final order =
          rawOrder is num && rawOrder.toInt() >= 0 ? rawOrder.toInt() : null;
      normalized.add((
        type: type,
        targetId: targetId.trim(),
        sortOrder: order,
        pinnedAt: row['pinnedAt'] is String
            ? DateTime.tryParse(row['pinnedAt'] as String)
            : null,
      ));
    }

    _db.execute('BEGIN IMMEDIATE');
    try {
      if (replace) {
        _db.execute(
          'DELETE FROM pinned_items WHERE user_id = ?',
          <Object?>[userId],
        );
      }
      for (var index = 0; index < normalized.length; index++) {
        final row = normalized[index];
        pin(
          userId,
          row.type,
          row.targetId,
          sourceDeviceId: sourceDeviceId,
          sortOrder: row.sortOrder ?? index,
          pinnedAt: row.pinnedAt,
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return normalized.length;
  }

  PinnedItem? _find(String userId, String type, String targetId) {
    final rows = _db.select('''
      SELECT id, user_id, type, target_id, sort_order, pinned_at, updated_at,
             source_device_id
      FROM pinned_items
      WHERE user_id = ? AND type = ? AND target_id = ?
      LIMIT 1
    ''', <Object?>[userId, type, targetId.trim()]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  void _validate(String type, String targetId) {
    if (!PinnedItem.supportedTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'Unsupported pin type');
    }
    if (targetId.trim().isEmpty || targetId.length > 512) {
      throw ArgumentError.value(targetId, 'targetId', 'Invalid target id');
    }
  }

  PinnedItem _fromRow(Row row) => PinnedItem(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        type: row['type'] as String,
        targetId: row['target_id'] as String,
        sortOrder: row['sort_order'] as int,
        pinnedAt: DateTime.fromMillisecondsSinceEpoch(
          row['pinned_at'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int,
          isUtc: true,
        ),
        sourceDeviceId: row['source_device_id'] as String?,
      );

  void close() {
    _database?.close();
    _database = null;
  }
}
