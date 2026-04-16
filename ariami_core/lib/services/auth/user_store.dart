import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../models/auth_models.dart';

/// Stores and persists user accounts to JSON file.
/// Uses in-memory maps for O(1) lookups, with atomic writes to disk.
class UserStore {
  /// Map of userId → User for quick ID lookups
  final Map<String, User> _users = {};

  /// Map of lowercase username → userId for case-insensitive username lookups
  final Map<String, String> _usernameIndex = {};

  /// Path to the JSON file for persistence
  String? _filePath;

  /// Whether the store has been initialized
  bool _initialized = false;

  /// Serialize persist operations to avoid temp-file rename collisions
  Future<void> _persistQueue = Future.value();

  /// Initialize the store by loading users from the JSON file.
  /// Creates an empty file if it doesn't exist.
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
            final usersList = jsonData['users'] as List<dynamic>? ?? [];
            for (final userJson in usersList) {
              final user = User.fromJson(userJson as Map<String, dynamic>);
              _users[user.userId] = user;
              _usernameIndex[user.username.toLowerCase()] = user.userId;
            }
          }
        }
      } catch (e) {
        // If file is corrupted, start fresh but log the error
        print('UserStore: Error loading users.json: $e');
        _users.clear();
        _usernameIndex.clear();
      }
    }

    _initialized = true;
  }

  /// Create a new user with the given username and password hash.
  /// Throws if username already exists.
  /// Returns the created User.
  Future<User> createUser(String username, String passwordHash) async {
    _ensureInitialized();

    // Check for existing username (case-insensitive)
    if (_usernameIndex.containsKey(username.toLowerCase())) {
      throw UserExistsException(username);
    }

    // Generate a unique user ID
    final userId = _generateUserId();
    final now = DateTime.now().toUtc().toIso8601String();

    final user = User(
      userId: userId,
      username: username,
      passwordHash: passwordHash,
      createdAt: now,
    );

    _users[userId] = user;
    _usernameIndex[username.toLowerCase()] = userId;

    await _persist();
    return user;
  }

  /// Get a user by their user ID.
  /// Returns null if not found.
  User? getUserById(String userId) {
    _ensureInitialized();
    return _users[userId];
  }

  /// Get a user by their username (case-insensitive).
  /// Returns null if not found.
  User? getUserByUsername(String username) {
    _ensureInitialized();
    final userId = _usernameIndex[username.toLowerCase()];
    if (userId == null) return null;
    return _users[userId];
  }

  /// Check if any users exist in the store.
  /// Used to determine legacy mode vs auth-required mode.
  bool hasUsers() {
    _ensureInitialized();
    return _users.isNotEmpty;
  }

  /// Get the count of registered users.
  int get userCount {
    _ensureInitialized();
    return _users.length;
  }

  /// Resolve the admin user as the earliest created account.
  /// This preserves backward compatibility with existing users.json data.
  String? getAdminUserId() {
    _ensureInitialized();
    if (_users.isEmpty) return null;

    final users = _users.values.toList()
      ..sort((a, b) {
        final createdCompare = a.createdAt.compareTo(b.createdAt);
        if (createdCompare != 0) return createdCompare;
        return a.userId.compareTo(b.userId);
      });

    return users.first.userId;
  }

  /// Check whether the provided user ID is the admin user.
  bool isAdminUser(String userId) {
    _ensureInitialized();
    final adminUserId = getAdminUserId();
    return adminUserId != null && adminUserId == userId;
  }

  /// Update password hash for an existing user.
  /// Returns the updated user, or null if no matching user exists.
  Future<User?> updatePasswordHash(String userId, String passwordHash) async {
    _ensureInitialized();

    final existingUser = _users[userId];
    if (existingUser == null) return null;

    final updatedUser = User(
      userId: existingUser.userId,
      username: existingUser.username,
      passwordHash: passwordHash,
      createdAt: existingUser.createdAt,
    );

    _users[userId] = updatedUser;
    await _persist();
    return updatedUser;
  }

  /// Delete an existing user by ID.
  /// Returns deleted user, or null when user does not exist.
  Future<User?> deleteUser(String userId) async {
    _ensureInitialized();

    final existingUser = _users.remove(userId);
    if (existingUser == null) return null;

    _usernameIndex.remove(existingUser.username.toLowerCase());
    await _persist();
    return existingUser;
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
        'users': _users.values.map((u) => u.toJson()).toList(),
        'lastModified': DateTime.now().toUtc().toIso8601String(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // Atomic write: write to temp file, then rename
      await tempFile.writeAsString(jsonString);
      await tempFile.rename(_filePath!);
    });

    return _persistQueue;
  }

  /// Generate a unique user ID using timestamp and random hash.
  String _generateUserId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    final hash = sha256.convert(utf8.encode('$timestamp-$random')).toString();
    return 'user_${hash.substring(0, 16)}';
  }

  /// Ensure the store has been initialized.
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('UserStore not initialized. Call initialize() first.');
    }
  }

  /// Testing-only helper to clear in-memory singleton state between test runs.
  void resetForTesting() {
    _users.clear();
    _usernameIndex.clear();
    _filePath = null;
    _initialized = false;
    _persistQueue = Future.value();
  }
}

/// Exception thrown when attempting to create a user with an existing username.
class UserExistsException implements Exception {
  final String username;
  UserExistsException(this.username);

  @override
  String toString() => 'User with username "$username" already exists';
}
