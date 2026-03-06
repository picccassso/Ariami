import 'package:bcrypt/bcrypt.dart';
import '../../models/auth_models.dart';
import 'user_store.dart';
import 'session_store.dart';

/// Main authentication service coordinating user registration, login, and session management.
/// Singleton pattern - use AuthService() to get the instance.
class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// User storage
  final UserStore _userStore = UserStore();

  /// Session storage
  final SessionStore _sessionStore = SessionStore();

  /// bcrypt cost factor (10 is recommended for balance of security and performance)
  static const int bcryptCost = 10;

  /// Whether the service has been initialized
  bool _initialized = false;

  // ============================================================================
  // RATE LIMITING
  // ============================================================================

  /// Track failed login attempts per device/identifier
  final Map<String, _LoginAttemptTracker> _loginAttempts = {};

  /// Maximum failed login attempts before rate limiting
  static const int maxLoginAttempts = 5;

  /// Cooldown period after max attempts reached
  static const Duration rateLimitCooldown = Duration(minutes: 15);

  /// Initialize the auth service with paths to storage files.
  /// Must be called before any other methods.
  Future<void> initialize(String usersFilePath, String sessionsFilePath) async {
    if (_initialized) return;

    await _userStore.initialize(usersFilePath);
    await _sessionStore.initialize(sessionsFilePath);

    _initialized = true;
  }

  /// Register a new user account.
  /// Returns RegisterResponse on success.
  /// Throws UserExistsException if username is taken.
  /// Throws AuthException for other errors.
  Future<RegisterResponse> register(String username, String password) async {
    _ensureInitialized();

    // Validate input
    if (username.trim().isEmpty) {
      throw AuthException(
          AuthErrorCodes.invalidCredentials, 'Username cannot be empty');
    }
    if (password.isEmpty) {
      throw AuthException(
          AuthErrorCodes.invalidCredentials, 'Password cannot be empty');
    }
    if (username.length < 3) {
      throw AuthException(AuthErrorCodes.invalidCredentials,
          'Username must be at least 3 characters');
    }
    if (password.length < 4) {
      throw AuthException(AuthErrorCodes.invalidCredentials,
          'Password must be at least 4 characters');
    }

    // Hash password with bcrypt
    final passwordHash =
        BCrypt.hashpw(password, BCrypt.gensalt(logRounds: bcryptCost));

    // Create user (throws UserExistsException if username taken)
    final user = await _userStore.createUser(username.trim(), passwordHash);

    return RegisterResponse(
      userId: user.userId,
      username: user.username,
      sessionToken: '', // No session created on register - user must login
    );
  }

  /// Login with username and password.
  /// Creates a new session for the device.
  /// Returns LoginResponse on success.
  /// Throws AuthException if credentials are invalid or rate limited.
  Future<LoginResponse> login(
    String username,
    String password,
    String deviceId,
    String deviceName,
  ) async {
    _ensureInitialized();

    // Check rate limiting by deviceId
    final tracker =
        _loginAttempts.putIfAbsent(deviceId, () => _LoginAttemptTracker());
    if (tracker.isLocked) {
      final remainingMinutes =
          (tracker.remainingLockTime.inSeconds / 60).ceil();
      throw AuthException(
        AuthErrorCodes.rateLimited,
        'Too many failed login attempts. Try again in $remainingMinutes minute${remainingMinutes == 1 ? '' : 's'}.',
      );
    }

    // Find user by username
    final user = _userStore.getUserByUsername(username);
    if (user == null) {
      tracker.recordFailure(maxLoginAttempts, rateLimitCooldown);
      throw AuthException(
          AuthErrorCodes.invalidCredentials, 'Invalid username or password');
    }

    // Verify password
    if (!BCrypt.checkpw(password, user.passwordHash)) {
      tracker.recordFailure(maxLoginAttempts, rateLimitCooldown);
      throw AuthException(
          AuthErrorCodes.invalidCredentials, 'Invalid username or password');
    }

    // Success - reset rate limit tracker for this device
    tracker.reset();

    // Enforce single active session policy:
    // - same-device re-login is allowed (replace existing same-device session)
    // - different-device login is rejected while an active session exists
    if (_sessionStore.hasActiveSessionOnDifferentDevice(
        user.userId, deviceId)) {
      throw AuthException(
        AuthErrorCodes.alreadyLoggedInOtherDevice,
        'You are logged in on another device.',
      );
    }
    await _sessionStore.revokeSessionsForUserOnDevice(user.userId, deviceId);

    // Create a new session
    final session = await _sessionStore.createSession(
      user.userId,
      deviceId,
      deviceName,
    );

    return LoginResponse(
      userId: user.userId,
      username: user.username,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
    );
  }

  /// Logout by revoking the session token.
  /// Returns LogoutResponse.
  Future<LogoutResponse> logout(String sessionToken) async {
    _ensureInitialized();

    await _sessionStore.revokeSession(sessionToken);

    return LogoutResponse(success: true);
  }

  /// Validate a session token and refresh its TTL.
  /// Returns the Session if valid, null if invalid or expired.
  Future<Session?> validateSession(String sessionToken) async {
    _ensureInitialized();

    final session = _sessionStore.getSession(sessionToken);
    if (session == null) return null;

    // Refresh TTL on successful validation (sliding expiry)
    await _sessionStore.refreshSession(sessionToken);

    return session;
  }

  /// Get a session without refreshing TTL (for read-only checks).
  Session? getSession(String sessionToken) {
    _ensureInitialized();
    return _sessionStore.getSession(sessionToken);
  }

  /// Get user by ID.
  User? getUserById(String userId) {
    _ensureInitialized();
    return _userStore.getUserById(userId);
  }

  /// Get user by username.
  User? getUserByUsername(String username) {
    _ensureInitialized();
    return _userStore.getUserByUsername(username);
  }

  /// Check whether a user has admin privileges.
  /// Admin is the earliest created user for backward compatibility.
  bool isAdminUser(String userId) {
    _ensureInitialized();
    return _userStore.isAdminUser(userId);
  }

  /// Check if any users exist (for legacy mode detection).
  /// Returns true if at least one user is registered.
  bool hasUsers() {
    _ensureInitialized();
    return _userStore.hasUsers();
  }

  /// Get count of registered users.
  int get userCount {
    _ensureInitialized();
    return _userStore.userCount;
  }

  /// Get count of active sessions.
  int get sessionCount {
    _ensureInitialized();
    return _sessionStore.sessionCount;
  }

  /// Get all active sessions for a user.
  List<Session> getSessionsForUser(String userId) {
    _ensureInitialized();
    return _sessionStore.getSessionsForUser(userId);
  }

  /// Get all active sessions for a device.
  List<Session> getSessionsForDevice(String deviceId) {
    _ensureInitialized();
    return _sessionStore.getSessionsForDevice(deviceId);
  }

  /// Revoke all sessions for a user (logout all devices).
  Future<void> revokeAllSessionsForUser(String userId) async {
    _ensureInitialized();
    await _sessionStore.revokeAllForUser(userId);
  }

  /// Revoke all sessions for a user and return the revoked sessions.
  Future<List<Session>> revokeAllSessionsForUserWithDetails(
      String userId) async {
    _ensureInitialized();
    return _sessionStore.revokeAllForUserWithDetails(userId);
  }

  /// Revoke all active sessions for a device and return revoked sessions.
  Future<List<Session>> revokeSessionsForDevice(String deviceId) async {
    _ensureInitialized();
    return _sessionStore.revokeSessionsForDevice(deviceId);
  }

  /// Change password for an existing user.
  /// Returns updated user, or null if username does not exist.
  Future<User?> changePassword(String username, String newPassword) async {
    _ensureInitialized();

    if (newPassword.isEmpty) {
      throw AuthException(
        AuthErrorCodes.invalidCredentials,
        'Password cannot be empty',
      );
    }
    if (newPassword.length < 4) {
      throw AuthException(
        AuthErrorCodes.invalidCredentials,
        'Password must be at least 4 characters',
      );
    }

    final user = _userStore.getUserByUsername(username.trim());
    if (user == null) return null;

    final passwordHash =
        BCrypt.hashpw(newPassword, BCrypt.gensalt(logRounds: bcryptCost));
    return _userStore.updatePasswordHash(user.userId, passwordHash);
  }

  /// Clean up resources. Call when shutting down.
  void dispose() {
    _sessionStore.dispose();
  }

  /// Testing-only helper to clear singleton state for deterministic test runs.
  void resetForTesting() {
    _sessionStore.dispose();
    _sessionStore.resetForTesting();
    _userStore.resetForTesting();
    _loginAttempts.clear();
    _initialized = false;
  }

  /// Ensure the service has been initialized.
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('AuthService not initialized. Call initialize() first.');
    }
  }
}

/// Exception thrown for authentication errors.
class AuthException implements Exception {
  final String code;
  final String message;

  AuthException(this.code, this.message);

  @override
  String toString() => 'AuthException($code): $message';
}

/// Tracks login attempts for rate limiting
class _LoginAttemptTracker {
  int failedAttempts = 0;
  DateTime? lockedUntil;

  /// Check if currently rate limited
  bool get isLocked {
    if (lockedUntil == null) return false;
    if (DateTime.now().isAfter(lockedUntil!)) {
      // Lock expired, reset
      reset();
      return false;
    }
    return true;
  }

  /// Get remaining lockout time
  Duration get remainingLockTime {
    if (lockedUntil == null) return Duration.zero;
    final remaining = lockedUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Record a failed attempt
  void recordFailure(int maxAttempts, Duration cooldown) {
    failedAttempts++;
    if (failedAttempts >= maxAttempts) {
      lockedUntil = DateTime.now().add(cooldown);
    }
  }

  /// Reset tracker (on successful login)
  void reset() {
    failedAttempts = 0;
    lockedUntil = null;
  }
}
