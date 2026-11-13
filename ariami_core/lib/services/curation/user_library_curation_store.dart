import 'package:ariami_core/models/hidden_item.dart';
import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/services/common/sqlite_store.dart';
import 'package:ariami_core/services/hidden/hidden_item_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// Account-scoped SQLite store for per-user library curation rules and mode.
class UserLibraryCurationStore extends SqliteStore {
  UserLibraryCurationStore({required super.databasePath})
      : super(storeName: 'UserLibraryCurationStore');

  static const String _hiddenMigrationMetaKey = 'hidden_items_migrated_v1';

  @override
  void createSchema(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS user_curation_settings (
        user_id TEXT PRIMARY KEY,
        mode TEXT NOT NULL,
        onboarding_completed INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS user_curation_rules (
        user_id TEXT NOT NULL,
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        action TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        source_device_id TEXT,
        display_label TEXT,
        PRIMARY KEY (user_id, target_type, target_id)
      )
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_curation_rules_user
        ON user_curation_rules (user_id, target_type, action)
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS user_curation_meta (
        meta_key TEXT PRIMARY KEY,
        meta_value TEXT NOT NULL
      )
    ''');
  }

  UserLibraryCuration getForUser(
    String userId, {
    LibraryCurationMode defaultMode = LibraryCurationMode.full,
    bool defaultOnboardingCompleted = false,
  }) {
    final settingsRows = db.select(
      '''
      SELECT mode, onboarding_completed, revision, updated_at
      FROM user_curation_settings
      WHERE user_id = ?
      LIMIT 1
      ''',
      <Object?>[userId],
    );

    final rules = _readRulesForUser(userId);
    if (settingsRows.isEmpty) {
      return UserLibraryCuration.defaultForUser(
        userId,
        mode: defaultMode,
        onboardingCompleted: defaultOnboardingCompleted,
        revision: rules.isEmpty ? 0 : 1,
        rules: rules,
      );
    }

    final row = settingsRows.first;
    return UserLibraryCuration(
      userId: userId,
      mode: LibraryCurationMode.fromWire(row['mode'] as String?),
      onboardingCompleted: (row['onboarding_completed'] as int? ?? 0) != 0,
      revision: row['revision'] as int? ?? 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      rules: rules,
    );
  }

  /// Loads every user that already has persisted curation settings or rules.
  Map<String, UserLibraryCuration> listAllByUserId() {
    final result = <String, UserLibraryCuration>{};
    final settingsRows = db.select('''
      SELECT user_id, mode, onboarding_completed, revision, updated_at
      FROM user_curation_settings
    ''');

    final rulesByUser = <String, List<CurationRuleEntry>>{};
    final ruleRows = db.select('''
      SELECT user_id, target_type, target_id, action, updated_at,
             source_device_id, display_label
      FROM user_curation_rules
      ORDER BY rowid ASC
    ''');
    for (final row in ruleRows) {
      final userId = row['user_id'] as String;
      final parsed = _ruleFromRow(row);
      if (parsed != null) {
        rulesByUser.putIfAbsent(userId, () => <CurationRuleEntry>[]).add(parsed);
      }
    }

    for (final row in settingsRows) {
      final userId = row['user_id'] as String;
      result[userId] = UserLibraryCuration(
        userId: userId,
        mode: LibraryCurationMode.fromWire(row['mode'] as String?),
        onboardingCompleted: (row['onboarding_completed'] as int? ?? 0) != 0,
        revision: row['revision'] as int? ?? 1,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
          isUtc: true,
        ),
        rules: rulesByUser.remove(userId) ?? const <CurationRuleEntry>[],
      );
    }

    for (final entry in rulesByUser.entries) {
      result[entry.key] = UserLibraryCuration.defaultForUser(
        entry.key,
        revision: 1,
        rules: entry.value,
      );
    }

    return result;
  }

  UserLibraryCuration saveForUser(
    String userId, {
    required LibraryCurationMode mode,
    bool? onboardingCompleted,
    required List<CurationRuleEntry> rules,
    String? sourceDeviceId,
  }) {
    final now = DateTime.now().toUtc();
    final nowMs = now.millisecondsSinceEpoch;
    final deduplicated = _deduplicateRules(rules, defaultTimestamp: now, defaultSourceDeviceId: sourceDeviceId);

    late int nextRevision;
    late bool effectiveOnboardingCompleted;

    _runInTransaction(() {
      final existing = db.select(
        '''
        SELECT onboarding_completed, revision
        FROM user_curation_settings
        WHERE user_id = ?
        LIMIT 1
        ''',
        <Object?>[userId],
      );
      final prevRevision =
          existing.isEmpty ? 0 : (existing.first['revision'] as int? ?? 0);
      final prevOnboarding = existing.isEmpty
          ? false
          : ((existing.first['onboarding_completed'] as int? ?? 0) != 0);

      nextRevision = prevRevision + 1;
      effectiveOnboardingCompleted = onboardingCompleted ?? prevOnboarding;

      db.execute(
        '''
        INSERT INTO user_curation_settings (
          user_id, mode, onboarding_completed, revision, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          mode = excluded.mode,
          onboarding_completed = excluded.onboarding_completed,
          revision = excluded.revision,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          userId,
          mode.wireName,
          effectiveOnboardingCompleted ? 1 : 0,
          nextRevision,
          nowMs,
        ],
      );

      db.execute(
        'DELETE FROM user_curation_rules WHERE user_id = ?',
        <Object?>[userId],
      );

      if (deduplicated.isNotEmpty) {
        final stmt = db.prepare('''
          INSERT INTO user_curation_rules (
            user_id, target_type, target_id, action, updated_at,
            source_device_id, display_label
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''');
        try {
          for (final rule in deduplicated) {
            stmt.execute(<Object?>[
              userId,
              rule.targetType.wireName,
              rule.normalizedTargetId,
              rule.action.wireName,
              rule.updatedAt.toUtc().millisecondsSinceEpoch,
              rule.sourceDeviceId,
              rule.displayLabel,
            ]);
          }
        } finally {
          stmt.dispose();
        }
      }
    });

    return UserLibraryCuration(
      userId: userId,
      mode: mode,
      onboardingCompleted: effectiveOnboardingCompleted,
      revision: nextRevision,
      updatedAt: now,
      rules: deduplicated,
    );
  }

  /// Applies incremental rule additions/removals (used by `/api/hidden` facade
  /// and quick `+ Add` actions from search).
  UserLibraryCuration applyPatchForUser(
    String userId, {
    LibraryCurationMode? mode,
    bool? onboardingCompleted,
    List<CurationRuleEntry> upsertRules = const <CurationRuleEntry>[],
    List<({CurationTargetType targetType, String targetId})> removeTargets =
        const <({CurationTargetType targetType, String targetId})>[],
    LibraryCurationMode defaultMode = LibraryCurationMode.full,
    bool defaultOnboardingCompleted = false,
    String? sourceDeviceId,
  }) {
    final current = getForUser(
      userId,
      defaultMode: defaultMode,
      defaultOnboardingCompleted: defaultOnboardingCompleted,
    );

    final ruleMap = <String, CurationRuleEntry>{
      for (final rule in current.rules) rule.key: rule.normalized(),
    };
    for (final target in removeTargets) {
      final norm =
          CurationRuleEntry.normalizeTargetId(target.targetType, target.targetId);
      ruleMap.remove('${target.targetType.wireName}:$norm');
    }
    final now = DateTime.now().toUtc();
    for (final rule in upsertRules) {
      final normalized = rule
          .copyWith(
            updatedAt: now,
            sourceDeviceId: rule.sourceDeviceId ?? sourceDeviceId,
          )
          .normalized();
      if (normalized.normalizedTargetId.isNotEmpty) {
        ruleMap[normalized.key] = normalized;
      }
    }

    return saveForUser(
      userId,
      mode: mode ?? current.mode,
      onboardingCompleted: onboardingCompleted ?? current.onboardingCompleted,
      rules: ruleMap.values.toList(growable: false),
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// One-time migration from legacy `hidden_items.db` into `exclude` rules.
  bool migrateFromHiddenItems(
    HiddenItemStore hiddenStore, {
    bool Function(String userId)? isAdminUser,
  }) {
    final flag = db.select(
      'SELECT meta_value FROM user_curation_meta WHERE meta_key = ? LIMIT 1',
      <Object?>[_hiddenMigrationMetaKey],
    );
    if (flag.isNotEmpty && flag.first['meta_value'] == '1') {
      return false;
    }

    final legacyItems = hiddenStore.listAll();
    final byUser = <String, List<HiddenItem>>{};
    for (final item in legacyItems) {
      byUser.putIfAbsent(item.userId, () => <HiddenItem>[]).add(item);
    }

    _runInTransaction(() {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final entry in byUser.entries) {
        final userId = entry.key;
        final isAdmin = isAdminUser?.call(userId) ?? false;
        db.execute(
          '''
          INSERT OR IGNORE INTO user_curation_settings (
            user_id, mode, onboarding_completed, revision, updated_at
          ) VALUES (?, ?, ?, 1, ?)
          ''',
          <Object?>[
            userId,
            LibraryCurationMode.full.wireName,
            isAdmin ? 1 : 0,
            nowMs,
          ],
        );

        for (final item in entry.value) {
          final targetType = CurationTargetType.tryFromWire(item.type);
          if (targetType == null) continue;
          final normId =
              CurationRuleEntry.normalizeTargetId(targetType, item.targetId);
          if (normId.isEmpty) continue;
          final label = targetType == CurationTargetType.artist
              ? item.targetId.trim()
              : null;
          db.execute(
            '''
            INSERT OR IGNORE INTO user_curation_rules (
              user_id, target_type, target_id, action, updated_at,
              source_device_id, display_label
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            <Object?>[
              userId,
              targetType.wireName,
              normId,
              CurationRuleAction.exclude.wireName,
              item.hiddenAt.toUtc().millisecondsSinceEpoch,
              item.sourceDeviceId,
              label,
            ],
          );
        }
      }

      db.execute(
        '''
        INSERT OR REPLACE INTO user_curation_meta (meta_key, meta_value)
        VALUES (?, '1')
        ''',
        <Object?>[_hiddenMigrationMetaKey],
      );
    });

    return true;
  }

  /// Compatibility projection of `exclude` rules for legacy `/api/hidden`.
  List<HiddenItem> listExcludedAsHiddenItems(String userId) {
    final rows = db.select(
      '''
      SELECT target_type, target_id, updated_at, source_device_id, display_label
      FROM user_curation_rules
      WHERE user_id = ? AND action = ? AND target_type IN ('artist', 'album', 'playlist')
      ORDER BY updated_at ASC, rowid ASC
      ''',
      <Object?>[userId, CurationRuleAction.exclude.wireName],
    );
    return rows.map((row) {
      final type = row['target_type'] as String;
      final targetId = row['target_id'] as String;
      final label = (row['display_label'] as String?)?.trim();
      final effectiveTarget =
          (label != null && label.isNotEmpty) ? label : targetId;
      return HiddenItem(
        id: '$type:$targetId',
        userId: userId,
        type: type,
        targetId: effectiveTarget,
        hiddenAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int? ?? 0,
          isUtc: true,
        ),
        sourceDeviceId: row['source_device_id'] as String?,
      );
    }).toList(growable: false);
  }

  void deleteUser(String userId) {
    _runInTransaction(() {
      db.execute(
        'DELETE FROM user_curation_rules WHERE user_id = ?',
        <Object?>[userId],
      );
      db.execute(
        'DELETE FROM user_curation_settings WHERE user_id = ?',
        <Object?>[userId],
      );
    });
  }

  List<CurationRuleEntry> _readRulesForUser(String userId) {
    final rows = db.select(
      '''
      SELECT target_type, target_id, action, updated_at,
             source_device_id, display_label
      FROM user_curation_rules
      WHERE user_id = ?
      ORDER BY rowid ASC
      ''',
      <Object?>[userId],
    );
    return rows
        .map(_ruleFromRow)
        .whereType<CurationRuleEntry>()
        .toList(growable: false);
  }

  CurationRuleEntry? _ruleFromRow(Row row) {
    final targetType =
        CurationTargetType.tryFromWire(row['target_type'] as String?);
    final action = CurationRuleAction.tryFromWire(row['action'] as String?);
    final targetId = row['target_id'] as String?;
    if (targetType == null || action == null || targetId == null) return null;
    return CurationRuleEntry(
      targetType: targetType,
      targetId: targetId,
      action: action,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
        isUtc: true,
      ),
      sourceDeviceId: row['source_device_id'] as String?,
      displayLabel: row['display_label'] as String?,
    );
  }

  List<CurationRuleEntry> _deduplicateRules(
    List<CurationRuleEntry> rules, {
    required DateTime defaultTimestamp,
    String? defaultSourceDeviceId,
  }) {
    final map = <String, CurationRuleEntry>{};
    for (final raw in rules) {
      final normalized = raw
          .copyWith(
            updatedAt: raw.updatedAt,
            sourceDeviceId: raw.sourceDeviceId ?? defaultSourceDeviceId,
          )
          .normalized();
      if (normalized.normalizedTargetId.isEmpty) continue;
      map[normalized.key] = normalized;
    }
    return map.values.toList(growable: false);
  }

  void _runInTransaction(void Function() work) {
    db.execute('BEGIN IMMEDIATE');
    try {
      work();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
