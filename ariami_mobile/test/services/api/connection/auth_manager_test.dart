import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/services/api/connection/auth_manager.dart';
import 'package:ariami_mobile/services/api/connection/connection_persistence_manager.dart';

// Simple mock for ConnectionPersistenceManager
class MockPersistenceManager implements ConnectionPersistenceManager {
  final Map<String, String> _authData = {};

  @override
  Future<Map<String, String?>> loadAuthInfo() async {
    return {
      'sessionToken': _authData['session_token'],
      'userId': _authData['user_id'],
      'username': _authData['username'],
    };
  }

  @override
  Future<void> saveAuthInfo({
    required String sessionToken,
    required String userId,
    required String username,
  }) async {
    _authData['session_token'] = sessionToken;
    _authData['user_id'] = userId;
    _authData['username'] = username;
  }

  @override
  Future<void> clearAuthInfo() async {
    _authData.clear();
  }

  @override
  Future<void> saveSessionToken(String token) async {
    _authData['session_token'] = token;
  }

  @override
  Future<String?> loadSessionToken() async {
    return _authData['session_token'];
  }

  // Stub implementations for other methods
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AuthManager', () {
    late AuthManager manager;
    late MockPersistenceManager persistence;
    bool sessionExpiredCalled = false;

    setUp(() {
      persistence = MockPersistenceManager();
      sessionExpiredCalled = false;
      manager = AuthManager(
        persistence: persistence,
        onSessionExpired: () => sessionExpiredCalled = true,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    group('Initial State', () {
      test('should start with null auth info', () {
        expect(manager.sessionToken, isNull);
        expect(manager.userId, isNull);
        expect(manager.username, isNull);
        expect(manager.isAuthenticated, isFalse);
      });

      test('should return null authHeaders when not authenticated', () {
        expect(manager.authHeaders, isNull);
      });
    });

    group('setAuthInfo', () {
      test('should set auth info in memory', () async {
        await manager.setAuthInfo(
          sessionToken: 'token-123',
          userId: 'user-456',
          username: 'testuser',
        );

        expect(manager.sessionToken, equals('token-123'));
        expect(manager.userId, equals('user-456'));
        expect(manager.username, equals('testuser'));
        expect(manager.isAuthenticated, isTrue);
      });

      test('should persist auth info', () async {
        await manager.setAuthInfo(
          sessionToken: 'token-123',
          userId: 'user-456',
          username: 'testuser',
        );

        final loaded = await persistence.loadAuthInfo();
        expect(loaded['sessionToken'], equals('token-123'));
        expect(loaded['userId'], equals('user-456'));
        expect(loaded['username'], equals('testuser'));
      });

      test('should return correct authHeaders when authenticated', () async {
        await manager.setAuthInfo(
          sessionToken: 'bearer-token',
          userId: 'user-1',
          username: 'test',
        );

        expect(
          manager.authHeaders,
          equals({'Authorization': 'Bearer bearer-token'}),
        );
      });
    });

    group('clearAuthInfo', () {
      test('should clear auth info from memory', () async {
        await manager.setAuthInfo(
          sessionToken: 'token',
          userId: 'user',
          username: 'name',
        );

        await manager.clearAuthInfo();

        expect(manager.sessionToken, isNull);
        expect(manager.userId, isNull);
        expect(manager.username, isNull);
        expect(manager.isAuthenticated, isFalse);
      });

      test('should clear persisted auth info', () async {
        await manager.setAuthInfo(
          sessionToken: 'token',
          userId: 'user',
          username: 'name',
        );

        await manager.clearAuthInfo();

        final loaded = await persistence.loadAuthInfo();
        expect(loaded['sessionToken'], isNull);
      });
    });

    group('loadAuthInfo', () {
      test('should load auth info from persistence', () async {
        await persistence.saveAuthInfo(
          sessionToken: 'stored-token',
          userId: 'stored-user',
          username: 'stored-name',
        );

        await manager.loadAuthInfo();

        expect(manager.sessionToken, equals('stored-token'));
        expect(manager.userId, equals('stored-user'));
        expect(manager.username, equals('stored-name'));
        expect(manager.isAuthenticated, isTrue);
      });

      test('should handle missing auth info gracefully', () async {
        await manager.loadAuthInfo();

        expect(manager.sessionToken, isNull);
        expect(manager.isAuthenticated, isFalse);
      });
    });

    group('updateSessionToken', () {
      test('should update only the session token', () async {
        await manager.setAuthInfo(
          sessionToken: 'old-token',
          userId: 'user',
          username: 'name',
        );

        await manager.updateSessionToken('new-token');

        expect(manager.sessionToken, equals('new-token'));
        expect(manager.userId, equals('user')); // Unchanged
        expect(manager.username, equals('name')); // Unchanged
      });
    });

    group('handleSessionExpired', () {
      test('should clear auth info', () async {
        await manager.setAuthInfo(
          sessionToken: 'token',
          userId: 'user',
          username: 'name',
        );

        await manager.handleSessionExpired();

        expect(manager.isAuthenticated, isFalse);
      });

      test('should emit session expired event', () async {
        final events = <void>[];
        final subscription =
            manager.sessionExpiredStream.listen((_) => events.add(null));

        await manager.handleSessionExpired();
        await Future<void>.delayed(Duration.zero);

        expect(events.length, equals(1));
        await subscription.cancel();
      });

      test('should call onSessionExpired callback', () async {
        await manager.handleSessionExpired();
        expect(sessionExpiredCalled, isTrue);
      });

      test('should support multiple listeners', () async {
        var count = 0;
        final sub1 = manager.sessionExpiredStream.listen((_) => count++);
        final sub2 = manager.sessionExpiredStream.listen((_) => count++);

        await manager.handleSessionExpired();
        await Future<void>.delayed(Duration.zero);

        expect(count, equals(2));
        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('authHeaders edge cases', () {
      test('should return null for empty token', () async {
        await manager.setAuthInfo(
          sessionToken: '',
          userId: 'user',
          username: 'name',
        );

        expect(manager.authHeaders, isNull);
      });

      test('should handle token with special characters', () async {
        const token = 'token-with-special_chars.123';
        await manager.setAuthInfo(
          sessionToken: token,
          userId: 'user',
          username: 'name',
        );

        expect(
          manager.authHeaders,
          equals({'Authorization': 'Bearer $token'}),
        );
      });
    });
  });
}
