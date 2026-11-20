part of '../listening_stats_controller.dart';

extension _ListeningStatsAccountSync on ListeningStatsController {
  Future<void> _attachClient(
    PlayerApiClient client,
    String? accountKey,
    int generation,
  ) async {
    await _ensureSyncPipeline();
    if (generation != _clientAttachGeneration) return;

    final prefs = await SharedPreferences.getInstance();
    if (generation != _clientAttachGeneration) return;
    final normalizedKey = accountKey?.trim().isNotEmpty == true
        ? accountKey!.trim()
        : client.baseUrl;
    final previousKey =
        prefs.getString(ListeningStatsController._lastAccountKey);
    if (previousKey != null && previousKey != normalizedKey) {
      // Never attribute one account's offline queue or cached dashboard to a
      // different account on the same desktop installation.
      await _outbox?.clear();
      _accountDailyMs = const <String, int>{};
      _accountRecent = const <ListeningSongRollup>[];
      _accountArtists = const <ListeningArtistRollup>[];
      _accountAlbums = const <ListeningAlbumRollup>[];
      _accountWeekArtists = const <ListeningArtistRollup>[];
      _accountSummary = ListeningStatsSummary.empty;
      _accountFetchedAt = null;
      _accountCachedAt = null;
      _periodCache.clear();
      await prefs.remove(ListeningStatsController._accountCacheKey);
      await prefs.remove(ListeningStatsController._periodCacheKey);
      _pendingDaysDirty = true;
      _invalidateSnapshot();
      _notifyListeners();
    }
    _accountKey = normalizedKey;
    await prefs.setString(
      ListeningStatsController._lastAccountKey,
      normalizedKey,
    );
    if (generation != _clientAttachGeneration) return;

    _client = client;
    _syncer?.nudge(delay: const Duration(seconds: 2));
    unawaited(refreshAccountStats());
  }

  Future<void> _ensureSyncPipeline() {
    return _pipelineInit ??= _buildSyncPipeline();
  }

  Future<void> _buildSyncPipeline() async {
    try {
      final outbox = ListeningEventOutbox(
        read: _outboxStore.read,
        write: _outboxStore.write,
      );
      await outbox.load();
      _outbox = outbox;
      _pendingDaysDirty = true;
      // Queued events top up the account rollups, so the derived snapshot is
      // stale the moment one is queued or acknowledged.
      outbox.addListener(_invalidateSnapshot);

      _syncer = ListeningStatsSyncer(
        outbox: outbox,
        upload: _uploadEvents,
        canSync: () async =>
            _client != null && (_client!.sessionToken?.isNotEmpty ?? false),
        onSynced: () => unawaited(refreshAccountStats()),
      )..start();

      _tracker = ListeningEventTracker(
        clientKind: _clientKind,
        onEvent: (event) {
          outbox.add(event);
          _pendingDaysDirty = true;
          _syncer?.nudge();
        },
      );
    } catch (e) {
      debugPrint('[ListeningStats] Sync pipeline unavailable: $e');
    }
  }

  Future<bool> _uploadEvents(List<ListeningEvent> events) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.postListeningEvents(
        events.map((event) => event.toJson()).toList(),
      );
      return true;
    } catch (_) {
      return false; // stays queued; retried on the next cycle
    }
  }

  Future<T?> _fetchOrNull<T>(Future<T> Function() fetch) async {
    try {
      return await fetch();
    } catch (_) {
      return null; // Old server or transient failure — fall back gracefully.
    }
  }

  /// Fetches a rollup list with limit 0 ("return everything"). Servers that
  /// predate that special value reject it, so retry once at their old cap
  /// before giving up (pre-derivation servers 404 both attempts).
  Future<T?> _fetchUncapped<T>(
    Future<T> Function(int limit) fetch, {
    required int legacyLimit,
  }) async {
    return await _fetchOrNull(() => fetch(0)) ??
        await _fetchOrNull(() => fetch(legacyLimit));
  }

  List<ListeningSongRollup> _mergedSummarySongs() {
    final baseSongs = _hasAccountData ? _accountSummary.songs : _accountRecent;
    final pending = _pendingEvents();
    if (!_hasAccountData && baseSongs.isEmpty && pending.isEmpty) {
      return const <ListeningSongRollup>[];
    }
    final merged = <String, ListeningSongRollup>{
      for (final song in baseSongs) song.songId: song,
    };
    for (final event in pending) {
      final existing = merged[event.songId];
      merged[event.songId] = ListeningSongRollup(
        songId: event.songId,
        playCount: (existing?.playCount ?? 0) + event.plays,
        listenedMs: (existing?.listenedMs ?? 0) + event.listenedMs,
        firstPlayedMs: existing?.firstPlayedMs == null
            ? event.occurredAtMs
            : (existing!.firstPlayedMs! < event.occurredAtMs
                ? existing.firstPlayedMs
                : event.occurredAtMs),
        lastPlayedMs: existing?.lastPlayedMs == null
            ? event.occurredAtMs
            : (existing!.lastPlayedMs! > event.occurredAtMs
                ? existing.lastPlayedMs
                : event.occurredAtMs),
        songTitle: existing?.songTitle ?? event.songTitle,
        songArtist: existing?.songArtist ?? event.songArtist,
        albumId: existing?.albumId ?? event.albumId,
        album: existing?.album ?? event.album,
        albumArtist: existing?.albumArtist ?? event.albumArtist,
      );
    }
    return merged.values.toList();
  }
}

List<ListeningArtistRollup> _parseArtistRollups(
  List<Map<String, dynamic>>? raw,
) {
  if (raw == null) return const <ListeningArtistRollup>[];
  return raw
      .map(ListeningArtistRollup.fromJson)
      .where((rollup) => rollup.artistKey.isNotEmpty)
      .toList();
}

List<ListeningAlbumRollup> _parseAlbumRollups(
  List<Map<String, dynamic>>? raw,
) {
  if (raw == null) return const <ListeningAlbumRollup>[];
  return raw
      .map(ListeningAlbumRollup.fromJson)
      .where((rollup) => rollup.albumKey.isNotEmpty)
      .toList();
}
