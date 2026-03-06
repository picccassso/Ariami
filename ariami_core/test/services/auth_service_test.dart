import 'dart:io';
import 'package:test/test.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/auth/user_store.dart';
import 'package:ariami_core/models/auth_models.dart';

void main() {
  late Directory tempDir;
  late AuthService authService;
  late String usersFilePath;
  late String sessionsFilePath;
  int counter = 0;

  String unique(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${counter++}';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_auth_service_tests_');
    usersFilePath = '${tempDir.path}/users.json';
    sessionsFilePath = '${tempDir.path}/sessions.json';

    authService = AuthService();
    await authService.initialize(usersFilePath, sessionsFilePath);
  });

  tearDownAll(() async {
    authService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AuthService Register', () {
    test('registers a new user and increments count', () async {
      final baseCount = authService.userCount;
      final username = unique('user');
      final response = await authService.register(username, 'password123');

      expect(response.userId, isNotEmpty);
      expect(response.username, equals(username));
      expect(response.sessionToken, equals(''));
      expect(authService.userCount, equals(baseCount + 1));

      final storedUser = authService.getUserByUsername(username);
      expect(storedUser, isNotNull);
      expect(storedUser!.username, equals(username));
    });

    test('rejects duplicate username (case-insensitive)', () async {
      final username = unique('dupuser');
      await authService.register(username, 'password123');

      expect(
        () => authService.register(username.toUpperCase(), 'password456'),
        throwsA(isA<UserExistsException>()),
      );
    });

    test('rejects empty or short username/password', () async {
      expect(
        () => authService.register('', 'password'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => authService.register('ab', 'password'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => authService.register('validname', ''),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => authService.register('validname', '123'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthService Login / Validate / Logout', () {
    test('login returns session token and validateSession works', () async {
      final username = unique('loginuser');
      final password = 'strongpassword';
      await authService.register(username, password);

      final deviceId = unique('device');
      final response = await authService.login(username, password, deviceId, 'Test Device');

      expect(response.sessionToken, isNotEmpty);
      expect(response.sessionToken.length, equals(64));
      expect(response.expiresAt, isNotEmpty);

      final session = await authService.validateSession(response.sessionToken);
      expect(session, isNotNull);
      expect(session!.userId, equals(response.userId));
    });

    test('logout revokes session token', () async {
      final username = unique('logoutuser');
      final password = 'password123';
      await authService.register(username, password);

      final response = await authService.login(username, password, unique('device'), 'Logout Device');
      await authService.logout(response.sessionToken);

      final session = await authService.validateSession(response.sessionToken);
      expect(session, isNull);
    });

    test('login rejects invalid username', () async {
      expect(
        () => authService.login('nonexistent_user', 'password', unique('device'), 'Device'),
        throwsA(isA<AuthException>()),
      );
    });

    test('login rejects wrong password', () async {
      final username = unique('wrongpass');
      await authService.register(username, 'correctpassword');

      expect(
        () => authService.login(username, 'wrongpassword', unique('device'), 'Device'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthService Single-Session Enforcement', () {
    test('rejects login from different device when user already has active session', () async {
      final username = unique('single_session_block');
      const password = 'strongpassword';
      await authService.register(username, password);

      final firstDeviceId = unique('device');
      await authService.login(username, password, firstDeviceId, 'First Device');

      final secondDeviceId = unique('device');
      try {
        await authService.login(username, password, secondDeviceId, 'Second Device');
        fail('Expected ALREADY_LOGGED_IN_OTHER_DEVICE');
      } catch (e) {
        expect(e, isA<AuthException>());
        final authError = e as AuthException;
        expect(
          authError.code,
          equals(AuthErrorCodes.alreadyLoggedInOtherDevice),
        );
        expect(
          authError.message,
          equals('You are logged in on another device.'),
        );
      }
    });

    test('allows re-login from same device and replaces prior device session', () async {
      final username = unique('single_session_replace');
      const password = 'strongpassword';
      await authService.register(username, password);

      final deviceId = unique('device');
      final firstLogin = await authService.login(
        username,
        password,
        deviceId,
        'My Device',
      );

      final secondLogin = await authService.login(
        username,
        password,
        deviceId,
        'My Device',
      );

      expect(secondLogin.sessionToken, isNotEmpty);
      expect(secondLogin.sessionToken, isNot(equals(firstLogin.sessionToken)));

      final firstSession = await authService.validateSession(firstLogin.sessionToken);
      expect(firstSession, isNull);

      final secondSession =
          await authService.validateSession(secondLogin.sessionToken);
      expect(secondSession, isNotNull);
      expect(secondSession!.deviceId, equals(deviceId));

      final sessionsForUser = authService.getSessionsForUser(secondLogin.userId);
      expect(sessionsForUser.length, equals(1));
      expect(sessionsForUser.first.sessionToken, equals(secondLogin.sessionToken));
    });

    test(
        'allows login from a different device after current device sessions are revoked',
        () async {
      final username = unique('single_session_after_revoke');
      const password = 'strongpassword';
      await authService.register(username, password);

      final firstDeviceId = unique('device');
      final firstLogin = await authService.login(
        username,
        password,
        firstDeviceId,
        'First Device',
      );

      final secondDeviceId = unique('device');
      await expectLater(
        () => authService.login(
          username,
          password,
          secondDeviceId,
          'Second Device',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCodes.alreadyLoggedInOtherDevice,
          ),
        ),
      );

      final revoked = await authService.revokeSessionsForDevice(firstDeviceId);
      expect(revoked.length, equals(1));
      expect(revoked.first.sessionToken, equals(firstLogin.sessionToken));

      final secondLogin = await authService.login(
        username,
        password,
        secondDeviceId,
        'Second Device',
      );
      expect(secondLogin.sessionToken, isNotEmpty);

      final firstSession =
          await authService.validateSession(firstLogin.sessionToken);
      expect(firstSession, isNull);

      final activeSessions = authService.getSessionsForUser(secondLogin.userId);
      expect(activeSessions.length, equals(1));
      expect(activeSessions.first.deviceId, equals(secondDeviceId));
    });
  });

  group('AuthService Rate Limiting', () {
    test('rate limits after max failed attempts', () async {
      final username = unique('ratelimit');
      final password = 'correctpassword';
      await authService.register(username, password);

      final deviceId = unique('device');
      for (int i = 0; i < 5; i++) {
        try {
          await authService.login(username, 'wrongpassword', deviceId, 'Device');
          fail('Expected AuthException for invalid credentials');
        } catch (e) {
          expect(e, isA<AuthException>());
          expect((e as AuthException).code, equals(AuthErrorCodes.invalidCredentials));
        }
      }

      try {
        await authService.login(username, 'wrongpassword', deviceId, 'Device');
        fail('Expected rate limit after max attempts');
      } catch (e) {
        expect(e, isA<AuthException>());
        expect((e as AuthException).code, equals(AuthErrorCodes.rateLimited));
      }
    });

    test('successful login resets rate limit counter', () async {
      final username = unique('ratelimit_reset');
      final password = 'correctpassword';
      await authService.register(username, password);

      final deviceId = unique('device');

      // Fail twice
      for (int i = 0; i < 2; i++) {
        try {
          await authService.login(username, 'wrongpassword', deviceId, 'Device');
          fail('Expected AuthException for invalid credentials');
        } catch (e) {
          expect(e, isA<AuthException>());
          expect((e as AuthException).code, equals(AuthErrorCodes.invalidCredentials));
        }
      }

      // Successful login should reset tracker
      await authService.login(username, password, deviceId, 'Device');

      // Now it should allow 5 more failures before rate limit
      for (int i = 0; i < 5; i++) {
        try {
          await authService.login(username, 'wrongpassword', deviceId, 'Device');
          fail('Expected AuthException for invalid credentials');
        } catch (e) {
          expect(e, isA<AuthException>());
          expect((e as AuthException).code, equals(AuthErrorCodes.invalidCredentials));
        }
      }

      try {
        await authService.login(username, 'wrongpassword', deviceId, 'Device');
        fail('Expected rate limit after max attempts');
      } catch (e) {
        expect(e, isA<AuthException>());
        expect((e as AuthException).code, equals(AuthErrorCodes.rateLimited));
      }
    });
  });

  group('AuthException + AuthErrorCodes', () {
    test('AuthException contains code and message', () {
      final exception = AuthException('TEST_CODE', 'Test message');

      expect(exception.code, equals('TEST_CODE'));
      expect(exception.message, equals('Test message'));
      expect(exception.toString(), contains('TEST_CODE'));
      expect(exception.toString(), contains('Test message'));
    });

    test('AuthErrorCodes has expected constants', () {
      expect(AuthErrorCodes.invalidCredentials, equals('INVALID_CREDENTIALS'));
      expect(AuthErrorCodes.userExists, equals('USER_EXISTS'));
      expect(AuthErrorCodes.sessionExpired, equals('SESSION_EXPIRED'));
      expect(AuthErrorCodes.streamTokenExpired, equals('STREAM_TOKEN_EXPIRED'));
      expect(AuthErrorCodes.authRequired, equals('AUTH_REQUIRED'));
      expect(AuthErrorCodes.rateLimited, equals('RATE_LIMITED'));
    });
  });
}
