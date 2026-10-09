import 'dart:async';
import 'dart:math';

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
  static final StreamTracker _instance = StreamTracker._internal();
  factory StreamTracker() => _instance;
  StreamTracker._internal();

  final Map<String, StreamTicket> _tickets = {};

  final Map<String, DownloadTicket> _downloadTickets = {};

  /// Stream tokens of currently active streams (for stats tracking).
  final Set<String> _activeStreams = {};

  final Random _random = Random.secure();

  Timer? _cleanupTimer;

  bool _initialized = false;

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

  /// Issue a download ticket for one song and quality.
  ///
  /// Tickets ride in the download URL's query string, so they must stay
  /// short-lived: clients request one per song right before transferring it
  /// (never in advance), and 2 hours comfortably covers a single transfer
  /// including any server-side transcode wait.
  DownloadTicket issueDownloadTicket({
    required String userId,
    required String sessionToken,
    required String songId,
    String? quality,
    String? format,
    Duration ttl = const Duration(hours: 2),
  }) {
    final now = DateTime.now();
    final ticket = DownloadTicket(
      token: _generateToken(),
      userId: userId,
      sessionToken: sessionToken,
      songId: songId,
      quality: quality,
      format: format,
      issuedAt: now,
      expiresAt: now.add(ttl),
    );

    _downloadTickets[ticket.token] = ticket;
    return ticket;
  }

  StreamTicket? validateToken(String streamToken) {
    final ticket = _tickets[streamToken];
    if (ticket == null) return null;

    if (DateTime.now().isAfter(ticket.expiresAt)) {
      _tickets.remove(streamToken);
      _activeStreams.remove(streamToken);
      return null;
    }

    return ticket;
  }

  DownloadTicket? validateDownloadToken(String downloadToken) {
    final ticket = _downloadTickets[downloadToken];
    if (ticket == null) return null;

    if (DateTime.now().isAfter(ticket.expiresAt)) {
      _downloadTickets.remove(downloadToken);
      return null;
    }

    return ticket;
  }

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

  /// Revoke all tickets for a session (on logout, admin kick, password change and user delete).
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

  /// Number of tracked tickets; may include expired ones until the cleanup sweep removes them.
  int get ticketCount => _tickets.length;

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

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpired();
    });
  }

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

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remainingTime {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Ticket for offline download transfer.
class DownloadTicket {
  final String token;
  final String userId;
  final String sessionToken;
  final String songId;
  final String? quality;
  final String? format;
  final DateTime issuedAt;
  final DateTime expiresAt;

  DownloadTicket({
    required this.token,
    required this.userId,
    required this.sessionToken,
    required this.songId,
    this.quality,
    this.format,
    required this.issuedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
