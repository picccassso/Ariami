import 'dart:async';
import 'connection_persistence_manager.dart';

/// Manages authentication state and secure storage.
///
/// Handles:
/// - Session token storage/retrieval
/// - User ID and username management
/// - Auth header generation
/// - Session expiry events
class AuthManager {
  final ConnectionPersistenceManager _persistence;
  final void Function()? _onSessionExpired;

  // Auth state
  String? _sessionToken;
  String? _userId;
  String? _username;

  // Stream controller for session expiry events
  final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();

  /// Creates an AuthManager.
  ///
  /// [persistence] is required for storing/retrieving auth data.
  /// [onSessionExpired] is an optional callback invoked when session expires.
  AuthManager({
    required ConnectionPersistenceManager persistence,
    void Function()? onSessionExpired,
  })  : _persistence = persistence,
        _onSessionExpired = onSessionExpired;

  /// Stream that emits when session expires (401 from server)
  Stream<void> get sessionExpiredStream => _sessionExpiredController.stream;

  /// Current session token (for authenticated requests)
  String? get sessionToken => _sessionToken;

  /// Current user ID
  String? get userId => _userId;

  /// Current username
  String? get username => _username;

  /// Check if user is authenticated
  bool get isAuthenticated => _sessionToken != null;

  /// Get Authorization header map for authenticated requests
  Map<String, String>? get authHeaders {
    final token = _sessionToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  /// Load stored auth info from secure storage
  Future<void> loadAuthInfo() async {
    final authData = await _persistence.loadAuthInfo();
    _sessionToken = authData['sessionToken'];
    _userId = authData['userId'];
    _username = authData['username'];
  }

  /// Set auth info in memory and persist to secure storage
  Future<void> setAuthInfo({
    required String sessionToken,
    required String userId,
    required String username,
  }) async {
    _sessionToken = sessionToken;
    _userId = userId;
    _username = username;

    await _persistence.saveAuthInfo(
      sessionToken: sessionToken,
      userId: userId,
      username: username,
    );
  }

  /// Clear auth info from memory and secure storage
  Future<void> clearAuthInfo() async {
    _sessionToken = null;
    _userId = null;
    _username = null;

    await _persistence.clearAuthInfo();
  }

  /// Update just the session token (used when server provides a new token)
  Future<void> updateSessionToken(String token) async {
    _sessionToken = token;
    await _persistence.saveSessionToken(token);
  }

  /// Handle session expiry - clear auth and emit event
  ///
  /// This is called when the server returns 401 SESSION_EXPIRED or AUTH_REQUIRED.
  /// It clears auth state and emits an event for UI to navigate to login.
  Future<void> handleSessionExpired() async {
    // Clear auth state from memory (don't call server logout - session is already invalid)
    await clearAuthInfo();

    // Notify listeners
    _sessionExpiredController.add(null);

    // Call optional callback
    _onSessionExpired?.call();
  }

  /// Dispose resources
  void dispose() {
    _sessionExpiredController.close();
  }
}
