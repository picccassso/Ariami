import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../models/auth_models.dart';

/// Stores and persists user sessions to JSON file.
/// Uses in-memory map for O(1) lookups, with sliding TTL expiry.
class SessionStore {
  /// Map of sessionToken → Session for quick lookups
  final Map<String, Session> _sessions = {};

  /// Default session TTL: 30 days
  static const Duration defaultTtl = Duration(days: 30);

  /// Cleanup interval: every 5 minutes
  static const Duration cleanupInterval = Duration(minutes: 5);

  /// Path to the JSON file for persistence
  String? _filePath;

  /// Whether the store has been initialized
  bool _initialized = false;

  /// Timer for periodic cleanup of expired sessions
  Timer? _cleanupTimer;

  /// Serialize persist operations to avoid temp-file rename collisions
  Future<void> _persistQueue = Future.value();

  /// Throttle how often session expiry is persisted for hot session tokens.
  static const Duration refreshPersistInterval = Duration(minutes: 10);
  final Map<String, DateTime> _lastRefreshPersistAt = {};

  /// Random number generator for token generation
  final Random _random = Random.secure();

  /// Initialize the store by loading sessions from the JSON file.
  /// Automatically prunes expired sessions on load.
  Future<void> initialize(String filePath) async {
    if (_initialized) return;

    _filePath = filePath;
    final file = File(filePath);

    if (await file.exists()) {
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
              // Only load non-expired sessions
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

  /// Create a new session for a user on a specific device.
  /// Returns the created Session with a secure random token.
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

  /// Get a session by token.
  /// Returns null if not found or expired.
  Session? getSession(String sessionToken) {
    _ensureInitialized();

    final session = _sessions[sessionToken];
    if (session == null) return null;

    // Check if expired
    final expiresAt = DateTime.parse(session.expiresAt);
    if (expiresAt.isBefore(DateTime.now().toUtc())) {
      // Session expired - remove it
      _sessions.remove(sessionToken);
      // Don't persist here to avoid blocking - cleanup timer will handle it
      return null;
    }

    return session;
  }

  /// Refresh a session's expiry time (sliding TTL).
  /// Call this on successful activity to extend the session.
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

    // Check if expired first
    final expiresAt = DateTime.parse(session.expiresAt);
    if (expiresAt.isBefore(now)) {
      _sessions.remove(sessionToken);
      _lastRefreshPersistAt.remove(sessionToken);
      return;
    }

    // Create new session with extended expiry
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

  /// Revoke a specific session (logout).
  Future<void> revokeSession(String sessionToken) async {
    _ensureInitialized();

    if (_sessions.remove(sessionToken) != null) {
      _lastRefreshPersistAt.remove(sessionToken);
      await _persist();
    }
  }

  /// Revoke all sessions for a user (logout all devices).
  Future<void> revokeAllForUser(String userId) async {
    await revokeAllForUserWithDetails(userId);
  }

  /// Revoke all sessions for a user and return revoked sessions.
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

  /// Get all active sessions for a user.
  List<Session> getSessionsForUser(String userId) {
    _ensureInitialized();

    final now = DateTime.now().toUtc();
    return _sessions.values
        .where((s) => s.userId == userId)
        .where((s) => DateTime.parse(s.expiresAt).isAfter(now))
        .toList();
  }

  /// Returns true if user has an active session on a different device.
  bool hasActiveSessionOnDifferentDevice(String userId, String deviceId) {
    _ensureInitialized();

    final now = DateTime.now().toUtc();
    return _sessions.values
        .where((s) => s.userId == userId)
        .where((s) => DateTime.parse(s.expiresAt).isAfter(now))
        .any((s) => s.deviceId != deviceId);
  }

  /// Revoke all active sessions for a user on a specific device.
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

  /// Get all active sessions for a device.
  List<Session> getSessionsForDevice(String deviceId) {
    _ensureInitialized();

    final now = DateTime.now().toUtc();
    return _sessions.values
        .where((s) => s.deviceId == deviceId)
        .where((s) => DateTime.parse(s.expiresAt).isAfter(now))
        .toList();
  }

  /// Revoke all active sessions for a device and return revoked sessions.
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

  /// Get the count of active sessions.
  int get sessionCount {
    _ensureInitialized();
    return _sessions.length;
  }

  /// Clean up resources. Call when shutting down.
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Persist the current state to the JSON file.
  /// Uses atomic write (write to temp, then rename) for safety.
  Future<void> _persist() async {
    if (_filePath == null) return;

    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      final file = File(_filePath!);
      final tempFile = File('${_filePath!}.tmp');

      // Ensure directory exists
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = {
        'sessions': _sessions.values.map((s) => s.toJson()).toList(),
        'lastModified': DateTime.now().toUtc().toIso8601String(),
      };

      final jsonString = jsonEncode(data);

      // Atomic write: write to temp file, then rename
      await tempFile.writeAsString(jsonString);
      await tempFile.rename(_filePath!);
    });

    return _persistQueue;
  }

  /// Start the periodic cleanup timer.
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => _cleanupExpired());
  }

  /// Remove expired sessions from memory and persist.
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

  /// Ensure the store has been initialized.
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
