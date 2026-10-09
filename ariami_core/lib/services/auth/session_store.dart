import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../models/auth_models.dart';
import '../../utils/atomic_file_write.dart';
import '../../utils/secure_file_permissions.dart';

/// Stores and persists user sessions to JSON file.
/// Uses in-memory map for O(1) lookups, with sliding TTL expiry.
class SessionStore {
  final Map<String, Session> _sessions = {};

  static const Duration defaultTtl = Duration(days: 30);

  static const Duration cleanupInterval = Duration(minutes: 5);

  String? _filePath;

  bool _initialized = false;

  Timer? _cleanupTimer;

  /// Serialize persist operations to avoid temp-file rename collisions
  Future<void> _persistQueue = Future.value();

  /// Throttle how often session expiry is persisted for hot session tokens.
  static const Duration refreshPersistInterval = Duration(minutes: 10);
  final Map<String, DateTime> _lastRefreshPersistAt = {};

  final Random _random = Random.secure();

  Future<void> initialize(String filePath) async {
    if (_initialized) return;

    _filePath = filePath;
    final file = File(filePath);

    if (await file.exists()) {
      // Tighten pre-existing installs where the file/dir were created with
      // the default umask.
      await SecureFilePermissions.restrictDirectory(file.parent.path);
      await SecureFilePermissions.restrictFile(filePath);
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final jsonData = jsonDecode(content);
          if (jsonData is Map<String, dynamic>) {
            final sessionsList = jsonData['sessions'] as List<dynamic>? ?? [];
            final now = DateTime.now().toUtc();

            for (final sessionJson in sessionsList) {
              final session =
                  Session.fromJson(sessionJson as Map<String, dynamic>);
              final expiresAt = DateTime.parse(session.expiresAt);
              if (expiresAt.isAfter(now)) {
                _sessions[session.sessionToken] = session;
              }
            }
          }
        }
      } catch (e) {
        // If file is corrupted, start fresh but log the error
        print('SessionStore: Error loading sessions.json: $e');
        _sessions.clear();
      }
    }

    _initialized = true;
    _startCleanupTimer();

    // Persist to remove any expired sessions that were filtered out
    if (_sessions.isNotEmpty) {
      await _persist();
    }
  }

  Future<Session> createSession(
    String userId,
    String deviceId,
    String deviceName,
  ) async {
    _ensureInitialized();

    final sessionToken = _generateSessionToken();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(defaultTtl);

    final session = Session(
      sessionToken: sessionToken,
      userId: userId,
      deviceId: deviceId,
      deviceName: deviceName,
      createdAt: now.toIso8601String(),
      expiresAt: expiresAt.toIso8601String(),
    );

    _sessions[sessionToken] = session;
    await _persist();

    return session;
  }

  Session? getSession(String sessionToken) {
    _ensureInitialized();

    final session = _sessions[sessionToken];
    if (session == null) return null;

    final expiresAt = DateTime.parse(session.expiresAt);
    if (expiresAt.isBefore(DateTime.now().toUtc())) {
      _sessions.remove(sessionToken);
      // Don't persist here to avoid blocking - cleanup timer will handle it
      return null;
    }

    return session;
  }

  Future<void> refreshSession(String sessionToken) async {
    _ensureInitialized();

    final session = _sessions[sessionToken];
    if (session == null) return;

    final now = DateTime.now().toUtc();
    final lastPersistAt = _lastRefreshPersistAt[sessionToken];
    if (lastPersistAt != null &&
        now.difference(lastPersistAt) < refreshPersistInterval) {
      return;
    }

    final expiresAt = DateTime.parse(session.expiresAt);
    if (expiresAt.isBefore(now)) {
      _sessions.remove(sessionToken);
      _lastRefreshPersistAt.remove(sessionToken);
      return;
    }

    final newExpiresAt = now.add(defaultTtl);
    final refreshedSession = Session(
      sessionToken: session.sessionToken,
      userId: session.userId,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
      createdAt: session.createdAt,
      expiresAt: newExpiresAt.toIso8601String(),
    );

    _sessions[sessionToken] = refreshedSession;
    _lastRefreshPersistAt[sessionToken] = now;
    await _persist();
  }

  Future<void> revokeSession(String sessionToken) async {
    _ensureInitialized();

    if (_sessions.remove(sessionToken) != null) {
      _lastRefreshPersistAt.remove(sessionToken);
      await _persist();
    }
  }

  Future<void> revokeAllForUser(String userId) async {
    await revokeAllForUserWithDetails(userId);
  }

  Future<List<Session>> revokeAllForUserWithDetails(String userId) async {
    _ensureInitialized();

    final sessionsToRemove =
        _sessions.values.where((session) => session.userId == userId).toList();
    if (sessionsToRemove.isEmpty) return [];

    for (final session in sessionsToRemove) {
      _sessions.remove(session.sessionToken);
      _lastRefreshPersistAt.remove(session.sessionToken);
    }

    await _persist();
    return sessionsToRemove;
  }

  List<Session> getSessionsForUser(String userId) {
    _ensureInitialized();

    final now = DateTime.now().toUtc();
    return _sessions.values
        .where((s) => s.userId == userId)
        .where((s) => DateTime.parse(s.expiresAt).isAfter(now))
        .toList();
  }

  Future<void> revokeSessionsForUserOnDevice(
      String userId, String deviceId) async {
    _ensureInitialized();

    final tokensToRemove = _sessions.entries
        .where((e) => e.value.userId == userId && e.value.deviceId == deviceId)
        .map((e) => e.key)
        .toList();

    if (tokensToRemove.isEmpty) return;

    for (final token in tokensToRemove) {
      _sessions.remove(token);
      _lastRefreshPersistAt.remove(token);
    }

    await _persist();
  }

  /// Update the display name on every session of [deviceId] (user rename),
  /// so session listings match the device's new name.
  Future<void> renameDevice(String deviceId, String deviceName) async {
    _ensureInitialized();

    var changed = false;
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.deviceId != deviceId || session.deviceName == deviceName) {
        continue;
      }
      _sessions[entry.key] = Session(
        sessionToken: session.sessionToken,
        userId: session.userId,
        deviceId: session.deviceId,
        deviceName: deviceName,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
      );
      changed = true;
    }

    if (changed) {
      await _persist();
    }
  }

  List<Session> getSessionsForDevice(String deviceId) {
    _ensureInitialized();

    final now = DateTime.now().toUtc();
    return _sessions.values
        .where((s) => s.deviceId == deviceId)
        .where((s) => DateTime.parse(s.expiresAt).isAfter(now))
        .toList();
  }

  Future<List<Session>> revokeSessionsForDevice(String deviceId) async {
    _ensureInitialized();

    final sessionsToRemove = getSessionsForDevice(deviceId);
    if (sessionsToRemove.isEmpty) return [];

    for (final session in sessionsToRemove) {
      _sessions.remove(session.sessionToken);
      _lastRefreshPersistAt.remove(session.sessionToken);
    }

    await _persist();
    return sessionsToRemove;
  }

  int get sessionCount {
    _ensureInitialized();
    return _sessions.length;
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  Future<void> _persist() async {
    if (_filePath == null) return;

    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      final file = File(_filePath!);

      // Ensure directory exists, readable by the owner only (auth data).
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await SecureFilePermissions.restrictDirectory(dir.path);

      final data = {
        'sessions': _sessions.values.map((s) => s.toJson()).toList(),
        'lastModified': DateTime.now().toUtc().toIso8601String(),
      };

      final jsonString = jsonEncode(data);

      await writeFileAtomically(_filePath!, jsonString, ownerOnly: true);
    });

    return _persistQueue;
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => _cleanupExpired());
  }

  Future<void> _cleanupExpired() async {
    if (!_initialized) return;

    final now = DateTime.now().toUtc();
    final expiredTokens = <String>[];

    for (final entry in _sessions.entries) {
      final expiresAt = DateTime.parse(entry.value.expiresAt);
      if (expiresAt.isBefore(now)) {
        expiredTokens.add(entry.key);
      }
    }

    if (expiredTokens.isEmpty) return;

    for (final token in expiredTokens) {
      _sessions.remove(token);
      _lastRefreshPersistAt.remove(token);
    }

    await _persist();
    print(
        'SessionStore: Cleaned up ${expiredTokens.length} expired session(s)');
  }

  /// Generate a secure random session token.
  /// Format: 64 hex characters (256 bits of entropy).
  String _generateSessionToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'SessionStore not initialized. Call initialize() first.');
    }
  }

  /// Testing-only helper to clear in-memory singleton state between test runs.
  void resetForTesting() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _sessions.clear();
    _lastRefreshPersistAt.clear();
    _filePath = null;
    _initialized = false;
    _persistQueue = Future.value();
  }
}
