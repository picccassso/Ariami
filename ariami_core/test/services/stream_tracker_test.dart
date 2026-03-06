import 'package:test/test.dart';
import 'package:ariami_core/services/server/stream_tracker.dart';

void main() {
  group('StreamTracker Issue Ticket', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('issues ticket with valid fields', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180, // 3 minutes
      );

      expect(ticket.token, isNotEmpty);
      expect(ticket.token.length, equals(64)); // 32 bytes = 64 hex chars
      expect(ticket.userId, equals('user_123'));
      expect(ticket.sessionToken, equals('session_abc'));
      expect(ticket.songId, equals('song_456'));
      expect(ticket.quality, isNull);
      expect(ticket.issuedAt, isNotNull);
      expect(ticket.expiresAt, isNotNull);
      expect(ticket.expiresAt.isAfter(ticket.issuedAt), isTrue);
    });

    test('issues ticket with quality parameter', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
        quality: 'high',
      );

      expect(ticket.quality, equals('high'));
    });

    test('generates unique tokens', () {
      final ticket1 = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );

      final ticket2 = tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_2',
        durationSeconds: 180,
      );

      expect(ticket1.token, isNot(equals(ticket2.token)));
    });

    test('increments ticket count', () {
      expect(tracker.ticketCount, equals(0));

      tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );
      expect(tracker.ticketCount, equals(1));

      tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_2',
        durationSeconds: 180,
      );
      expect(tracker.ticketCount, equals(2));
    });
  });

  group('StreamTracker TTL Calculation', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('short track gets minimum 20 minutes TTL', () {
      // 1 minute track should get 20 min TTL (minimum)
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 60, // 1 minute
      );

      final ttl = ticket.expiresAt.difference(ticket.issuedAt);
      expect(ttl.inMinutes, equals(20));
    });

    test('medium track gets duration + 10 minutes TTL', () {
      // 30 minute track should get 40 min TTL (30 + 10)
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 30 * 60, // 30 minutes
      );

      final ttl = ticket.expiresAt.difference(ticket.issuedAt);
      expect(ttl.inMinutes, equals(40));
    });

    test('long track is capped at 2 hours TTL', () {
      // 3 hour track should be capped at 2 hours
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 3 * 60 * 60, // 3 hours
      );

      final ttl = ticket.expiresAt.difference(ticket.issuedAt);
      expect(ttl.inMinutes, equals(120)); // 2 hours max
    });

    test('typical song (3 min) gets 20 min TTL', () {
      // 3 minute song: max(3+10, 20) = 20 minutes
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180, // 3 minutes
      );

      final ttl = ticket.expiresAt.difference(ticket.issuedAt);
      expect(ttl.inMinutes, equals(20));
    });

    test('15 minute track gets 25 min TTL', () {
      // 15 minute track: max(15+10, 20) = 25 minutes
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 15 * 60, // 15 minutes
      );

      final ttl = ticket.expiresAt.difference(ticket.issuedAt);
      expect(ttl.inMinutes, equals(25));
    });
  });

  group('StreamTracker Validate Token', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('returns ticket for valid token', () {
      final issued = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );

      final validated = tracker.validateToken(issued.token);

      expect(validated, isNotNull);
      expect(validated!.token, equals(issued.token));
      expect(validated.userId, equals('user_123'));
      expect(validated.songId, equals('song_456'));
    });

    test('returns null for invalid token', () {
      final validated = tracker.validateToken('invalid_token_xyz');
      expect(validated, isNull);
    });

    test('returns null for empty token', () {
      final validated = tracker.validateToken('');
      expect(validated, isNull);
    });
  });

  group('StreamTracker Stream Tracking', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('startStream marks stream as active', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );

      expect(tracker.activeStreamCount, equals(0));

      tracker.startStream(ticket.token);

      expect(tracker.activeStreamCount, equals(1));
    });

    test('endStream marks stream as inactive', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );

      tracker.startStream(ticket.token);
      expect(tracker.activeStreamCount, equals(1));

      tracker.endStream(ticket.token);
      expect(tracker.activeStreamCount, equals(0));
    });

    test('startStream does nothing for invalid token', () {
      tracker.startStream('invalid_token');
      expect(tracker.activeStreamCount, equals(0));
    });

    test('endStream does nothing for invalid token', () {
      // Should not throw
      tracker.endStream('invalid_token');
      expect(tracker.activeStreamCount, equals(0));
    });

    test('multiple streams can be active', () {
      final ticket1 = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );
      final ticket2 = tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_2',
        durationSeconds: 180,
      );

      tracker.startStream(ticket1.token);
      tracker.startStream(ticket2.token);

      expect(tracker.activeStreamCount, equals(2));
    });
  });

  group('StreamTracker Active Streamer Count', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('counts distinct users with active streams', () {
      // User 1 has two active streams
      final ticket1a = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1a',
        songId: 'song_1',
        durationSeconds: 180,
      );
      final ticket1b = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1b',
        songId: 'song_2',
        durationSeconds: 180,
      );

      // User 2 has one active stream
      final ticket2 = tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_3',
        durationSeconds: 180,
      );

      tracker.startStream(ticket1a.token);
      tracker.startStream(ticket1b.token);
      tracker.startStream(ticket2.token);

      expect(tracker.activeStreamCount, equals(3));
      expect(tracker.activeStreamerCount, equals(2)); // Only 2 distinct users
    });

    test('returns 0 when no active streams', () {
      expect(tracker.activeStreamerCount, equals(0));
    });

    test('updates when streams end', () {
      final ticket1 = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );
      final ticket2 = tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_2',
        durationSeconds: 180,
      );

      tracker.startStream(ticket1.token);
      tracker.startStream(ticket2.token);
      expect(tracker.activeStreamerCount, equals(2));

      tracker.endStream(ticket1.token);
      expect(tracker.activeStreamerCount, equals(1));

      tracker.endStream(ticket2.token);
      expect(tracker.activeStreamerCount, equals(0));
    });
  });

  group('StreamTracker Revoke Session Tickets', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('revokes all tickets for a session', () {
      // Create tickets for session_1
      final ticket1a = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );
      final ticket1b = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_2',
        durationSeconds: 180,
      );

      // Create ticket for session_2
      final ticket2 = tracker.issueTicket(
        userId: 'user_2',
        sessionToken: 'session_2',
        songId: 'song_3',
        durationSeconds: 180,
      );

      // Start all streams
      tracker.startStream(ticket1a.token);
      tracker.startStream(ticket1b.token);
      tracker.startStream(ticket2.token);

      expect(tracker.ticketCount, equals(3));
      expect(tracker.activeStreamCount, equals(3));

      // Revoke session_1
      tracker.revokeSessionTickets('session_1');

      expect(tracker.ticketCount, equals(1));
      expect(tracker.activeStreamCount, equals(1));
      expect(tracker.validateToken(ticket1a.token), isNull);
      expect(tracker.validateToken(ticket1b.token), isNull);
      expect(tracker.validateToken(ticket2.token), isNotNull);
    });

    test('does nothing for nonexistent session', () {
      final ticket = tracker.issueTicket(
        userId: 'user_1',
        sessionToken: 'session_1',
        songId: 'song_1',
        durationSeconds: 180,
      );

      tracker.revokeSessionTickets('nonexistent_session');

      expect(tracker.ticketCount, equals(1));
      expect(tracker.validateToken(ticket.token), isNotNull);
    });
  });

  group('StreamTicket Properties', () {
    late StreamTracker tracker;

    setUp(() {
      tracker = StreamTracker();
      tracker.initialize();
    });

    tearDown(() {
      tracker.dispose();
    });

    test('isExpired returns false for fresh ticket', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );

      expect(ticket.isExpired, isFalse);
    });

    test('remainingTime returns positive duration for fresh ticket', () {
      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );

      expect(ticket.remainingTime.inMinutes, greaterThan(0));
      expect(ticket.remainingTime.inMinutes, lessThanOrEqualTo(20));
    });
  });

  group('StreamTracker Dispose', () {
    test('clears all state on dispose', () {
      final tracker = StreamTracker();
      tracker.initialize();

      final ticket = tracker.issueTicket(
        userId: 'user_123',
        sessionToken: 'session_abc',
        songId: 'song_456',
        durationSeconds: 180,
      );
      tracker.startStream(ticket.token);

      expect(tracker.ticketCount, equals(1));
      expect(tracker.activeStreamCount, equals(1));

      tracker.dispose();

      expect(tracker.ticketCount, equals(0));
      expect(tracker.activeStreamCount, equals(0));
    });
  });
}
