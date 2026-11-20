import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/listening_stats_models.dart'
    show
        ListeningAlbumRollup,
        ListeningArtistRollup,
        ListeningEvent,
        ListeningPeriodStats,
        ListeningSongRollup,
        ListeningStatsSummary,
        SpotifyImportStatus;
import 'package:ariami_core/services/stats/listening_event_outbox.dart';
import 'package:ariami_core/services/stats/listening_event_tracker.dart';
import 'package:ariami_core/services/stats/listening_stats_syncer.dart';
import 'package:ariami_core/utils/text_sanitizer.dart' show sanitizeTagText;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import 'audio_controller.dart';
import 'player_api_client.dart';
import 'player_host.dart';

part 'listening_stats_controller/listening_stats_account_sync.dart';
part 'listening_stats_controller/listening_stats_models.dart';
part 'listening_stats_controller/listening_stats_persistence.dart';
part 'listening_stats_controller/listening_stats_tracking.dart';

/// Records listening activity for the home view's stats — minutes listened,
/// listening streaks, top artist — and a "jump back in" row of recently
/// played albums/playlists.
///
/// Two layers work together:
/// - Local tracking (always on): credits wall-clock time while playback is
///   running, including mirrored Connect playback, and keeps the recents row.
///   Works with no server and no account.
/// - Account sync (when connected & signed in): honest listening events from
///   this device's own playback are queued durably and uploaded to the
///   server, and the displayed stats switch to the account-wide rollups so
///   listening on the phone or TV shows up here too. The tracker only ever
///   credits local playback — mirrored sessions are reported by the device
///   actually playing the audio, so nothing is counted twice.
class ListeningStatsController extends ChangeNotifier {
  ListeningStatsController({
    ListeningOutboxStore? outboxStore,
    String clientKind = 'web',
  })  : _outboxStore = outboxStore ?? PrefsListeningOutboxStore(),
        _clientKind = clientKind;

  final ListeningOutboxStore _outboxStore;
  final String _clientKind;

  static const _storageKey = 'desktop_listening_stats_v1';
  static const _maxEvents = 400;
  static const _maxRecentSources = 12;
  static const _maxDailyEntries = 120;

  /// A day needs at least a minute of listening to count toward the streak,
  /// so briefly opening the app doesn't inflate it.
  static const _streakMinimumSeconds = 60;

  AudioController? _audio;
  SharedPreferences? _prefs;
  Timer? _saveTimer;
  bool _dirty = false;

  static const _lastAccountKey = 'desktop_listening_stats_account_v1';
  static const _accountCacheKey = 'desktop_listening_stats_account_cache_v1';
  static const _periodCacheKey = 'desktop_listening_stats_period_cache_v1';
  static const _maxPeriodCacheEntries = 16;

  /// Cached trailing-window lists (recent songs, week artists) older than
  /// this are dropped on restore — unlike the day-keyed daily map, they go
  /// stale in a way that would misreport "this week".
  static const _accountCacheWindowMaxAge = Duration(hours: 24);

  PlayerApiClient? _client;
  String? _accountKey;
  final Map<String, ({int savedAtMs, ListeningPeriodStats stats})>
      _periodCache = <String, ({int savedAtMs, ListeningPeriodStats stats})>{};
  int _clientAttachGeneration = 0;
  ListeningEventTracker? _tracker;
  ListeningEventOutbox? _outbox;
  ListeningStatsSyncer? _syncer;
  Future<void>? _pipelineInit;
  Timer? _accountRefreshDebounce;
  bool _fetchingAccount = false;

  /// Account-wide listened ms per local day, fetched from the server.
  Map<String, int> _accountDailyMs = const <String, int>{};

  /// Account-wide per-song totals over the last 7 days.
  List<ListeningSongRollup> _accountRecent = const <ListeningSongRollup>[];

  /// All-time credited-artist and album rollups from the server. Empty on
  /// servers that predate the derivation layer — the snapshot then falls
  /// back to deriving artists/albums from the song rollups.
  List<ListeningArtistRollup> _accountArtists = const <ListeningArtistRollup>[];
  List<ListeningAlbumRollup> _accountAlbums = const <ListeningAlbumRollup>[];

