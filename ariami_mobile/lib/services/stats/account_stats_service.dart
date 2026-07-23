import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart'
    show
        ListeningEvent,
        ListeningEventOutbox,
        ListeningStatsSummary,
        ListeningStatsSyncer,
        WsMessageType;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/song_stats.dart';
import '../api/connection_service.dart';
import 'streaming_stats_service.dart';
import 'period_stats_cache.dart';

/// Keeps this device's listening stats in sync with the account on the server
/// and feeds the account-wide view back into [StreamingStatsService].
///
/// How it works, end to end:
/// - [StreamingStatsService] mirrors every credited play / time segment into
///   a durable outbox (works fully offline).
/// - A syncer drains the outbox to `/api/v2/listening/events` whenever the
///   device is connected and authenticated. Events carry stable ids, so
///   retries and crash-replays can never double-count.
/// - After uploads (and on `listening_stats_updated` pushes caused by the
///   account's other devices), the merged summary is re-fetched and shown via
///   the stats overlay: server rollups + still-pending local events.
/// - Period stats screens listen to this service for pending-outbox changes
///   so offline period views can recompute their display overlay immediately
///   without touching the outbox file themselves.
/// - On first login this device's pre-existing local stats are imported once
///   as a deterministic baseline, so history isn't lost.
///
/// Everything is automatic — no user interaction anywhere.
class AccountStatsService extends ChangeNotifier {
  static final AccountStatsService _instance = AccountStatsService._internal();
  factory AccountStatsService() => _instance;
  AccountStatsService._internal();

  static const String _summaryFileName = 'account_listening_summary.json';
  static const String _outboxFileName = 'listening_events_outbox.json';
  static const String _baselineDoneKeyPrefix = 'stats_baseline_done_';
  static const String _pendingResetKey = 'stats_pending_account_reset';
  static const String _lastUserKey = 'stats_last_account_user';
  static const int _baselineBatchSize = 300;

  final ConnectionService _connection = ConnectionService();
  final StreamingStatsService _stats = StreamingStatsService();

  ListeningEventOutbox? _outbox;
  ListeningStatsSyncer? _syncer;
  SharedPreferences? _prefs;
  ListeningStatsSummary _summary = ListeningStatsSummary.empty;
  bool _hasFetchedSummary = false;
  bool _initialized = false;
  Future<void>? _initialization;
  bool _baselineRunning = false;
  bool _fetchingSummary = false;
  Timer? _overlayDebounce;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<dynamic>? _wsSub;

  /// Event ids the server has accepted that are still (briefly) in the outbox.
  /// Period overlays exclude these so a fresh base is not double-counted.
  final Set<String> _ackedInFlightEventIds = <String>{};

  Future<String> _fileDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize().whenComplete(() {
      // A failed initialization must remain retryable (for example, if the
      // platform storage plugin was temporarily unavailable). Successful
      // initialization keeps the completed future as the cheap fast path.
      if (!_initialized) _initialization = null;
    });
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await _fileDir();
    final outboxPath = '$dir/$_outboxFileName';

    final outbox = ListeningEventOutbox(
      read: () async {
        final file = File(outboxPath);
        return file.existsSync() ? file.readAsString() : null;
      },
      write: (contents) => File(outboxPath).writeAsString(contents),
    );
    await outbox.load();
    _outbox = outbox;
    outbox.addListener(_onOutboxChanged);

    await _loadCachedSummary();

    _syncer = ListeningStatsSyncer(
      outbox: outbox,
      upload: _uploadBatch,
      canSync: () async => _canSync,
      onBatchAccepted: _onBatchAccepted,
      onSynced: () => unawaited(refreshSummary()),
    );

    // Every credited play / segment flows into the outbox.
    _stats.onListeningEvent = _onLocalEvent;

    // Sync opportunities: reconnects and stats pushes from other devices.
    _connectionSub = _connection.connectionStateStream.listen((connected) {
      if (connected) {
        unawaited(_onBecameConnected());
      }
    });
    _wsSub = _connection.webSocketMessages.listen((message) {
      if (message.type == WsMessageType.listeningStatsUpdated) {
        unawaited(refreshSummary());
      }
    });

