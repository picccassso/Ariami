import 'package:bcrypt/bcrypt.dart';
import '../../models/auth_models.dart';
import 'user_store.dart';
import 'session_store.dart';

/// Main authentication service coordinating user registration, login, and session management.
/// Singleton pattern - use AuthService() to get the instance.
class AuthService {
  static const String _desktopDashboardAdminDeviceId =
      'desktop_dashboard_admin';
  static const String _desktopDashboardAdminDeviceName =
      'Ariami Desktop Dashboard';
  static const String _cliWebDashboardDeviceName = 'Ariami CLI Web Dashboard';

  // The desktop music-player client (see the desktop app's ConnectionController).
  // It registers with this device name and a `desktop_client_` device-id
  // prefix. The classification is used for presence reporting; authentication
  // itself permits concurrent sessions on every distinct device.
  static const String _desktopPlayerDeviceName = 'Ariami Desktop';
  static const String _desktopPlayerDeviceIdPrefix = 'desktop_client_';

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

  /// Track failed login attempts per server-derived identifier.
  final Map<String, _LoginAttemptTracker> _loginAttempts = {};

  /// Maximum failed login attempts before rate limiting
  static const int maxLoginAttempts = 5;

  /// Cooldown period after max attempts reached
  static const Duration rateLimitCooldown = Duration(minutes: 15);

  /// Upper bound on tracked login-attempt buckets so the map cannot grow
  /// without limit under key churn (e.g. rotating usernames).
  static const int maxTrackedLoginBuckets = 5000;

  /// Minimum password length for new passwords. Existing shorter passwords
  /// keep working for login; only registration and password changes enforce
  /// this.
  static const int minPasswordLength = 10;

  /// Build a rate-limit bucket from request metadata controlled by the server.
  static String buildLoginRateLimitKey({
    required String clientIp,
    required String username,
  }) {
    final normalizedIp =
        clientIp.trim().isEmpty ? 'unknown_ip' : clientIp.trim();
    final normalizedUsername = username.trim().toLowerCase().isEmpty
        ? '<empty>'
        : username.trim().toLowerCase();
    return 'ip=$normalizedIp|user=$normalizedUsername';
  }

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
    if (password.length < minPasswordLength) {
      throw AuthException(AuthErrorCodes.invalidCredentials,
          'Password must be at least $minPasswordLength characters');
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
    String deviceName, {
    String? rateLimitKey,
    bool allowOtherDeviceTakeover = false,
  }) async {
    _ensureInitialized();

    // Check rate limiting by a server-derived key, not client-controlled IDs.
    final attemptKey = rateLimitKey ??
        buildLoginRateLimitKey(
          clientIp: 'unknown_ip',
          username: username,
        );
    _pruneLoginAttempts();
    final tracker =
        _loginAttempts.putIfAbsent(attemptKey, () => _LoginAttemptTracker());
    tracker.touch();
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

    // Success - reset rate limit tracker for this login bucket.
    tracker.reset();

    // Accounts are ecosystem identities, not single-device leases. Every
    // distinct phone, desktop player, and dashboard may remain signed in at
    // the same time. Re-authenticating the same installation replaces only
    // that device's previous session, preventing duplicate stale tokens.
    //
    // [allowOtherDeviceTakeover] remains accepted for wire compatibility with
    // older clients, but no longer revokes sessions belonging to other devices.
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

  /// Get all registered users ordered by creation time.
  List<User> getUsers() {
    _ensureInitialized();
    return _userStore.getUsers();
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

  /// True when this device is the CLI web or desktop dashboard control surface.
  ///
  /// Used by the HTTP server to tag presence rows so they are not counted as
  /// mobile clients in `/api/stats` (`mobileClients`).
  static bool isDashboardControlDevice({
    required String deviceId,
    required String deviceName,
  }) {
    if (deviceId == _desktopDashboardAdminDeviceId) {
      return true;
    }

    return deviceName == _desktopDashboardAdminDeviceName ||
        deviceName == _cliWebDashboardDeviceName;
  }

  /// True when this device is the desktop music-player client.
  ///
  /// Used to distinguish desktop playback clients from mobile/generic clients
  /// in presence and activity reporting.
  static bool isDesktopPlayerDevice({
    required String deviceId,
    required String deviceName,
  }) {
    if (deviceId.startsWith(_desktopPlayerDeviceIdPrefix)) {
      return true;
    }
    return deviceName == _desktopPlayerDeviceName;
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

  /// Update the display name on every session of a device (user rename).
  Future<void> renameDeviceSessions(String deviceId, String deviceName) async {
    _ensureInitialized();
    await _sessionStore.renameDevice(deviceId, deviceName);
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
    if (newPassword.length < minPasswordLength) {
      throw AuthException(
        AuthErrorCodes.invalidCredentials,
        'Password must be at least $minPasswordLength characters',
      );
    }

    final user = _userStore.getUserByUsername(username.trim());
    if (user == null) return null;

    final passwordHash =
        BCrypt.hashpw(newPassword, BCrypt.gensalt(logRounds: bcryptCost));
    return _userStore.updatePasswordHash(user.userId, passwordHash);
  }

  /// Delete a user account by user ID.
  /// Returns deleted user, or null if no such user exists.
  Future<User?> deleteUserById(String userId) async {
    _ensureInitialized();
    return _userStore.deleteUser(userId);
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

  /// Keep the login-attempt map bounded: drop trackers idle past the
  /// cooldown (they hold no useful rate-limit state), then evict the least
  /// recently touched buckets if the map is still oversized.
  void _pruneLoginAttempts() {
    final now = DateTime.now();
    _loginAttempts.removeWhere((_, tracker) =>
        !tracker.isLocked &&
        now.difference(tracker.lastAttemptAt) > rateLimitCooldown);

    if (_loginAttempts.length < maxTrackedLoginBuckets) {
      return;
    }
    final keysByAge = _loginAttempts.keys.toList()
      ..sort((a, b) => _loginAttempts[a]!
          .lastAttemptAt
          .compareTo(_loginAttempts[b]!.lastAttemptAt));
    for (final key
        in keysByAge.take(_loginAttempts.length - maxTrackedLoginBuckets + 1)) {
      _loginAttempts.remove(key);
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
  DateTime lastAttemptAt = DateTime.now();

  /// Record activity on this bucket (for idle-based pruning).
  void touch() {
    lastAttemptAt = DateTime.now();
  }

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