  /// Credited artists over the trailing 7 days (for the home strip).
  List<ListeningArtistRollup> _accountWeekArtists =
      const <ListeningArtistRollup>[];
  ListeningStatsSummary _accountSummary = ListeningStatsSummary.empty;

  /// What the account's Spotify import holds. Null when never fetched or when
  /// the server predates the import-status endpoint — the UI then simply says
  /// nothing about the import.
  SpotifyImportStatus? _spotifyImportStatus;
  DateTime? _accountFetchedAt;

  /// When the account data currently held came from the persisted cache (an
  /// offline restart) rather than a fetch in this run.
  DateTime? _accountCachedAt;
  String? _accountError;
  Map<String, Album> _albumCatalog = const <String, Album>{};
  VoidCallback? onReset;

  bool get _hasAccountData => _accountFetchedAt != null;

  /// Home highlights prefer account-derived numbers whenever the account has
  /// ever been seen — freshly fetched or restored from the persisted cache —
  /// so the wall-clock local fallback only shows on never-connected setups.
  bool get _hasAccountHighlights =>
      _accountFetchedAt != null || _accountCachedAt != null;

  bool get hasAccountStats => _hasAccountData;
  bool get isRefreshingAccountStats => _fetchingAccount;
  String? get accountStatsError => _accountError;

  SpotifyImportStatus? get spotifyImportStatus =>
      hasSpotifyImport ? _spotifyImportStatus : null;

  bool get hasSpotifyImport =>
      _client != null &&
      _accountFetchedAt != null &&
      _accountSummary.hasSpotifyImport;

  void _notifyListeners() => notifyListeners();

  /// Cached derived snapshot: building it walks every song and re-matches
  /// credited artists, so computing it in every widget build janks once the
  /// lists are uncapped. Dropped by [_invalidateSnapshot] whenever the data
  /// behind it changes — deliberately *not* on every [notifyListeners], since
  /// most notifications (a minute of listening rolling over, a track change)
  /// leave the rollups untouched and rebuilding then costs a page of history
  /// its frame budget.
  ListeningStatsSnapshot? _snapshotMemo;

  ListeningStatsSnapshot get snapshot =>
      _snapshotMemo ??= ListeningStatsSnapshot.fromSongs(
        _mergedSummarySongs(),
        creditedArtists: _accountArtists.isNotEmpty
            ? _accountArtists
            : _accountWeekArtists,
        serverAlbums: _accountAlbums,
        albumCatalog: _albumCatalog,
        activeDays: _accountSummary.activeDays,
      );

  /// Call after mutating anything the snapshot derives from: the account
  /// summary, the server rollups, the album catalog, or the pending-event
  /// outbox that tops them up.
  void _invalidateSnapshot() => _snapshotMemo = null;

  /// Supplies the normalized library's album side-table. It repairs both
  /// historical server rollups for display and future events from restored
  /// queues whose Track records predate denormalized album metadata.
  void updateAlbumCatalog(Iterable<Album> albums) {
    final next = <String, Album>{for (final album in albums) album.id: album};
    if (_albumCatalog.length == next.length &&
        _albumCatalog.entries.every((entry) {
          final replacement = next[entry.key];
          return replacement != null &&
              replacement.title == entry.value.title &&
              replacement.artist == entry.value.artist;
        })) {
      return;
    }
    _albumCatalog = next;
    _invalidateSnapshot();
    notifyListeners();
  }

  /// `yyyy-mm-dd` -> seconds listened that day.
  final Map<String, double> _dailySeconds = <String, double>{};

  /// Track starts, newest first.
  List<PlayEvent> _events = <PlayEvent>[];

  /// Recently played collections as namespaced source keys
  /// (`album:<id>` / `playlist:<id>`), newest first.
  List<String> _recentSources = <String>[];

  String? _creditedTrackId;
  String? _lastSourceId;
  DateTime? _lastTick;
  int _lastMinutesToday = 0;

