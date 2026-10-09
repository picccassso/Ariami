import 'dart:io';
import 'package:test/test.dart';
import 'package:ariami_core/services/auth/user_store.dart';
import 'package:ariami_core/services/auth/session_store.dart';
import 'package:ariami_core/services/server/connection_manager.dart';
import 'package:ariami_core/services/server/stream_tracker.dart';

/// Integration tests for multi-user concurrent streaming.
///
/// These tests verify that:
/// - Multiple users can register and login independently
/// - Each user has separate sessions
/// - Multiple users can stream different songs concurrently
/// - Server correctly tracks active sessions and active streamers
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('ariami_integration_tests_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Multi-User Registration and Login', () {
    late UserStore userStore;
    late SessionStore sessionStore;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('multi_user_test_');

      userStore = UserStore();
      await userStore.initialize('${testDir.path}/users.json');

      sessionStore = SessionStore();
      await sessionStore.initialize('${testDir.path}/sessions.json');
    });

    tearDown(() async {
      sessionStore.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('two users can register independently', () async {
      final user1 = await userStore.createUser('alice', 'password_hash_1');
      expect(user1.userId, isNotEmpty);
      expect(user1.username, equals('alice'));

      final user2 = await userStore.createUser('bob', 'password_hash_2');
      expect(user2.userId, isNotEmpty);
      expect(user2.username, equals('bob'));

      expect(user1.userId, isNot(equals(user2.userId)));

      expect(userStore.userCount, equals(2));
      expect(userStore.getUserByUsername('alice'), isNotNull);
      expect(userStore.getUserByUsername('bob'), isNotNull);
    });

    test('two users can login and have separate sessions', () async {
      final user1 = await userStore.createUser('alice', 'password_hash_1');
      final user2 = await userStore.createUser('bob', 'password_hash_2');

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_alice_phone',
        "Alice's Phone",
      );

      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_bob_tablet',
        "Bob's Tablet",
      );

      expect(session1.sessionToken, isNot(equals(session2.sessionToken)));
      expect(session1.userId, isNot(equals(session2.userId)));

      expect(sessionStore.getSession(session1.sessionToken), isNotNull);
      expect(sessionStore.getSession(session2.sessionToken), isNotNull);

      expect(sessionStore.sessionCount, equals(2));
    });

    test('one user can have multiple sessions (multiple devices)', () async {
      final user = await userStore.createUser('alice', 'password_hash');

      final sessionPhone = await sessionStore.createSession(
        user.userId,
        'device_phone',
        "Alice's Phone",
      );

      final sessionTablet = await sessionStore.createSession(
        user.userId,
        'device_tablet',
        "Alice's Tablet",
      );

      final sessionDesktop = await sessionStore.createSession(
        user.userId,
        'device_desktop',
        "Alice's Desktop",
      );

      expect(sessionStore.getSession(sessionPhone.sessionToken), isNotNull);
      expect(sessionStore.getSession(sessionTablet.sessionToken), isNotNull);
      expect(sessionStore.getSession(sessionDesktop.sessionToken), isNotNull);

      final userSessions = sessionStore.getSessionsForUser(user.userId);
      expect(userSessions.length, equals(3));
    });
  });

  group('Multi-User Concurrent Streaming', () {
    late UserStore userStore;
    late SessionStore sessionStore;
    late StreamTracker streamTracker;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('concurrent_stream_test_');

      userStore = UserStore();
      await userStore.initialize('${testDir.path}/users.json');

      sessionStore = SessionStore();
      await sessionStore.initialize('${testDir.path}/sessions.json');

      streamTracker = StreamTracker();
      streamTracker.initialize();
    });

    tearDown(() async {
      sessionStore.dispose();
      streamTracker.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('two users can stream different songs concurrently', () async {
      final user1 = await userStore.createUser('alice', 'hash1');
      final user2 = await userStore.createUser('bob', 'hash2');

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_1',
        'Device 1',
      );
      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_2',
        'Device 2',
      );

      final ticket1 = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );

      final ticket2 = streamTracker.issueTicket(
        userId: user2.userId,
        sessionToken: session2.sessionToken,
        songId: 'song_b',
        durationSeconds: 240,
      );

      expect(streamTracker.validateToken(ticket1.token), isNotNull);
      expect(streamTracker.validateToken(ticket2.token), isNotNull);

      streamTracker.startStream(ticket1.token);
      streamTracker.startStream(ticket2.token);

      expect(streamTracker.activeStreamCount, equals(2));
      expect(streamTracker.activeStreamerCount, equals(2));
      expect(streamTracker.ticketCount, equals(2));
    });

    test('same user streaming on multiple devices', () async {
      final user = await userStore.createUser('alice', 'hash');

      final sessionPhone = await sessionStore.createSession(
        user.userId,
        'device_phone',
        'Phone',
      );
      final sessionTablet = await sessionStore.createSession(
        user.userId,
        'device_tablet',
        'Tablet',
      );

      final ticketPhone = streamTracker.issueTicket(
        userId: user.userId,
        sessionToken: sessionPhone.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );

      final ticketTablet = streamTracker.issueTicket(
        userId: user.userId,
        sessionToken: sessionTablet.sessionToken,
        songId: 'song_b',
        durationSeconds: 200,
      );

      streamTracker.startStream(ticketPhone.token);
      streamTracker.startStream(ticketTablet.token);

      // 2 streams but only 1 unique streamer
      expect(streamTracker.activeStreamCount, equals(2));
      expect(streamTracker.activeStreamerCount, equals(1));
    });

    test('user logout revokes all stream tickets for that session', () async {
      final user1 = await userStore.createUser('alice', 'hash1');
      final user2 = await userStore.createUser('bob', 'hash2');

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_1',
        'Device 1',
      );
      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_2',
        'Device 2',
      );

      final ticket1a = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );
      final ticket1b = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_b',
        durationSeconds: 180,
      );

      final ticket2 = streamTracker.issueTicket(
        userId: user2.userId,
        sessionToken: session2.sessionToken,
        songId: 'song_c',
        durationSeconds: 180,
      );

      streamTracker.startStream(ticket1a.token);
      streamTracker.startStream(ticket1b.token);
      streamTracker.startStream(ticket2.token);

      expect(streamTracker.activeStreamCount, equals(3));
      expect(streamTracker.activeStreamerCount, equals(2));

      streamTracker.revokeSessionTickets(session1.sessionToken);
      await sessionStore.revokeSession(session1.sessionToken);

      expect(streamTracker.validateToken(ticket1a.token), isNull);
      expect(streamTracker.validateToken(ticket1b.token), isNull);

      expect(streamTracker.validateToken(ticket2.token), isNotNull);

      expect(streamTracker.activeStreamCount, equals(1));
      expect(streamTracker.activeStreamerCount, equals(1));
      expect(streamTracker.ticketCount, equals(1));
    });

    test('streams are independent - ending one does not affect others',
        () async {
      final user1 = await userStore.createUser('alice', 'hash1');
      final user2 = await userStore.createUser('bob', 'hash2');

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_1',
        'Device 1',
      );
      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_2',
        'Device 2',
      );

      final ticket1 = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );
      final ticket2 = streamTracker.issueTicket(
        userId: user2.userId,
        sessionToken: session2.sessionToken,
        songId: 'song_b',
        durationSeconds: 180,
      );

      streamTracker.startStream(ticket1.token);
      streamTracker.startStream(ticket2.token);

      expect(streamTracker.activeStreamCount, equals(2));

      streamTracker.endStream(ticket1.token);

      expect(streamTracker.activeStreamCount, equals(1));
      expect(streamTracker.validateToken(ticket2.token), isNotNull);

      // User 1's ticket is still valid (not expired), just not actively streaming
      expect(streamTracker.validateToken(ticket1.token), isNotNull);
    });
  });

  group('Server Statistics', () {
    late UserStore userStore;
    late SessionStore sessionStore;
    late StreamTracker streamTracker;
    late Directory testDir;

    setUp(() async {
      testDir = await tempDir.createTemp('stats_test_');

      userStore = UserStore();
      await userStore.initialize('${testDir.path}/users.json');

      sessionStore = SessionStore();
      await sessionStore.initialize('${testDir.path}/sessions.json');

      streamTracker = StreamTracker();
      streamTracker.initialize();
    });

    tearDown(() async {
      sessionStore.dispose();
      streamTracker.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('server can report active sessions and active streamers', () async {
      final user1 = await userStore.createUser('alice', 'hash1');
      final user2 = await userStore.createUser('bob', 'hash2');
      final user3 = await userStore.createUser('charlie', 'hash3');

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_1',
        'Device 1',
      );
      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_2',
        'Device 2',
      );
      final session3 = await sessionStore.createSession(
        user3.userId,
        'device_3',
        'Device 3',
      );

      expect(sessionStore.sessionCount, equals(3));

      // Only 2 users are streaming
      final ticket1 = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );
      final ticket2 = streamTracker.issueTicket(
        userId: user2.userId,
        sessionToken: session2.sessionToken,
        songId: 'song_b',
        durationSeconds: 180,
      );

      streamTracker.startStream(ticket1.token);
      streamTracker.startStream(ticket2.token);

      expect(userStore.userCount, equals(3)); // Total registered users
      expect(sessionStore.sessionCount, equals(3)); // Active sessions
      expect(streamTracker.activeStreamerCount,
          equals(2)); // Users actively streaming
      expect(
          streamTracker.activeStreamCount, equals(2)); // Total active streams

      // User 3 is connected but not streaming
      expect(sessionStore.getSession(session3.sessionToken), isNotNull);
    });

    test('stats update correctly as users connect and disconnect', () async {
      final user1 = await userStore.createUser('alice', 'hash1');
      final user2 = await userStore.createUser('bob', 'hash2');

      expect(userStore.userCount, equals(2));
      expect(sessionStore.sessionCount, equals(0));
      expect(streamTracker.activeStreamerCount, equals(0));

      final session1 = await sessionStore.createSession(
        user1.userId,
        'device_1',
        'Device 1',
      );
      expect(sessionStore.sessionCount, equals(1));

      final session2 = await sessionStore.createSession(
        user2.userId,
        'device_2',
        'Device 2',
      );
      expect(sessionStore.sessionCount, equals(2));

      final ticket1 = streamTracker.issueTicket(
        userId: user1.userId,
        sessionToken: session1.sessionToken,
        songId: 'song_a',
        durationSeconds: 180,
      );
      streamTracker.startStream(ticket1.token);
      expect(streamTracker.activeStreamerCount, equals(1));

      streamTracker.revokeSessionTickets(session1.sessionToken);
      await sessionStore.revokeSession(session1.sessionToken);

      expect(sessionStore.sessionCount, equals(1));
      expect(streamTracker.activeStreamerCount, equals(0));

      expect(sessionStore.getSession(session2.sessionToken), isNotNull);
    });
  });

  group('Connection Manager Stats', () {
    test('counts unique users across multiple devices', () {
      final manager = ConnectionManager();

      manager.registerClient('device_1', 'Device 1', userId: 'user_a');
      manager.registerClient('device_2', 'Device 2', userId: 'user_a');
      manager.registerClient('device_3', 'Device 3', userId: 'user_b');

      expect(manager.clientCount, equals(3));
      expect(manager.uniqueUserCount, equals(2));
    });

    test('ignores legacy devices without userId', () {
      final manager = ConnectionManager();

      manager.registerClient('device_1', 'Device 1');
      manager.registerClient('device_2', 'Device 2', userId: 'user_a');

      expect(manager.clientCount, equals(2));
      expect(manager.uniqueUserCount, equals(1));
    });
  });

  group('Edge Cases', () {
    late StreamTracker streamTracker;

    setUp(() {
      streamTracker = StreamTracker();
      streamTracker.initialize();
    });

    tearDown(() {
      streamTracker.dispose();
    });

    test('handling many concurrent streams', () {
      for (int i = 0; i < 10; i++) {
        final ticket1 = streamTracker.issueTicket(
          userId: 'user_$i',
          sessionToken: 'session_$i',
          songId: 'song_${i}_a',
          durationSeconds: 180,
        );
        final ticket2 = streamTracker.issueTicket(
          userId: 'user_$i',
          sessionToken: 'session_$i',
          songId: 'song_${i}_b',
          durationSeconds: 180,
        );

        streamTracker.startStream(ticket1.token);
        streamTracker.startStream(ticket2.token);
      }

      expect(streamTracker.ticketCount, equals(20));
      expect(streamTracker.activeStreamCount, equals(20));
      expect(
          streamTracker.activeStreamerCount, equals(10)); // 10 distinct users
    });

    test('rapid ticket issuance does not cause collisions', () {
      final tokens = <String>{};

      for (int i = 0; i < 100; i++) {
        final ticket = streamTracker.issueTicket(
          userId: 'user_$i',
          sessionToken: 'session_$i',
          songId: 'song_$i',
          durationSeconds: 180,
        );
        tokens.add(ticket.token);
      }

      expect(tokens.length, equals(100));
    });
  });
}
