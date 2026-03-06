import 'dart:io';
import 'package:test/test.dart';
import 'package:ariami_core/services/auth/session_store.dart';
import 'package:ariami_core/models/auth_models.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_session_tests_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SessionStore Create Session', () {
    late SessionStore sessionStore;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('create_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('creates session with valid fields', () async {
      final session = await sessionStore.createSession(
        'user_123',
        'device_abc',
        'Test Device',
      );

      expect(session.sessionToken, isNotEmpty);
      expect(session.sessionToken.length, equals(64)); // 32 bytes = 64 hex chars
      expect(session.userId, equals('user_123'));
      expect(session.deviceId, equals('device_abc'));
      expect(session.deviceName, equals('Test Device'));
      expect(session.createdAt, isNotEmpty);
      expect(session.expiresAt, isNotEmpty);
    });

    test('generates unique session tokens', () async {
      final session1 = await sessionStore.createSession('user_1', 'device_1', 'Device 1');
      final session2 = await sessionStore.createSession('user_2', 'device_2', 'Device 2');

      expect(session1.sessionToken, isNot(equals(session2.sessionToken)));
    });

    test('session expires in 30 days by default', () async {
      final session = await sessionStore.createSession('user_123', 'device_abc', 'Test Device');

      final createdAt = DateTime.parse(session.createdAt);
      final expiresAt = DateTime.parse(session.expiresAt);
      final duration = expiresAt.difference(createdAt);

      // Should be approximately 30 days (allow small margin for test execution time)
      expect(duration.inDays, equals(30));
    });

    test('increments session count', () async {
      expect(sessionStore.sessionCount, equals(0));

      await sessionStore.createSession('user_1', 'device_1', 'Device 1');
      expect(sessionStore.sessionCount, equals(1));

      await sessionStore.createSession('user_2', 'device_2', 'Device 2');
      expect(sessionStore.sessionCount, equals(2));
    });
  });

  group('SessionStore Get Session', () {
    late SessionStore sessionStore;
    late Directory testDir;
    late Session createdSession;

    setUp(() async {
      testDir = await tempDir.createTemp('get_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      createdSession = await sessionStore.createSession(
        'user_123',
        'device_abc',
        'Test Device',
      );
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('returns valid session', () {
      final session = sessionStore.getSession(createdSession.sessionToken);

      expect(session, isNotNull);
      expect(session!.sessionToken, equals(createdSession.sessionToken));
      expect(session.userId, equals('user_123'));
      expect(session.deviceId, equals('device_abc'));
      expect(session.deviceName, equals('Test Device'));
    });

    test('returns null for invalid token', () {
      final session = sessionStore.getSession('invalid_token_12345');
      expect(session, isNull);
    });

    test('returns null for empty token', () {
      final session = sessionStore.getSession('');
      expect(session, isNull);
    });
  });

  group('SessionStore Session Expiry', () {
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('expiry_test_');
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('returns null for expired session', () async {
      final sessionsFilePath = '${testDir.path}/sessions.json';

      // Create a sessions file with an expired session
      final expiredJson = '''
{
  "sessions": [
    {
      "sessionToken": "expired_token_abc123",
      "userId": "user_123",
      "deviceId": "device_abc",
      "deviceName": "Test Device",
      "createdAt": "2020-01-01T00:00:00.000Z",
      "expiresAt": "2020-01-31T00:00:00.000Z"
    }
  ],
  "lastModified": "2020-01-01T00:00:00.000Z"
}
''';
      await File(sessionsFilePath).writeAsString(expiredJson);

      final sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      // Expired session should not be loaded
      final session = sessionStore.getSession('expired_token_abc123');
      expect(session, isNull);
      expect(sessionStore.sessionCount, equals(0));

      sessionStore.dispose();
    });

    test('filters out expired sessions on load', () async {
      final sessionsFilePath = '${testDir.path}/sessions.json';

      // Create a file with mixed valid and expired sessions
      final now = DateTime.now().toUtc();
      final validExpiry = now.add(const Duration(days: 30)).toIso8601String();
      final expiredExpiry = now.subtract(const Duration(days: 1)).toIso8601String();

      final mixedJson = '''
{
  "sessions": [
    {
      "sessionToken": "valid_token_123",
      "userId": "user_1",
      "deviceId": "device_1",
      "deviceName": "Valid Device",
      "createdAt": "${now.toIso8601String()}",
      "expiresAt": "$validExpiry"
    },
    {
      "sessionToken": "expired_token_456",
      "userId": "user_2",
      "deviceId": "device_2",
      "deviceName": "Expired Device",
      "createdAt": "2020-01-01T00:00:00.000Z",
      "expiresAt": "$expiredExpiry"
    }
  ],
  "lastModified": "${now.toIso8601String()}"
}
''';
      await File(sessionsFilePath).writeAsString(mixedJson);

      final sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      expect(sessionStore.sessionCount, equals(1));
      expect(sessionStore.getSession('valid_token_123'), isNotNull);
      expect(sessionStore.getSession('expired_token_456'), isNull);

      sessionStore.dispose();
    });
  });

  group('SessionStore Refresh Session', () {
    late SessionStore sessionStore;
    late Directory testDir;
    late Session originalSession;

    setUp(() async {
      testDir = await tempDir.createTemp('refresh_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      originalSession = await sessionStore.createSession(
        'user_123',
        'device_abc',
        'Test Device',
      );
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('extends session expiry time', () async {
      final originalExpiry = DateTime.parse(originalSession.expiresAt);

      // Wait a tiny bit to ensure time difference
      await Future.delayed(const Duration(milliseconds: 10));

      await sessionStore.refreshSession(originalSession.sessionToken);

      final refreshedSession = sessionStore.getSession(originalSession.sessionToken);
      expect(refreshedSession, isNotNull);

      final newExpiry = DateTime.parse(refreshedSession!.expiresAt);
      expect(newExpiry.isAfter(originalExpiry), isTrue);
    });

    test('preserves other session fields after refresh', () async {
      await sessionStore.refreshSession(originalSession.sessionToken);

      final refreshedSession = sessionStore.getSession(originalSession.sessionToken);
      expect(refreshedSession, isNotNull);
      expect(refreshedSession!.sessionToken, equals(originalSession.sessionToken));
      expect(refreshedSession.userId, equals(originalSession.userId));
      expect(refreshedSession.deviceId, equals(originalSession.deviceId));
      expect(refreshedSession.deviceName, equals(originalSession.deviceName));
      expect(refreshedSession.createdAt, equals(originalSession.createdAt));
    });

    test('does nothing for invalid token', () async {
      // Should not throw
      await sessionStore.refreshSession('invalid_token_xyz');
      expect(sessionStore.sessionCount, equals(1));
    });
  });

  group('SessionStore Revoke Session', () {
    late SessionStore sessionStore;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('revoke_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('removes session by token', () async {
      final session = await sessionStore.createSession('user_123', 'device_abc', 'Test Device');
      expect(sessionStore.sessionCount, equals(1));

      await sessionStore.revokeSession(session.sessionToken);

      expect(sessionStore.sessionCount, equals(0));
      expect(sessionStore.getSession(session.sessionToken), isNull);
    });

    test('does nothing for invalid token', () async {
      await sessionStore.createSession('user_123', 'device_abc', 'Test Device');
      expect(sessionStore.sessionCount, equals(1));

      await sessionStore.revokeSession('nonexistent_token');

      expect(sessionStore.sessionCount, equals(1));
    });
  });

  group('SessionStore Revoke All For User', () {
    late SessionStore sessionStore;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('revoke_all_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('removes all sessions for a user', () async {
      // Create multiple sessions for user_1
      await sessionStore.createSession('user_1', 'device_1a', 'Device 1A');
      await sessionStore.createSession('user_1', 'device_1b', 'Device 1B');
      await sessionStore.createSession('user_1', 'device_1c', 'Device 1C');

      // Create session for user_2
      final user2Session = await sessionStore.createSession('user_2', 'device_2', 'Device 2');

      expect(sessionStore.sessionCount, equals(4));

      await sessionStore.revokeAllForUser('user_1');

      expect(sessionStore.sessionCount, equals(1));
      expect(sessionStore.getSession(user2Session.sessionToken), isNotNull);
    });

    test('does nothing for user with no sessions', () async {
      await sessionStore.createSession('user_1', 'device_1', 'Device 1');
      expect(sessionStore.sessionCount, equals(1));

      await sessionStore.revokeAllForUser('user_nonexistent');

      expect(sessionStore.sessionCount, equals(1));
    });
  });

  group('SessionStore Get Sessions For User', () {
    late SessionStore sessionStore;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('get_user_sessions_test_');
      final sessionsFilePath = '${testDir.path}/sessions.json';

      sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('returns all sessions for a user', () async {
      await sessionStore.createSession('user_1', 'device_1a', 'Device 1A');
      await sessionStore.createSession('user_1', 'device_1b', 'Device 1B');
      await sessionStore.createSession('user_2', 'device_2', 'Device 2');

      final user1Sessions = sessionStore.getSessionsForUser('user_1');

      expect(user1Sessions.length, equals(2));
      expect(user1Sessions.every((s) => s.userId == 'user_1'), isTrue);
    });

    test('returns empty list for user with no sessions', () {
      final sessions = sessionStore.getSessionsForUser('nonexistent_user');
      expect(sessions, isEmpty);
    });
  });

  group('SessionStore Persistence', () {
    late Directory testDir;
    late String sessionsFilePath;

    setUp(() async {
      testDir = await tempDir.createTemp('persist_test_');
      sessionsFilePath = '${testDir.path}/sessions.json';
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('persists sessions to JSON file', () async {
      final sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      final session = await sessionStore.createSession('user_123', 'device_abc', 'Test Device');
      sessionStore.dispose();

      // Load in a new store instance
      final newStore = SessionStore();
      await newStore.initialize(sessionsFilePath);

      final loadedSession = newStore.getSession(session.sessionToken);
      expect(loadedSession, isNotNull);
      expect(loadedSession!.userId, equals('user_123'));
      expect(loadedSession.deviceId, equals('device_abc'));

      newStore.dispose();
    });

    test('creates directory if it does not exist', () async {
      final nestedPath = '${testDir.path}/nested/deep/sessions.json';
      final sessionStore = SessionStore();
      await sessionStore.initialize(nestedPath);

      await sessionStore.createSession('user_123', 'device_abc', 'Test Device');

      final file = File(nestedPath);
      expect(await file.exists(), isTrue);

      sessionStore.dispose();
    });

    test('handles corrupted JSON file gracefully', () async {
      await File(sessionsFilePath).writeAsString('invalid json {{{');

      final sessionStore = SessionStore();
      await sessionStore.initialize(sessionsFilePath);

      expect(sessionStore.sessionCount, equals(0));

      sessionStore.dispose();
    });
  });

  group('SessionStore Initialization', () {
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('init_test_');
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('throws StateError when not initialized', () {
      final store = SessionStore();

      expect(() => store.sessionCount, throwsStateError);
      expect(() => store.getSession('token'), throwsStateError);
      expect(() => store.getSessionsForUser('user'), throwsStateError);
    });
  });

  group('Session Model', () {
    test('Session.fromJson creates correct instance', () {
      final json = {
        'sessionToken': 'token_123',
        'userId': 'user_456',
        'deviceId': 'device_789',
        'deviceName': 'Test Device',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'expiresAt': '2025-01-31T00:00:00.000Z',
      };

      final session = Session.fromJson(json);

      expect(session.sessionToken, equals('token_123'));
      expect(session.userId, equals('user_456'));
      expect(session.deviceId, equals('device_789'));
      expect(session.deviceName, equals('Test Device'));
      expect(session.createdAt, equals('2025-01-01T00:00:00.000Z'));
      expect(session.expiresAt, equals('2025-01-31T00:00:00.000Z'));
    });

    test('Session.toJson creates correct map', () {
      final session = Session(
        sessionToken: 'token_abc',
        userId: 'user_def',
        deviceId: 'device_ghi',
        deviceName: 'My Device',
        createdAt: '2025-02-01T12:00:00.000Z',
        expiresAt: '2025-03-03T12:00:00.000Z',
      );

      final json = session.toJson();

      expect(json['sessionToken'], equals('token_abc'));
      expect(json['userId'], equals('user_def'));
      expect(json['deviceId'], equals('device_ghi'));
      expect(json['deviceName'], equals('My Device'));
      expect(json['createdAt'], equals('2025-02-01T12:00:00.000Z'));
      expect(json['expiresAt'], equals('2025-03-03T12:00:00.000Z'));
    });

    test('Session roundtrip (toJson -> fromJson)', () {
      final original = Session(
        sessionToken: 'roundtrip_token',
        userId: 'roundtrip_user',
        deviceId: 'roundtrip_device',
        deviceName: 'Roundtrip Device',
        createdAt: '2025-03-01T00:00:00.000Z',
        expiresAt: '2025-03-31T00:00:00.000Z',
      );

      final json = original.toJson();
      final restored = Session.fromJson(json);

      expect(restored.sessionToken, equals(original.sessionToken));
      expect(restored.userId, equals(original.userId));
      expect(restored.deviceId, equals(original.deviceId));
      expect(restored.deviceName, equals(original.deviceName));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.expiresAt, equals(original.expiresAt));
    });
  });
}