  List<String> get recentSources => List.unmodifiable(_recentSources);

  /// Drops a single collection from the "jump back in" row. This is a soft
  /// dismiss: the key reappears at the front the next time that album/playlist
  /// is played, since the row mirrors recent play history. Deliberately leaves
  /// `_lastSourceId` untouched so dismissing whatever is playing right now
  /// doesn't get instantly re-added by the next position tick.
  void removeRecentSource(String source) {
    final next = _recentSources.where((s) => s != source).toList();
    if (next.length == _recentSources.length) return;
    _recentSources = next;
    _markDirty();
    notifyListeners();
  }

  /// Empties the whole "jump back in" row. Like [removeRecentSource], entries
  /// reappear as collections are played again.
  void clearRecentSources() {
    if (_recentSources.isEmpty) return;
    _recentSources = <String>[];
    _markDirty();
    notifyListeners();
  }

  // Displayed stats -----------------------------------------------------------
  //
  // With account data these are account-wide (every device the user listens
  // on), topped up with this device's not-yet-uploaded events so the numbers
  // move in real time even offline. Without account data (no login yet, or
  // never reached the server) they fall back to the local-only tracking.

  int get minutesToday => _displayedSecondsForDay(DateTime.now()) ~/ 60;

  int get minutesThisWeek {
    var total = 0;
    var day = DateTime.now();
    for (var i = 0; i < 7; i++) {
      total += _displayedSecondsForDay(day);
      day = day.subtract(const Duration(days: 1));
    }
    return total ~/ 60;
  }

