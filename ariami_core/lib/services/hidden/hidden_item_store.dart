import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/hidden_item.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite persistence for account-scoped hidden items.
///
/// The HTTP layer supplies [userId] and [sourceDeviceId] from a validated
/// session. Client payloads never select the account that is read or written.
///
/// Unlike pins there is no ordering to keep: hidden things are absent, so the
/// only questions a client asks are "which ones" and "is this one hidden".
class HiddenItemStore {
  HiddenItemStore({required this.databasePath});

  final String databasePath;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('HiddenItemStore is not initialized');
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
        CREATE TABLE IF NOT EXISTS hidden_items (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('album', 'playlist', 'artist')),
          target_id TEXT NOT NULL,
          hidden_at INTEGER NOT NULL,
          source_device_id TEXT,
          UNIQUE (user_id, type, target_id)
        )
      ''');
      database.execute('''
        CREATE INDEX IF NOT EXISTS idx_hidden_items_user
          ON hidden_items (user_id, hidden_at)
      ''');
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  List<HiddenItem> list(String userId) {
    final rows = _db.select('''
      SELECT id, user_id, type, target_id, hidden_at, source_device_id
      FROM hidden_items
      WHERE user_id = ?
      -- rowid, not id: a whole multi-select lands in the same millisecond, and
      -- the id is a hash, so only insertion order is stable within one batch.
      ORDER BY hidden_at ASC, rowid ASC
    ''', <Object?>[userId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  /// Hides one target. Hiding something already hidden is a no-op that returns
  /// the existing row, so a repeated request from a second device is harmless.
  HiddenItem hide(
    String userId,
    String type,
    String targetId, {
    String? sourceDeviceId,
    DateTime? hiddenAt,
  }) {
    _validate(type, targetId);
    final existing = _find(userId, type, targetId);
    if (existing != null) return existing;

    final trimmed = targetId.trim();
    final id = sha256
        .convert(utf8.encode('$userId\u0000$type\u0000$trimmed'))
        .toString();
    _db.execute('''
      INSERT OR IGNORE INTO hidden_items (
        id, user_id, type, target_id, hidden_at, source_device_id
      ) VALUES (?, ?, ?, ?, ?, ?)
    ''', <Object?>[
      id,
      userId,
      type,
      trimmed,
      (hiddenAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      sourceDeviceId,
    ]);
    return _find(userId, type, trimmed)!;
  }

  /// Hides a batch in one transaction — the multi-select path. Invalid rows
  /// are skipped rather than failing the batch, so one bad entry can't lose
  /// the user's whole selection. Returns the rows that ended up hidden.
  List<HiddenItem> hideAll(
    String userId,
    Iterable<({String type, String targetId})> targets, {
    String? sourceDeviceId,
  }) {
    final hidden = <HiddenItem>[];
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final target in targets) {
        try {
          hidden.add(hide(
            userId,
            target.type,
            target.targetId,
            sourceDeviceId: sourceDeviceId,
          ));
        } on ArgumentError {
          continue;
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return hidden;
  }

  bool unhide(String userId, String type, String targetId) {
    _validate(type, targetId);
    _db.execute(
      'DELETE FROM hidden_items WHERE user_id = ? AND type = ? AND target_id = ?',
      <Object?>[userId, type, targetId.trim()],
    );
    return _db.updatedRows > 0;
  }

  HiddenItem? _find(String userId, String type, String targetId) {
    final rows = _db.select('''
      SELECT id, user_id, type, target_id, hidden_at, source_device_id
      FROM hidden_items
      WHERE user_id = ? AND type = ? AND target_id = ?
      LIMIT 1
    ''', <Object?>[userId, type, targetId.trim()]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  void _validate(String type, String targetId) {
    if (!HiddenItem.supportedTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'Unsupported hidden item type');
    }
    if (targetId.trim().isEmpty || targetId.length > 512) {
      throw ArgumentError.value(targetId, 'targetId', 'Invalid target id');
    }
  }

  HiddenItem _fromRow(Row row) => HiddenItem(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        type: row['type'] as String,
        targetId: row['target_id'] as String,
        hiddenAt: DateTime.fromMillisecondsSinceEpoch(
          row['hidden_at'] as int,
          isUtc: true,
        ),
        sourceDeviceId: row['source_device_id'] as String?,
      );

  void close() {
    _database?.close();
    _database = null;
  }
}