    _syncer!.start();
    if (_canSync) {
      unawaited(_onBecameConnected());
    }
    _recomputeOverlay();
    _initialized = true;
    // Outbox.load does not notify; surface any restored pending events so a
    // stats screen already open (or opening) can overlay them immediately.
    notifyListeners();
    print('[AccountStatsService] Initialized '
        '(${outbox.length} events pending upload)');
  }

  bool get _canSync => _connection.isConnected && _connection.isAuthenticated;

  /// Snapshot of events still waiting to upload. Period screens overlay these
  /// on the server/cache base; do not read the outbox file from UI code.
  List<ListeningEvent> get pendingListeningEvents {
    final outbox = _outbox;
    if (outbox == null) return const <ListeningEvent>[];
    return outbox.peek(outbox.length);
  }

  /// Server-acked event ids that are still pending in the outbox.
  ///
  /// Period screens pass this as the overlay exclude set so a freshly fetched
  /// base is not double-counted during the accept→drain race.
  Set<String> get syncedPendingEventIds =>
      Set<String>.unmodifiable(_ackedInFlightEventIds);

  /// Drains the outbox now (no-op when the syncer cannot sync).
  Future<void> syncPendingEventsNow() async {
    await _syncer?.syncNow();
  }

  // ---------------------------------------------------------------------------
  // Event flow
  // ---------------------------------------------------------------------------

  void _onLocalEvent(ListeningEvent event) {
    final outbox = _outbox;
    if (outbox == null) return;
    outbox.add(event);
    _syncer?.nudge();
    // Notify + overlay recompute come solely from [_onOutboxChanged].
  }

  /// Outbox membership changed (local add, successful upload drain, clear).
  void _onOutboxChanged() {
    _pruneAckedInFlight();
    // Period views recompute their overlay immediately from pending events.
    notifyListeners();
    // All-time overlay: debounce local churn; also recompute eventually when
    // events drain so the account view doesn't stay inflated after upload.
    _scheduleOverlayRecompute();
  }

  void _onBatchAccepted(List<String> eventIds) {
    if (eventIds.isEmpty) return;
    _ackedInFlightEventIds.addAll(eventIds);
    // Still in outbox until removeByIds finishes — notify so period overlay
    // excludes them before the drain notification arrives.
    notifyListeners();
  }

  void _pruneAckedInFlight() {
    if (_ackedInFlightEventIds.isEmpty) return;
    final outbox = _outbox;
    if (outbox == null || outbox.isEmpty) {
      _ackedInFlightEventIds.clear();
      return;
    }
    final pendingIds =
        outbox.peek(outbox.length).map((e) => e.eventId).toSet();
    _ackedInFlightEventIds.removeWhere((id) => !pendingIds.contains(id));
  }

  void _clearAckedInFlight() {
    if (_ackedInFlightEventIds.isEmpty) return;
    _ackedInFlightEventIds.clear();
  }

  Future<bool> _uploadBatch(List<ListeningEvent> events) async {
    if (!_canSync) return false;
    // An account reset requested while offline must land before new uploads,
    // otherwise the fresh events would be wiped by the late reset.
    if (!await _completePendingResetIfAny()) return false;
    final client = _connection.apiClient;
    if (client == null) return false;
    try {
      await client.postListeningEvents(
        events.map((event) => event.toJson()).toList(),
      );
      return true;
    } catch (e) {
      print('[AccountStatsService] Upload failed (will retry): $e');
      return false;
    }
  }

  Future<void> _onBecameConnected() async {
    if (!_canSync) return;
    await _handleAccountChangeIfAny();
    await _completePendingResetIfAny();
    await _maybeRunBaselineImport();
    await _syncer?.syncNow();
    await refreshSummary();
  }

  // ---------------------------------------------------------------------------
  // Summary / overlay
  // ---------------------------------------------------------------------------

  /// Fetches the merged account summary and refreshes the overlay.
  Future<void> refreshSummary() async {
    if (!_canSync || _fetchingSummary) return;
    final client = _connection.apiClient;
    if (client == null) return;
    _fetchingSummary = true;
    try {
      final json = await client.getListeningSummary();
      _summary = ListeningStatsSummary.fromJson(json);
      _hasFetchedSummary = true;
      await _persistSummary(json);
      _recomputeOverlay();
    } catch (e) {
      print('[AccountStatsService] Summary fetch failed: $e');
    } finally {
      _fetchingSummary = false;
    }
  }

  Future<void> _loadCachedSummary() async {
    try {
      final file = File('${await _fileDir()}/$_summaryFileName');
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return;
      _summary = ListeningStatsSummary.fromJson(json);
      _hasFetchedSummary = _summary.generatedAtMs > 0;
    } catch (_) {
      // A corrupt cache just means we wait for the next fetch.
    }
  }

  Future<void> _persistSummary(Map<String, dynamic> json) async {
    try {
      final file = File('${await _fileDir()}/$_summaryFileName');
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Best-effort cache.
    }
  }

  void _scheduleOverlayRecompute() {
    _overlayDebounce ??= Timer(const Duration(seconds: 2), () {
      _overlayDebounce = null;
      _recomputeOverlay();
    });
  }

  /// Builds the account-wide view: server rollups plus local events that are
  /// still waiting for upload (so offline listening shows up immediately),
  /// and hands it to [StreamingStatsService] as the display overlay.
  void _recomputeOverlay() {
    // Until this device has account data, keep the plain local view.
    if (!_hasFetchedSummary) {
      _stats.setAccountStatsOverlay(null);
      return;
    }

    final merged = <String, SongStats>{};
    for (final rollup in _summary.songs) {
      merged[rollup.songId] = SongStats(
        songId: rollup.songId,
        playCount: rollup.playCount,
        totalTime: Duration(milliseconds: rollup.listenedMs),
        firstPlayed: rollup.firstPlayedMs != null
            ? DateTime.fromMillisecondsSinceEpoch(rollup.firstPlayedMs!)
            : null,
        lastPlayed: rollup.lastPlayedMs != null
            ? DateTime.fromMillisecondsSinceEpoch(rollup.lastPlayedMs!)
            : null,
        songTitle: rollup.songTitle,
        songArtist: rollup.songArtist,
        albumId: rollup.albumId,
        album: rollup.album,
        albumArtist: rollup.albumArtist,
      );
    }

    final outbox = _outbox;
    if (outbox != null) {
      for (final event in outbox.peek(outbox.length)) {
        final existing = merged[event.songId];
        final occurred =
            DateTime.fromMillisecondsSinceEpoch(event.occurredAtMs);
        if (existing == null) {
          merged[event.songId] = SongStats(
            songId: event.songId,
            playCount: event.plays,
            totalTime: Duration(milliseconds: event.listenedMs),
            firstPlayed: occurred,
            lastPlayed: occurred,
            songTitle: event.songTitle,
            songArtist: event.songArtist,
            albumId: event.albumId,
            album: event.album,
            albumArtist: event.albumArtist,
          );
        } else {
          merged[event.songId] = existing.copyWith(
            playCount: existing.playCount + event.plays,
            totalTime:
                existing.totalTime + Duration(milliseconds: event.listenedMs),
            lastPlayed: existing.lastPlayed == null ||
                    occurred.isAfter(existing.lastPlayed!)
                ? occurred
                : existing.lastPlayed,
          );
        }
      }
    }

    _stats.setAccountStatsOverlay(
      merged.values.toList(),
      activeDays: _summary.activeDays,
    );
  }

  // ---------------------------------------------------------------------------
  // Baseline import
  // ---------------------------------------------------------------------------

  /// One-time import of this device's pre-sync local history into the
  /// account. Deterministic eventIds (`baseline:<deviceId>:<songId>`) make it
  /// idempotent even if the "done" flag is lost.
  Future<void> _maybeRunBaselineImport() async {
    if (_baselineRunning || !_canSync) return;
    final client = _connection.apiClient;
    final userId = _connection.userId;
    final deviceId = client?.deviceId;
    if (client == null || userId == null || deviceId == null) return;

    final doneKey = '$_baselineDoneKeyPrefix${userId}_$deviceId';
    if (_prefs?.getBool(doneKey) ?? false) return;

    _baselineRunning = true;
    try {
      final localStats = _stats.getLocalDeviceStats();
      final events = <Map<String, dynamic>>[];
      for (final stat in localStats) {
        if (stat.playCount <= 0 && stat.totalTime <= Duration.zero) continue;
        final anchor = stat.lastPlayed ?? stat.firstPlayed ?? DateTime.now();
        events.add(ListeningEvent(
          eventId: 'baseline:$deviceId:${stat.songId}',
          songId: stat.songId,
          listenedMs: stat.totalTime.inMilliseconds,
          plays: stat.playCount,
          occurredAtMs: anchor.toUtc().millisecondsSinceEpoch,
          tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          songTitle: stat.songTitle,
          songArtist: stat.songArtist,
          albumId: stat.albumId,
          album: stat.album,
          albumArtist: stat.albumArtist,
        ).toJson());
      }

      for (var i = 0; i < events.length; i += _baselineBatchSize) {
        final batch = events.sublist(
          i,
          i + _baselineBatchSize > events.length
              ? events.length
              : i + _baselineBatchSize,
        );
        await client.postListeningEvents(batch);
      }

      await _prefs?.setBool(doneKey, true);
      print('[AccountStatsService] Baseline import complete '
          '(${events.length} songs)');
    } catch (e) {
      // Not marked done — retried on the next connection.
      print('[AccountStatsService] Baseline import failed (will retry): $e');
    } finally {
      _baselineRunning = false;
    }
  }

  /// Re-syncs this device's history after a backup import replaced or merged
  /// the local stats database.
  ///
  /// The cached account summary predates the import, so the display falls
  /// back to the freshly imported local stats immediately; the baseline is
  /// then re-uploaded (the server replaces this device's previous baseline
  /// per song rather than stacking it) and the account view returns once the
  /// fresh summary lands. Works offline too: the re-baseline simply runs on
  /// the next connection.
  Future<void> resyncBaselineAfterImport() async {
    // Best-effort by design: a stats-sync hiccup must never fail the user's
    // backup import — the local import has already succeeded at this point.
    try {
      if (!_initialized) await initialize();

      // Show the imported local stats right away instead of a stale account
      // overlay that doesn't contain them yet.
      _summary = ListeningStatsSummary.empty;
      _hasFetchedSummary = false;
      try {
        final file = File('${await _fileDir()}/$_summaryFileName');
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      _stats.setAccountStatsOverlay(null);

      // Clear the baseline-done flags so the import is (re-)uploaded. When
      // not signed in yet, clear all of them — whichever account logs in
      // next should adopt this device's history.
      final prefs = _prefs;
      if (prefs != null) {
        for (final key in prefs.getKeys().toList()) {
          if (key.startsWith(_baselineDoneKeyPrefix)) {
            await prefs.remove(key);
          }
        }
      }

      if (_canSync) {
        await _maybeRunBaselineImport();
        await _syncer?.syncNow();
        await refreshSummary();
      }
    } catch (e) {
      print('[AccountStatsService] Baseline resync after import failed '
          '(will retry on next connection): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Reset / account changes
  // ---------------------------------------------------------------------------

  /// Wipes listening stats locally and across the whole account. When the
  /// server can't be reached the reset is remembered and completes on the
  /// next connection (before any further uploads).
  Future<void> resetEverywhere() async {
    await PeriodStatsCache().clearScope(PeriodStatsCache.scopeFor(
      userId: _connection.userId,
      serverInfo: _connection.serverInfo,
    ));
    await _stats.resetAllStats();
    await _outbox?.clear();
    _clearAckedInFlight();
    _summary = ListeningStatsSummary.empty;
    _hasFetchedSummary = false;
    try {
      final file = File('${await _fileDir()}/$_summaryFileName');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
    _stats.setAccountStatsOverlay(null);
    notifyListeners();

    // The local history is gone; a later "baseline import" would only upload
    // an empty set, but mark it done for clarity.
    final userId = _connection.userId;
    final deviceId = _connection.apiClient?.deviceId;
    if (userId != null && deviceId != null) {
      await _prefs?.setBool('$_baselineDoneKeyPrefix${userId}_$deviceId', true);
    }

    await _prefs?.setBool(_pendingResetKey, true);
    await _completePendingResetIfAny();
  }

  /// Runs a remembered account reset. Returns true when there is nothing
  /// (left) to do, false when the reset is still pending.
  Future<bool> _completePendingResetIfAny() async {
    if (!(_prefs?.getBool(_pendingResetKey) ?? false)) return true;
    if (!_canSync) return false;
    final client = _connection.apiClient;
    if (client == null) return false;
    try {
      await client.postListeningReset();
      await _prefs?.setBool(_pendingResetKey, false);
      print('[AccountStatsService] Account listening stats reset on server');
      return true;
    } catch (e) {
      print('[AccountStatsService] Server reset failed (will retry): $e');
      return false;
    }
  }

  /// Clears everything this service keeps on the device — queued events,
  /// cached summary, overlay — without touching the account on the server.
  /// Used by "forget this server" style local resets.
  Future<void> clearLocalOnly() async {
    await PeriodStatsCache().clearAll();
    await _outbox?.clear();
    _clearAckedInFlight();
    _summary = ListeningStatsSummary.empty;
    _hasFetchedSummary = false;
    try {
      final file = File('${await _fileDir()}/$_summaryFileName');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
    _stats.setAccountStatsOverlay(null);
    notifyListeners();
    await _prefs?.setBool(_pendingResetKey, false);
    await _prefs?.remove(_lastUserKey);
  }

  /// A different account on the same device must never inherit the previous
  /// account's queued events or cached summary.
  Future<void> _handleAccountChangeIfAny() async {
    final userId = _connection.userId;
    if (userId == null) return;
    final last = _prefs?.getString(_lastUserKey);
    if (last == userId) return;
    if (last != null) {
      print('[AccountStatsService] Account changed ($last -> $userId): '
          'clearing queued events and cached summary');
      await _outbox?.clear();
      _clearAckedInFlight();
      _summary = ListeningStatsSummary.empty;
      _hasFetchedSummary = false;
      try {
        final file = File('${await _fileDir()}/$_summaryFileName');
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      _stats.setAccountStatsOverlay(null);
      notifyListeners();
      await _prefs?.setBool(_pendingResetKey, false);
    }
    await _prefs?.setString(_lastUserKey, userId);
  }

  /// Flushes pending state, e.g. when the app is backgrounded.
  Future<void> flush() async {
    await _outbox?.persistNow();
  }

  /// Process-lived singleton — do not call in production.
  ///
  /// [ChangeNotifier.dispose] marks the notifier dead so later
  /// [notifyListeners] throws; this override only tears down timers/subs for
  /// tests and deliberately skips `super.dispose()`.
  @override
  // ignore: must_call_super
  void dispose() {
    assert(() {
      // ignore: avoid_print
      print('[AccountStatsService] dispose() called — test-only cleanup; '
          'singleton must not be disposed in production');
      return true;
    }());
    _overlayDebounce?.cancel();
    _overlayDebounce = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _wsSub?.cancel();
    _wsSub = null;
    _syncer?.dispose();
    _syncer = null;
    final outbox = _outbox;
    if (outbox != null) {
      outbox.removeListener(_onOutboxChanged);
      outbox.dispose();
    }
    _outbox = null;
    _clearAckedInFlight();
    // Do not call super.dispose() — keeps ChangeNotifier usable if this
    // singleton is touched again after a test tear-down.
  }
}