  int get playsThisWeek {
    if (!_hasAccountHighlights) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      var count = 0;
      for (final event in _events) {
        if (event.timestamp.isBefore(cutoff)) break; // events are newest-first
        count++;
      }
      return count;
    }
    var plays = 0;
    for (final rollup in _accountRecent) {
      plays += rollup.playCount;
    }
    final cutoffMs =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    for (final event in _pendingEvents()) {
      if (event.plays > 0 && event.occurredAtMs >= cutoffMs) {
        plays += event.plays;
      }
    }
    return plays;
  }

  /// Consecutive days (ending today, or yesterday if today hasn't started
  /// yet) with at least a minute of listening.
  int get streakDays {
    var day = DateTime.now();
    if (_displayedSecondsForDay(day) < _streakMinimumSeconds) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (_displayedSecondsForDay(day) >= _streakMinimumSeconds) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The top artist over the last 7 days, or null with no plays. Prefers the
  /// server's credited artists (collaborators on multi-artist tracks counted
  /// individually); falls back to combined artist strings from recent song
  /// totals, then to local track starts.
  String? get topArtistThisWeek {
    if (_accountWeekArtists.isNotEmpty) {
      String? top;
      var max = 0;
      for (final rollup in _accountWeekArtists) {
        final name = rollup.artistDisplay ?? rollup.artistKey;
        if (name.isEmpty || name == 'Unknown Artist') continue;
        if (rollup.playCount > max) {
          max = rollup.playCount;
          top = name;
        }
      }
      if (top != null) return top;
    }
    final counts = <String, int>{};
    if (_hasAccountHighlights) {
      for (final rollup in _accountRecent) {
        final artist = rollup.albumArtist ?? rollup.songArtist ?? '';
        if (artist.isEmpty || artist == 'Unknown Artist') continue;
        counts[artist] = (counts[artist] ?? 0) + rollup.playCount;
      }
      final cutoffMs = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      for (final event in _pendingEvents()) {
        if (event.plays <= 0 || event.occurredAtMs < cutoffMs) continue;
        final artist = event.albumArtist ?? event.songArtist ?? '';
        if (artist.isEmpty || artist == 'Unknown Artist') continue;
        counts[artist] = (counts[artist] ?? 0) + event.plays;
      }
    } else {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final event in _events) {
        if (event.timestamp.isBefore(cutoff)) break;
        if (event.artist.isEmpty || event.artist == 'Unknown Artist') continue;
        counts[event.artist] = (counts[event.artist] ?? 0) + 1;
      }
    }
    String? top;
    var max = 0;
    counts.forEach((artist, n) {
      if (n > max) {
        max = n;
        top = artist;
      }
    });
    return top;
  }

  bool _pendingDaysDirty = true;
  Map<String, int> _pendingDayMsCache = const <String, int>{};

  void attach(AudioController audio) {
    if (identical(_audio, audio)) return;
    _audio?.removeTickingListener(_onAudioChanged);
    _audio = audio;
    audio.addTickingListener(_onAudioChanged);
    unawaited(_load());
    // Event tracking starts immediately; events queue locally until a client
    // is attached and simply upload later.
    unawaited(_ensureSyncPipeline());
  }

  /// Wires (or clears) the API client used for uploads and account fetches.
  /// Called on every connect/disconnect; queued events survive disconnects.
  void attachClient(PlayerApiClient? client, {String? accountKey}) {
    final generation = ++_clientAttachGeneration;
    // Stop uploads immediately while an account transition is being checked.
    _client = null;
    if (client == null) return;
    unawaited(_attachClient(client, accountKey, generation));
  }

  /// Called when the server pushes `listening_stats_updated` (another device
  /// uploaded listening activity); refreshes the account view shortly after.
  void onRemoteStatsUpdated() {
    _accountRefreshDebounce?.cancel();
    _accountRefreshDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(refreshAccountStats());
    });
  }

  Future<void> refreshAccountStats() async {
    final client = _client;
    if (client == null || _fetchingAccount) return;
    _fetchingAccount = true;
    _accountError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        client.getListeningSummary(),
        client.getListeningDaily(days: _maxDailyEntries),
        client.getListeningRecent(days: 7),
      ]);
      _accountSummary = ListeningStatsSummary.fromJson(
        results[0] as Map<String, dynamic>,
      );
      _accountDailyMs = results[1] as Map<String, int>;
      _accountRecent = (results[2] as List<Map<String, dynamic>>)
          .map(ListeningSongRollup.fromJson)
          .toList();

      // Server-derived rollups (credited artists, albums). Guarded
      // individually: servers that predate the derivation layer 404 here,
      // and that must not fail the whole refresh.
      final rollupResults = await Future.wait([
        _fetchUncapped(
          (limit) => client.getListeningArtists(limit: limit),
          legacyLimit: 200,
        ),
        _fetchUncapped(
          (limit) => client.getListeningAlbums(limit: limit),
          legacyLimit: 200,
        ),
        _fetchUncapped(
          (limit) => client.getListeningArtists(days: 7, limit: limit),
          legacyLimit: 50,
        ),
      ]);
      // Also guarded individually: pre-5.x servers 404 here (the client maps
      // that to null) and no failure may cost the whole refresh.
      try {
        _spotifyImportStatus = await client.getSpotifyImportStatus();
      } catch (e) {
        debugPrint('[ListeningStats] Import status fetch failed: $e');
      }

      _accountArtists = _parseArtistRollups(rollupResults[0]);
      _accountAlbums = _parseAlbumRollups(rollupResults[1]);
      _accountWeekArtists = _parseArtistRollups(rollupResults[2]);

      _accountFetchedAt = DateTime.now();
      _accountCachedAt = null; // live data supersedes any restored cache
      _pendingDaysDirty = true;
      _invalidateSnapshot();
      // Keep the highlight cache current so an offline restart still shows
      // account-derived numbers instead of the wall-clock local fallback.
      unawaited(_persistAccountCache());
    } catch (e) {
      _accountError = 'Could not load listening stats. Check your connection.';
      debugPrint('[ListeningStats] Account stats fetch failed: $e');
    } finally {
      _fetchingAccount = false;
      notifyListeners();
    }
  }

  /// Fetches server-derived stats for an inclusive local-day range
  /// (`yyyy-mm-dd`, single day when [fromDay] == [toDay]). The default
  /// limit 0 asks for every ranked entry; servers that predate that special
  /// value get one retry at their default cap. Falls back to the persisted
  /// account-scoped period cache when offline or when a request fails.
  Future<ListeningPeriodStats?> loadPeriodStats({
    required String fromDay,
    required String toDay,
    int limit = 0,
  }) async {
    final client = _client;
    if (client == null) {
      return _readPeriodCache(fromDay: fromDay, toDay: toDay, limit: limit);
    }
    Future<Map<String, dynamic>> fetch(int fetchLimit) => fromDay == toDay
        ? client.getListeningDay(fromDay, limit: fetchLimit)
        : client.getListeningPeriod(
            from: fromDay,
            to: toDay,
            limit: fetchLimit,
          );
    try {
      final stats = ListeningPeriodStats.fromJson(await fetch(limit));
      unawaited(_writePeriodCache(
        fromDay: fromDay,
        toDay: toDay,
        limit: limit,
        stats: stats,
      ));
      return stats;
    } catch (_) {
      if (limit == 0) {
        try {
          final stats = ListeningPeriodStats.fromJson(await fetch(50));
          unawaited(_writePeriodCache(
            fromDay: fromDay,
            toDay: toDay,
            limit: limit,
            stats: stats,
          ));
          return stats;
        } catch (_) {}
      }
      return _readPeriodCache(fromDay: fromDay, toDay: toDay, limit: limit);
    }
  }

  /// Marks the Spotify import as removed after a confirmed successful
  /// server-side reset: rebuilds the summary with identical songs, totals
  /// and `generatedAtMs` but `hasSpotifyImport` false, so the persistent
  /// undo action disappears immediately even when the follow-up refresh
  /// races or fails. No-op when already false; a later successful refresh
  /// may set it true again after a new import.
  void markSpotifyImportRemoved() {
    if (!_accountSummary.hasSpotifyImport) return;
    _spotifyImportStatus = SpotifyImportStatus.none;
    _accountSummary = ListeningStatsSummary(
      songs: _accountSummary.songs,
      totalListenedMs: _accountSummary.totalListenedMs,
      totalPlays: _accountSummary.totalPlays,
      generatedAtMs: _accountSummary.generatedAtMs,
      activeDays: _accountSummary.activeDays,
    );
    _invalidateSnapshot();
    notifyListeners();
  }

  /// Matches Mobile's destructive reset: the account history, queued uploads,
  /// and this device's local summary stats are all cleared together.
  Future<void> resetEverywhere() async {
    final client = _client;
    if (client == null) {
      throw StateError('A server connection is required to reset stats.');
    }
    await client.postListeningReset();
    _tracker?.stop();
    await _outbox?.clear();
    _dailySeconds.clear();
    _events = <PlayEvent>[];
    _accountDailyMs = const <String, int>{};
    _accountRecent = const <ListeningSongRollup>[];
    _accountArtists = const <ListeningArtistRollup>[];
    _accountAlbums = const <ListeningAlbumRollup>[];
    _accountWeekArtists = const <ListeningArtistRollup>[];
    _accountSummary = ListeningStatsSummary.empty;
    _spotifyImportStatus = SpotifyImportStatus.none;
    _accountFetchedAt = DateTime.now();
    _accountCachedAt = null;
    _accountError = null;
    _pendingDaysDirty = true;
    _lastMinutesToday = 0;
    _invalidateSnapshot();
    _markDirty();
    await _persist();
    // The persisted highlight and period caches must reflect the reset too,
    // so a restart shows the emptied account rather than resurrecting old numbers.
    await _persistAccountCache();
    await _clearPeriodCache();
    notifyListeners();
    onReset?.call();
  }

  @visibleForTesting
  Future<void> loadForTests() => _load();

  @override
  void dispose() {
    _audio?.removeTickingListener(_onAudioChanged);
    _saveTimer?.cancel();
    _accountRefreshDebounce?.cancel();
    // Best-effort final flush so today's minutes — and any queued listening
    // events — survive a clean quit.
    _tracker?.flush();
    final outbox = _outbox;
    if (outbox != null) unawaited(outbox.persistNow());
    _syncer?.dispose();
    unawaited(_persist());
    super.dispose();
  }
}
