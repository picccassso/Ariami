import 'dart:async';
import 'dart:math';

/// How a stream's audio bytes reach the listener.
enum StreamDelivery {
  /// Served over HTTP via `/stream` (remote clients).
  http,

  /// Played straight from the library file on disk by the machine hosting
  /// the server (desktop server + client mode). Direct playback registers
  /// here so stream accounting covers every listener, not just HTTP ones.
  direct,
}

/// Tracks stream tokens and active streams for multi-user support.
/// Singleton pattern - use StreamTracker() to get the instance.
class StreamTracker {
  // Singleton pattern
  static final StreamTracker _instance = StreamTracker._internal();
  factory StreamTracker() => _instance;
  StreamTracker._internal();

  /// In-memory map: streamToken -> StreamTicket (O(1) lookup)
  final Map<String, StreamTicket> _tickets = {};

  /// In-memory map: downloadToken -> DownloadTicket (O(1) lookup).
  final Map<String, DownloadTicket> _downloadTickets = {};

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
  /// - [delivery]: How the audio reaches the listener (HTTP or direct file)
  StreamTicket issueTicket({
    required String userId,
    required String sessionToken,
    required String songId,
    required int durationSeconds,
    String? quality,
    StreamDelivery delivery = StreamDelivery.http,
  }) {
    // Generate secure random token (32 bytes = 64 hex chars)
    final token = _generateToken();

    final now = DateTime.now();
    final expiresAt = now.add(_ticketTtl(durationSeconds));

    final ticket = StreamTicket(
      token: token,
      userId: userId,
      sessionToken: sessionToken,
      songId: songId,
      quality: quality,
      delivery: delivery,
      issuedAt: now,
      expiresAt: expiresAt,
    );

    _tickets[token] = ticket;

    return ticket;
  }

  /// TTL policy: max(trackDuration + 10min, 20min), capped at 2hrs.
  Duration _ticketTtl(int durationSeconds) {
    final durationMinutes = (durationSeconds / 60).ceil();
    return Duration(minutes: min(max(durationMinutes + 10, 20), 120));
  }

  /// Issue a long-lived download ticket for one song and quality.
  DownloadTicket issueDownloadTicket({
    required String userId,
    required String sessionToken,
    required String songId,
    String? quality,
    Duration ttl = const Duration(hours: 24),
  }) {
    final now = DateTime.now();
    final ticket = DownloadTicket(
      token: _generateToken(),
      userId: userId,
      sessionToken: sessionToken,
      songId: songId,
      quality: quality,
      issuedAt: now,
      expiresAt: now.add(ttl),
    );

    _downloadTickets[ticket.token] = ticket;
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

  /// Validate a download token.
  /// Returns the DownloadTicket if valid and not expired, null otherwise.
  DownloadTicket? validateDownloadToken(String downloadToken) {
    final ticket = _downloadTickets[downloadToken];
    if (ticket == null) return null;

    if (DateTime.now().isAfter(ticket.expiresAt)) {
      _downloadTickets.remove(downloadToken);
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
  ///
  /// [discardTicket] also removes the ticket itself. HTTP streams keep their
  /// ticket alive until TTL (players re-use the token for range requests);
  /// direct playback sessions have no further use for it once ended.
  void endStream(String streamToken, {bool discardTicket = false}) {
    _activeStreams.remove(streamToken);
    if (discardTicket) {
      _tickets.remove(streamToken);
    }
  }

  /// Re-applies the TTL policy to a still-valid ticket, keeping a
  /// long-running playback session (e.g. a track on repeat) from expiring
  /// out of the active counts while it is genuinely still playing. Expiry
  /// stays in place as the leak guard for sessions that were never ended.
  void extendTicket(String streamToken, {int durationSeconds = 0}) {
    final ticket = _tickets[streamToken];
    if (ticket == null || ticket.isExpired) return;
    final extended = DateTime.now().add(_ticketTtl(durationSeconds));
    if (extended.isAfter(ticket.expiresAt)) {
      ticket.expiresAt = extended;
    }
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
    final downloadTokensToRemove = <String>[];
    for (final entry in _downloadTickets.entries) {
      if (entry.value.sessionToken == sessionToken) {
        downloadTokensToRemove.add(entry.key);
      }
    }
    for (final token in downloadTokensToRemove) {
      _downloadTickets.remove(token);
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

  /// Snapshot of the tickets behind currently active streams (HTTP and
  /// direct playback alike), for dashboards and stream-level stats.
  List<StreamTicket> get activeStreamTickets {
    final tickets = <StreamTicket>[];
    for (final token in _activeStreams) {
      final ticket = _tickets[token];
      if (ticket != null) tickets.add(ticket);
    }
    return List.unmodifiable(tickets);
  }

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
      print(
          '[StreamTracker] Cleaned up ${expiredTokens.length} expired tickets');
    }

    final expiredDownloadTokens = <String>[];
    for (final entry in _downloadTickets.entries) {
      if (now.isAfter(entry.value.expiresAt)) {
        expiredDownloadTokens.add(entry.key);
      }
    }
    for (final token in expiredDownloadTokens) {
      _downloadTickets.remove(token);
    }

    if (expiredDownloadTokens.isNotEmpty) {
      print(
        '[StreamTracker] Cleaned up ${expiredDownloadTokens.length} expired download tickets',
      );
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
    _downloadTickets.clear();
    _activeStreams.clear();
    _initialized = false;
  }

  String _generateToken() {
    final tokenBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return tokenBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Represents a stream ticket (short-lived token for audio streaming).
class StreamTicket {
  final String token;
  final String userId;
  final String sessionToken;
  final String songId;
  final String? quality;
  final StreamDelivery delivery;
  final DateTime issuedAt;

  /// Mutable: [StreamTracker.extendTicket] pushes it out for long-running
  /// direct playback sessions.
  DateTime expiresAt;

  StreamTicket({
    required this.token,
    required this.userId,
    required this.sessionToken,
    required this.songId,
    this.quality,
    this.delivery = StreamDelivery.http,
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

/// Represents a long-lived ticket for offline download transfer.
class DownloadTicket {
  final String token;
  final String userId;
  final String sessionToken;
  final String songId;
  final String? quality;
  final DateTime issuedAt;
  final DateTime expiresAt;

  DownloadTicket({
    required this.token,
    required this.userId,
    required this.sessionToken,
    required this.songId,
    this.quality,
    required this.issuedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
