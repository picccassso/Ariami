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

  String? _sessionToken;
  String? _userId;
  String? _username;

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

  Stream<void> get sessionExpiredStream => _sessionExpiredController.stream;

  String? get sessionToken => _sessionToken;

  String? get userId => _userId;

  String? get username => _username;

  bool get isAuthenticated => _sessionToken != null;

  Map<String, String>? get authHeaders {
    final token = _sessionToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> loadAuthInfo() async {
    final authData = await _persistence.loadAuthInfo();
    _sessionToken = authData['sessionToken'];
    _userId = authData['userId'];
    _username = authData['username'];
  }

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

  Future<void> clearAuthInfo() async {
    _sessionToken = null;
    _userId = null;
    _username = null;

    await _persistence.clearAuthInfo();
  }

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

    _sessionExpiredController.add(null);

    _onSessionExpired?.call();
  }

  void dispose() {
    _sessionExpiredController.close();
  }
}
