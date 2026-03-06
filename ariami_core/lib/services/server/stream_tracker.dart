import 'dart:async';
import 'dart:math';

/// Tracks stream tokens and active streams for multi-user support.
/// Singleton pattern - use StreamTracker() to get the instance.
class StreamTracker {
  // Singleton pattern
  static final StreamTracker _instance = StreamTracker._internal();
  factory StreamTracker() => _instance;
  StreamTracker._internal();

  /// In-memory map: streamToken -> StreamTicket (O(1) lookup)
  final Map<String, StreamTicket> _tickets = {};

  /// Track active streams: streamToken -> true (when actively streaming)
  final Set<String> _activeStreams = {};

  /// Random generator for secure token generation
  final Random _random = Random.secure();

  /// Cleanup timer
  Timer? _cleanupTimer;

  /// Whether the tracker has been initialized
  bool _initialized = false;

  /// Initialize the stream tracker and start cleanup timer.
  void initialize() {
    if (_initialized) return;
    _startCleanupTimer();
    _initialized = true;
  }

  /// Issue a stream ticket for a song.
  ///
  /// TTL calculation: max(trackDuration + 10min, 20min), capped at 2hrs
  ///
  /// Parameters:
  /// - [userId]: The user requesting the stream
  /// - [sessionToken]: The user's session token
  /// - [songId]: The song to stream
  /// - [durationSeconds]: The song duration in seconds
  /// - [quality]: Optional quality preset (high, medium, low)
  StreamTicket issueTicket({
    required String userId,
    required String sessionToken,
    required String songId,
    required int durationSeconds,
    String? quality,
  }) {
    // Generate secure random token (32 bytes = 64 hex chars)
    final tokenBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = tokenBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Calculate TTL: max(trackDuration + 10min, 20min), capped at 2hrs
    final durationMinutes = (durationSeconds / 60).ceil();
    final ttlMinutes = min(max(durationMinutes + 10, 20), 120);

    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: ttlMinutes));

    final ticket = StreamTicket(
      token: token,
      userId: userId,
      sessionToken: sessionToken,
      songId: songId,
      quality: quality,
      issuedAt: now,
      expiresAt: expiresAt,
    );

    _tickets[token] = ticket;

    return ticket;
  }

  /// Validate a stream token.
  /// Returns the StreamTicket if valid and not expired, null otherwise.
  StreamTicket? validateToken(String streamToken) {
    final ticket = _tickets[streamToken];
    if (ticket == null) return null;

    // Check if expired
    if (DateTime.now().isAfter(ticket.expiresAt)) {
      _tickets.remove(streamToken);
      _activeStreams.remove(streamToken);
      return null;
    }

    return ticket;
  }

  /// Mark a stream as actively streaming (for stats tracking).
  void startStream(String streamToken) {
    if (_tickets.containsKey(streamToken)) {
      _activeStreams.add(streamToken);
    }
  }

  /// Mark a stream as ended.
  void endStream(String streamToken) {
    _activeStreams.remove(streamToken);
  }

  /// Revoke all tickets for a session (called on logout).
  void revokeSessionTickets(String sessionToken) {
    final tokensToRemove = <String>[];
    for (final entry in _tickets.entries) {
      if (entry.value.sessionToken == sessionToken) {
        tokensToRemove.add(entry.key);
      }
    }
    for (final token in tokensToRemove) {
      _tickets.remove(token);
      _activeStreams.remove(token);
    }
  }

  /// Get count of currently active streamers (distinct users).
  int get activeStreamerCount {
    final activeUserIds = <String>{};
    for (final token in _activeStreams) {
      final ticket = _tickets[token];
      if (ticket != null) {
        activeUserIds.add(ticket.userId);
      }
    }
    return activeUserIds.length;
  }

  /// Get count of active streams (total, may be multiple per user).
  int get activeStreamCount => _activeStreams.length;

  /// Get count of valid (non-expired) tickets.
  int get ticketCount => _tickets.length;

  /// Cleanup expired tickets periodically.
  void _cleanupExpired() {
    final now = DateTime.now();
    final expiredTokens = <String>[];

    for (final entry in _tickets.entries) {
      if (now.isAfter(entry.value.expiresAt)) {
        expiredTokens.add(entry.key);
      }
    }

    for (final token in expiredTokens) {
      _tickets.remove(token);
      _activeStreams.remove(token);
    }

    if (expiredTokens.isNotEmpty) {
      print('[StreamTracker] Cleaned up ${expiredTokens.length} expired tickets');
    }
  }

  /// Start periodic cleanup timer (every 5 minutes).
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpired();
    });
  }

  /// Stop the cleanup timer and clear all data. Call on shutdown.
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _tickets.clear();
    _activeStreams.clear();
    _initialized = false;
  }
}

/// Represents a stream ticket (short-lived token for audio streaming).
class StreamTicket {
  final String token;
  final String userId;
  final String sessionToken;
  final String songId;
  final String? quality;
  final DateTime issuedAt;
  final DateTime expiresAt;

  StreamTicket({
    required this.token,
    required this.userId,
    required this.sessionToken,
    required this.songId,
    this.quality,
    required this.issuedAt,
    required this.expiresAt,
  });

  /// Check if the ticket is expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Get remaining time until expiry.
  Duration get remainingTime {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
