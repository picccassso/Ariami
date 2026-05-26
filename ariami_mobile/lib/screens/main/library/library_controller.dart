import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/api_models.dart';
import '../../../models/download_task.dart';
import '../../../models/song.dart';
import '../../../models/websocket_models.dart';
import '../../../services/api/connection_service.dart';
import '../../../services/cache/cache_manager.dart';
import '../../../services/download/download_manager.dart';
import '../../../services/library/library_read_facade.dart';
import '../../../services/library/library_pin_storage.dart';
import '../../../services/offline/offline_manual_reconnect.dart';
import '../../../services/offline/offline_playback_service.dart';
import '../../../services/playback_manager.dart';
import '../../../services/playlist_service.dart';
import '../../../services/stats/streaming_stats_service.dart';
import '../../../services/quality/quality_settings_service.dart';
import '../../../utils/artwork_url.dart';
import 'library_state.dart';

/// Controller for the LibraryScreen.
/// Manages all business logic and state for the library.
class LibraryController extends ChangeNotifier {
  // Singleton pattern
  static final LibraryController _instance = LibraryController._internal();
  factory LibraryController() => _instance;

  // Services
  late final ConnectionService _connectionService;
  late final PlaybackManager _playbackManager;
  late final PlaylistService _playlistService;
  late final OfflinePlaybackService _offlineService;
  late final DownloadManager _downloadManager;
  late final CacheManager _cacheManager;
  late final StreamingStatsService _statsService;

  // Preference keys
  static const String _viewPreferenceKey = 'library_view_grid';
  static const String _albumsSectionKey = 'library_section_albums';
  static const String _songsSectionKey = 'library_section_songs';
  static const String _mixedModeKey = 'library_mixed_mode';
  static const String _lastPlayedKey = 'library_last_played';

  // Duration retry constants
  static const int _maxDurationRetries = 3;
  static const Duration _durationRetryDelay = Duration(seconds: 3);

  // State
  LibraryState _state = const LibraryState();
  LibraryState get state => _state;

  // Multi-Selection State
  bool _isSelectionModeActive = false;
  bool get isSelectionModeActive => _isSelectionModeActive;

  final Set<String> _selectedPlaylistIds = {};
  Set<String> get selectedPlaylistIds => _selectedPlaylistIds;

  final Set<String> _selectedAlbumIds = {};
  Set<String> get selectedAlbumIds => _selectedAlbumIds;

  final Set<String> _selectedSongIds = {};
  Set<String> get selectedSongIds => _selectedSongIds;

  Set<String>? _queuedSongIdsForTest;

  int get totalSelectedCount =>
      _selectedPlaylistIds.length +
      _selectedAlbumIds.length +
      _selectedSongIds.length;

  BatchDownloadSummary get batchDownloadSummary => _computeBatchDownloadSummary();

  bool get hasBatchItemsToDownload => !batchDownloadSummary.allSaved;

  void enterSelectionMode() {
    _isSelectionModeActive = true;
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    notifyListeners();
  }

  void exitSelectionMode() {
    _isSelectionModeActive = false;
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    notifyListeners();
  }

  void togglePlaylistSelection(String playlistId) {
    if (_selectedPlaylistIds.contains(playlistId)) {
      _selectedPlaylistIds.remove(playlistId);
    } else {
      _selectedPlaylistIds.add(playlistId);
    }
    notifyListeners();
  }

  void toggleAlbumSelection(String albumId) {
    if (_selectedAlbumIds.contains(albumId)) {
      _selectedAlbumIds.remove(albumId);
    } else {
      _selectedAlbumIds.add(albumId);
    }
    notifyListeners();
  }

  void toggleSongSelection(String songId) {
    if (_selectedSongIds.contains(songId)) {
      _selectedSongIds.remove(songId);
    } else {
      _selectedSongIds.add(songId);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    // Select all currently visible regular and liked playlists, albums and songs
    final visiblePlaylists = _playlistService.playlists;
    for (final p in visiblePlaylists) {
      _selectedPlaylistIds.add(p.id);
    }
    
    final visibleAlbums = _state.albumsToShow;
    for (final a in visibleAlbums) {
      _selectedAlbumIds.add(a.id);
    }

    if (_state.isOfflineMode) {
      for (final s in _state.offlineSongs) {
        _selectedSongIds.add(s.id);
      }
    } else {
      for (final s in _state.onlineSongsToShow) {
        _selectedSongIds.add(s.id);
      }
    }

    notifyListeners();
  }

  void clearSelection() {
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    notifyListeners();
  }

  Set<String> _resolveSelectedSongIds() {
    final resolvedSongIds = <String>{};
    resolvedSongIds.addAll(_selectedSongIds);

    for (final playlistId in _selectedPlaylistIds) {
      final localPlaylist = _playlistService.getPlaylist(playlistId);
      if (localPlaylist != null) {
        resolvedSongIds.addAll(localPlaylist.songIds);
      }
    }

    for (final albumId in _selectedAlbumIds) {
      final albumSongs = _state.songs
          .where((s) => s.albumId == albumId)
          .map((s) => s.id);
      resolvedSongIds.addAll(albumSongs);
    }

    return resolvedSongIds;
  }

  bool _isSongInDownloadQueue(String songId) {
    if (_queuedSongIdsForTest != null) {
      return _queuedSongIdsForTest!.contains(songId);
    }
    return _downloadManager.queue.any((task) => task.songId == songId);
  }

  bool _isPlaylistFullyDownloaded(String playlistId) {
    final playlist = _playlistService.getPlaylist(playlistId);
    if (playlist == null || playlist.songIds.isEmpty) return false;
    return playlist.songIds.every((id) => _state.isSongDownloaded(id));
  }

  ({List<String> albumIds, List<String> playlistIds})
      _filteredContainersForEnqueue() {
    final albumIds = _selectedAlbumIds
        .where((id) => !_state.isAlbumFullyDownloaded(id))
        .toList();

    final playlistIds = <String>[];
    for (final playlistId in _selectedPlaylistIds) {
      final localPlaylist = _playlistService.getPlaylist(playlistId);
      if (localPlaylist != null) {
        continue;
      }
      if (!_isPlaylistFullyDownloaded(playlistId)) {
        playlistIds.add(playlistId);
      }
    }

    return (albumIds: albumIds, playlistIds: playlistIds);
  }

  BatchDownloadSummary _computeBatchDownloadSummary() {
    final resolvedSongIds = _resolveSelectedSongIds();
    var alreadySavedCount = 0;
    var inQueueCount = 0;
    var toDownloadCount = 0;

    for (final songId in resolvedSongIds) {
      if (_state.isSongDownloaded(songId)) {
        alreadySavedCount++;
      } else if (_isSongInDownloadQueue(songId)) {
        inQueueCount++;
      } else {
        toDownloadCount++;
      }
    }

    final containers = _filteredContainersForEnqueue();
    final hasEnqueueTargets = toDownloadCount > 0 ||
        containers.albumIds.isNotEmpty ||
        containers.playlistIds.isNotEmpty;

    return BatchDownloadSummary(
      containerCount: totalSelectedCount,
      resolvedSongCount: resolvedSongIds.length,
      alreadySavedCount: alreadySavedCount,
      inQueueCount: inQueueCount,
      toDownloadCount: toDownloadCount,
      hasEnqueueTargets: hasEnqueueTargets,
    );
  }

  List<String> _songIdsNeedingDownload(Iterable<String> songIds) {
    return songIds
        .where(
          (id) =>
              !_state.isSongDownloaded(id) && !_isSongInDownloadQueue(id),
        )
        .toList();
  }

  Future<int> downloadSelectedItems() async {
    if (totalSelectedCount == 0) return 0;

    final summary = batchDownloadSummary;
    if (summary.allSaved) return 0;

    final resolvedSongIds = _resolveSelectedSongIds();
    final songIdsToEnqueue = _songIdsNeedingDownload(resolvedSongIds);
    final containers = _filteredContainersForEnqueue();
    final playlistIdsList = _selectedPlaylistIds.toList();

    exitSelectionMode();

    int count = 0;
    try {
      count = await _downloadManager.enqueueDownloadJob(
        songIds: songIdsToEnqueue,
        albumIds: containers.albumIds,
        playlistIds: containers.playlistIds,
      );
    } catch (e, stackTrace) {
      print('DownloadManager enqueueDownloadJob failed, falling back to local resolver: $e\n$stackTrace');

      // Fallback resolver
      final allFallbackSongIds = <String>{...songIdsToEnqueue};

      // Add remaining song IDs from selected albums
      for (final albumId in containers.albumIds) {
        final albumSongs = _state.songs
            .where((s) => s.albumId == albumId)
            .map((s) => s.id);
        allFallbackSongIds.addAll(_songIdsNeedingDownload(albumSongs));
      }

      for (final songId in allFallbackSongIds) {
        // Try to find song in _state.songs
        final songMatch = _state.songs.where((s) => s.id == songId);

        String? title;
        String? artist;
        String? albumId;
        int duration = 0;
        int? trackNumber;

        if (songMatch.isNotEmpty) {
          final song = songMatch.first;
          title = song.title;
          artist = song.artist;
          albumId = song.albumId;
          duration = song.duration;
          trackNumber = song.trackNumber;
        } else {
          // Check in selected playlists for cached song metadata
          for (final playlistId in playlistIdsList) {
            final localPlaylist = _playlistService.getPlaylist(playlistId);
            if (localPlaylist != null &&
                localPlaylist.songIds.contains(songId)) {
              title = localPlaylist.songTitles[songId];
              artist = localPlaylist.songArtists[songId];
              albumId = localPlaylist.songAlbumIds[songId];
              duration = localPlaylist.songDurations[songId] ?? 0;
              break;
            }
          }
        }

        // Apply defaults if still not resolved
        title ??= 'Song $songId';
        artist ??= 'Unknown Artist';
        duration ??= 0;

        // Try to resolve album details
        String? albumName;
        String? albumArtist;
        if (albumId != null) {
          final albumMatch = _state.albums.where((a) => a.id == albumId);
          if (albumMatch.isNotEmpty) {
            albumName = albumMatch.first.title;
            albumArtist = albumMatch.first.artist;
          }
        }

        final baseUrl = _connectionService.apiClient?.baseUrl;
        final albumArt = (albumId != null && baseUrl != null)
            ? '$baseUrl/artwork/$albumId'
            : '';

        try {
          await _downloadManager.downloadSong(
            songId: songId,
            title: title,
            artist: artist,
            albumId: albumId,
            albumName: albumName,
            albumArtist: albumArtist,
            albumArt: albumArt,
            duration: duration,
            trackNumber: trackNumber,
            totalBytes: 0,
          );
          count++;
        } catch (downloadErr) {
          print('Failed to enqueue fallback download for song $songId: $downloadErr');
        }
      }
    }

    return count;
  }

  // Duration retry tracking
  bool _durationsPending = false;
  int _durationRetryCount = 0;

  // Signature for download state comparison
  String _lastCompletedDownloadsSignature = '';
  int _lastHandledSyncToken = 0;

  // Timers
  Timer? _durationRetryTimer;
  Timer? _downloadStateRefreshTimer;
  Timer? _cacheRefreshTimer;

  // Stream subscriptions
  StreamSubscription<OfflineMode>? _offlineSubscription;
  StreamSubscription<CacheUpdateEvent>? _cacheSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<DownloadTask>>? _downloadSubscription;
  StreamSubscription<WsMessage>? _webSocketSubscription;

  bool _isInitialized = false;
  bool _isLibraryLoadInFlight = false;
  bool _pendingBackgroundReload = false;
  bool _pendingScrollRestore = false;

  @visibleForTesting
  int libraryLoadAttemptsForTest = 0;

  /// Returns true once when the UI should restore scroll after a library update.
  bool consumeScrollRestorePending() {
    if (!_pendingScrollRestore) return false;
    _pendingScrollRestore = false;
    return true;
  }

  LibraryController._internal() {
    _connectionService = ConnectionService();
    _playbackManager = PlaybackManager();
    _playlistService = PlaylistService();
    _offlineService = OfflinePlaybackService();
    _downloadManager = DownloadManager();
    _cacheManager = CacheManager();
    _statsService = StreamingStatsService();
  }

  /// Initialize the controller and load initial data
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadUiPreferences();
    await _loadPlayedHistory();
    await _loadPinnedItems();
    await _loadLibrary();
    await _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
    await _loadDownloadedSongs();
    await _loadCachedSongs();
    _setupStreamListeners();
  }

  void _setupStreamListeners() {
    // Listen to offline state changes
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      unawaited(_loadLibrary(background: true));
    });

    // Listen to connection state changes
    _connectionSubscription =
        _connectionService.connectionStateStream.listen((isConnected) {
      if (isConnected) {
        unawaited(_loadLibrary(background: true));
        unawaited(_loadDownloadedSongs());
      }
    });

    // Listen to cache updates
    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((event) {
      if (!event.affectsSongCache) return;
      _scheduleCachedSongsRefresh();
    });

    // Listen to download queue changes
    _downloadSubscription = _downloadManager.queueStream.listen((tasks) {
      _scheduleDownloadedSongsRefresh(tasks);
    });

    // Listen for library updates from WebSocket
    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleWebSocketMessage,
    );
  }

  @override
  void dispose() {
    // Singleton - listeners and subscriptions live for app lifetime
    // Still call super to satisfy @mustCallSuper
    super.dispose();
  }

  // ============================================================================
  // State Updates
  // ============================================================================

  void _updateState(LibraryState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  // ============================================================================
  // UI Preferences
  // ============================================================================

  Future<void> _loadUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _updateState(_state.copyWith(
      isGridView: prefs.getBool(_viewPreferenceKey) ?? true,
      albumsExpanded: prefs.getBool(_albumsSectionKey) ?? true,
      songsExpanded: prefs.getBool(_songsSectionKey) ?? false,
      isMixedMode: prefs.getBool(_mixedModeKey) ?? false,
    ));
  }

  Future<void> toggleViewMode() async {
    final newValue = !_state.isGridView;
    _updateState(_state.copyWith(isGridView: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewPreferenceKey, newValue);
  }

  Future<void> toggleAlbumsExpanded() async {
    final newValue = !_state.albumsExpanded;
    _updateState(_state.copyWith(albumsExpanded: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_albumsSectionKey, newValue);
  }

  Future<void> toggleSongsExpanded() async {
    final newValue = !_state.songsExpanded;
    _updateState(_state.copyWith(songsExpanded: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_songsSectionKey, newValue);
  }

  Future<void> toggleMixedMode() async {
    final newValue = !_state.isMixedMode;
    _updateState(_state.copyWith(isMixedMode: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mixedModeKey, newValue);
  }

  Future<void> markAlbumPlayed(String albumId) =>
      _markItemPlayed('album:$albumId');

  Future<void> markPlaylistPlayed(String playlistId) =>
      _markItemPlayed('playlist:$playlistId');

  void toggleShowDownloadedOnly() {
    _updateState(
        _state.copyWith(showDownloadedOnly: !_state.showDownloadedOnly));
  }

  Future<void> _loadPlayedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_lastPlayedKey);
    if (jsonString == null || jsonString.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final playedHistory = <String, DateTime>{};

      decoded.forEach((key, value) {
        final epochMs = value is int ? value : int.tryParse(value.toString());
        if (epochMs != null) {
          playedHistory[key] = DateTime.fromMillisecondsSinceEpoch(epochMs);
        }
      });

      _updateState(_state.copyWith(itemLastPlayedAt: playedHistory));
    } catch (_) {
      // Ignore corrupt local played history and keep running.
    }
  }

  Future<void> _markItemPlayed(String key) async {
    final now = DateTime.now();
    final updatedPlayedHistory =
        Map<String, DateTime>.from(_state.itemLastPlayedAt)..[key] = now;

    _updateState(_state.copyWith(itemLastPlayedAt: updatedPlayedHistory));

    final prefs = await SharedPreferences.getInstance();
    final encoded = updatedPlayedHistory.map(
      (entryKey, value) => MapEntry(entryKey, value.millisecondsSinceEpoch),
    );
    await prefs.setString(_lastPlayedKey, jsonEncode(encoded));
  }

  // ============================================================================
  // Pinned Items
  // ============================================================================

  Future<void> _loadPinnedItems() async {
    final pinnedItemIds =
        await LibraryPinStorage.loadForUser(_connectionService.userId);
    _updateState(_state.copyWith(pinnedItemIds: pinnedItemIds));
  }

  Future<void> _savePinnedItems() async {
    await LibraryPinStorage.saveForUser(
      _connectionService.userId,
      _state.pinnedItemIds,
    );
  }

  Future<void> togglePinAlbum(String albumId) async {
    final key = 'album:$albumId';
    final updated = Set<String>.from(_state.pinnedItemIds);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    _updateState(_state.copyWith(pinnedItemIds: updated));
    await _savePinnedItems();
  }

  Future<void> togglePinPlaylist(String playlistId) async {
    final key = 'playlist:$playlistId';
    final updated = Set<String>.from(_state.pinnedItemIds);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    _updateState(_state.copyWith(pinnedItemIds: updated));
    await _savePinnedItems();
  }

  // ============================================================================
  // Playlist Listener
  // ============================================================================

  void _onPlaylistsChanged() {
    notifyListeners();
  }

  // ============================================================================
  // WebSocket Message Handling
  // ============================================================================

  void _handleWebSocketMessage(WsMessage message) {
    if (message.type == WsMessageType.syncTokenAdvanced) {
      final latestToken = _parseLatestToken(message.data?['latestToken']);
      unawaited(_handleSyncTokenAdvanced(latestToken));
      return;
    }

    if (message.type == WsMessageType.libraryUpdated) {
      unawaited(_handleLibraryUpdatedMessage());
    }
  }

  Future<void> _handleSyncTokenAdvanced(int latestToken) async {
    if (!await _isUsingV2LibrarySource()) return;
    if (latestToken > 0 && latestToken <= _lastHandledSyncToken) {
      return;
    }
    final refreshed = await _refreshFromSyncToken(latestToken);
    if (refreshed && latestToken > 0) {
      _lastHandledSyncToken = latestToken;
    }
  }

  Future<void> _handleLibraryUpdatedMessage() async {
    if (await _isUsingV2LibrarySource()) {
      return;
    }

    if (!_durationsPending) return;
    if (_isLibraryLoadInFlight) return;
    if (_durationRetryCount >= _maxDurationRetries) return;

    _durationRetryCount++;
    await _loadLibrary(background: true);
  }

  Future<bool> _isUsingV2LibrarySource() async {
    final decision = await _connectionService.libraryReadFacade.resolveSource();
    return decision.source == LibraryReadSource.v2LocalStore;
  }

  int _parseLatestToken(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<bool> _refreshFromSyncToken(int latestToken) async {
    if (_isLibraryLoadInFlight) {
      _pendingBackgroundReload = true;
      return false;
    }
    if (!await _isUsingV2LibrarySource()) return false;

    if (latestToken <= 0) {
      await _loadLibrary(background: true);
      return true;
    }

    for (var attempt = 0; attempt < 10; attempt++) {
      final appliedToken = await _connectionService.libraryReadFacade
          .getActiveLastAppliedToken();
      if (appliedToken != null && appliedToken >= latestToken) {
        await _loadLibrary(background: true);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    await _loadLibrary(background: true);
    return true;
  }

  void _scheduleDurationRetry() {
    if (_durationRetryCount >= _maxDurationRetries) return;

    _durationRetryTimer?.cancel();
    _durationRetryTimer = Timer(_durationRetryDelay, () {
      if (!_durationsPending || _isLibraryLoadInFlight) return;
      if (_durationRetryCount >= _maxDurationRetries) return;

      _durationRetryCount++;
      unawaited(_loadLibrary(background: true));
    });
  }

  void _clearDurationRetries() {
    _durationsPending = false;
    _durationRetryCount = 0;
    _durationRetryTimer?.cancel();
    _durationRetryTimer = null;
  }

  // ============================================================================
  // Download & Cache State Refresh
  // ============================================================================

  void _scheduleDownloadedSongsRefresh(List<DownloadTask> tasks) {
    final signature = _buildCompletedDownloadsSignature(tasks);
    if (signature == _lastCompletedDownloadsSignature) return;

    _lastCompletedDownloadsSignature = signature;
    _downloadStateRefreshTimer?.cancel();
    _downloadStateRefreshTimer = Timer(
      const Duration(milliseconds: 150),
      _loadDownloadedSongs,
    );
  }

  void _scheduleCachedSongsRefresh() {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      _loadCachedSongs,
    );
  }

  String _buildCompletedDownloadsSignature(List<DownloadTask> queue) {
    final buffer = StringBuffer();
    var completedCount = 0;

    for (final task in queue) {
      if (task.status != DownloadStatus.completed) continue;
      completedCount++;
      buffer
        ..write(task.id)
        ..write(':')
        ..write(task.albumId ?? '')
        ..write('|');
    }

    return '$completedCount#$buffer';
  }

  // ============================================================================
  // Load Downloaded Songs
  // ============================================================================

  Future<void> _loadDownloadedSongs([List<DownloadTask>? queueSnapshot]) async {
    final queue = queueSnapshot ?? _downloadManager.queue;
    final downloadedIds = <String>{};
    final albumsWithDownloads = <String>{};
    final albumDownloadCounts = <String, int>{};

    for (final task in queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
        if (task.albumId != null) {
          albumsWithDownloads.add(task.albumId!);
          albumDownloadCounts[task.albumId!] =
              (albumDownloadCounts[task.albumId!] ?? 0) + 1;
        }
      }
    }

    // Determine which albums are fully downloaded
    final fullyDownloaded = <String>{};
    for (final album in _state.albums) {
      final downloadedCount = albumDownloadCounts[album.id] ?? 0;
      if (downloadedCount >= album.songCount && album.songCount > 0) {
        fullyDownloaded.add(album.id);
      }
    }

    // Determine which playlists have downloaded songs
    final playlistsWithDownloads = <String>{};
    for (final playlist in _playlistService.playlists) {
      for (final songId in playlist.songIds) {
        if (downloadedIds.contains(songId)) {
          playlistsWithDownloads.add(playlist.id);
          break;
        }
      }
    }

    _lastCompletedDownloadsSignature = _buildCompletedDownloadsSignature(queue);

    final downloadStateUnchanged = _state.downloadedSongIds.length ==
            downloadedIds.length &&
        _state.downloadedSongIds.containsAll(downloadedIds) &&
        _state.albumsWithDownloads.length == albumsWithDownloads.length &&
        _state.albumsWithDownloads.containsAll(albumsWithDownloads) &&
        _state.fullyDownloadedAlbumIds.length == fullyDownloaded.length &&
        _state.fullyDownloadedAlbumIds.containsAll(fullyDownloaded) &&
        _state.playlistsWithDownloads.length == playlistsWithDownloads.length &&
        _state.playlistsWithDownloads.containsAll(playlistsWithDownloads);

    if (downloadStateUnchanged) return;

    _updateState(_state.copyWith(
      downloadedSongIds: downloadedIds,
      albumsWithDownloads: albumsWithDownloads,
      fullyDownloadedAlbumIds: fullyDownloaded,
      playlistsWithDownloads: playlistsWithDownloads,
    ));
  }

  // ============================================================================
  // Load Cached Songs
  // ============================================================================

  Future<void> _loadCachedSongs() async {
    final allCachedIds = await _cacheManager.getCachedSongIds();

    final cacheStateUnchanged =
        _state.cachedSongIds.length == allCachedIds.length &&
            _state.cachedSongIds.containsAll(allCachedIds);
    if (cacheStateUnchanged) return;

    _updateState(_state.copyWith(cachedSongIds: allCachedIds));
  }

  // ============================================================================
  // Load Library
  // ============================================================================

  /// Refreshes the library; attempts reconnect when offline or disconnected (same as Settings / pull-to-refresh).
  Future<LibraryRefreshOutcome> refreshLibrary() async {
    if (_offlineService.isManualOfflineModeEnabled) {
      final outcome = await reconnectFromManualOffline(
        offline: _offlineService,
        connection: _connectionService,
      );
      await _loadLibrary(background: true);
      switch (outcome) {
        case ManualOfflineReconnectOutcome.success:
          return LibraryRefreshOutcome.ok;
        case ManualOfflineReconnectOutcome.authFailure:
          return LibraryRefreshOutcome.showSessionExpiredSnack;
        case ManualOfflineReconnectOutcome.networkFailure:
          return LibraryRefreshOutcome.showManualReconnectFailedSnack;
      }
    }

    if (_offlineService.isOfflineModeEnabled ||
        !_connectionService.isConnected ||
        _connectionService.apiClient == null) {
      final restored = await _connectionService.tryRestoreConnection();
      if (!restored) {
        if (!_connectionService.hasServerInfo) {
          await _loadLibrary(background: true);
          return LibraryRefreshOutcome.navigateToReconnectScreen;
        }
        if (_connectionService.didLastRestoreFailForAuth) {
          await _loadLibrary(background: true);
          return LibraryRefreshOutcome.showSessionExpiredSnack;
        }
        await _loadLibrary(background: true);
        return LibraryRefreshOutcome.ok;
      }
    }

    if (!_offlineService.isOfflineModeEnabled &&
        _connectionService.isConnected &&
        _connectionService.apiClient != null) {
      try {
        await _connectionService.librarySyncEngine.syncNow();
      } catch (_) {
        // Sync errors are recorded in the engine; keep serving local data.
      }
    }

    await _loadLibrary(background: true);

    if (!_offlineService.isOfflineModeEnabled &&
        _connectionService.isConnected) {
      final syncHealth =
          await _connectionService.librarySyncEngine.getSyncHealth();
      if (syncHealth.hasSyncFailure) {
        return LibraryRefreshOutcome.showSyncFailedSnack;
      }
    }

    return LibraryRefreshOutcome.ok;
  }

  Future<void> _loadLibrary({bool background = false}) async {
    if (_isLibraryLoadInFlight) {
      _pendingBackgroundReload = true;
      return;
    }

    libraryLoadAttemptsForTest++;
    final hasExistingContent = _state.albums.isNotEmpty ||
        _state.songs.isNotEmpty ||
        _state.offlineSongs.isNotEmpty;
    final useFullScreenLoader = !background && !hasExistingContent;

    _isLibraryLoadInFlight = true;
    try {
      // If offline mode is enabled, build library from downloaded songs
      if (_offlineService.isOfflineModeEnabled) {
        _clearDurationRetries();
        await _loadDownloadedSongs();
        if (hasExistingContent) {
          _pendingScrollRestore = true;
        }
        _buildLibraryFromDownloads();
        await _loadDownloadedSongs();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          clearError: true,
          clearSyncWarning: true,
          showDownloadedOnly: true,
        ));
        return;
      }

      if (_connectionService.apiClient == null) {
        _clearDurationRetries();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: 'Not connected to server',
        ));
        return;
      }

      if (useFullScreenLoader) {
        _updateState(_state.copyWith(
          isLoading: true,
          isRefreshing: false,
          clearError: true,
        ));
      } else {
        _updateState(_state.copyWith(
          isRefreshing: true,
          isLoading: false,
          clearError: true,
        ));
      }

      await _loadLibraryFromFacade();
    } catch (e) {
      // If it's a network/timeout error, gracefully fall back to offline mode
      if (e.toString().contains('Network error') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException')) {
        _clearDurationRetries();
        if (background && hasExistingContent) {
          _updateState(_state.copyWith(
            isLoading: false,
            isRefreshing: false,
            syncWarningMessage: 'Library sync failed. Showing cached data.',
          ));
        } else {
          if (hasExistingContent) {
            _pendingScrollRestore = true;
          }
          await _loadDownloadedSongs();
          _buildLibraryFromDownloads();
          _updateState(_state.copyWith(
            isLoading: false,
            isRefreshing: false,
            clearError: true,
            clearSyncWarning: true,
            showDownloadedOnly: true,
          ));
        }
      } else {
        _clearDurationRetries();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: 'Failed to load library: $e',
        ));
      }
    } finally {
      await _completeLibraryLoad();
    }
  }

  Future<void> _completeLibraryLoad() async {
    _isLibraryLoadInFlight = false;
    if (_pendingBackgroundReload) {
      _pendingBackgroundReload = false;
      unawaited(_loadLibrary(background: true));
      return;
    }
    await _recheckStaleSyncWarning();
  }

  Future<void> _recheckStaleSyncWarning() async {
    if (_state.syncWarningMessage == null) return;
    if (_offlineService.isOfflineModeEnabled) return;
    if (_connectionService.apiClient == null) return;

    try {
      final health = await _connectionService.librarySyncEngine.getSyncHealth();
      if (!health.isPartialRead && !health.hasSyncFailure) {
        _updateState(_state.copyWith(
          clearSyncWarning: true,
          isRefreshing: false,
        ));
      }
    } catch (_) {
      // Keep the existing warning if health cannot be queried.
    }
  }

  Future<void> _loadLibraryFromFacade() async {
    final library =
        await _connectionService.libraryReadFacade.getLibraryBundle();

    _playlistService.updateServerPlaylists(library.serverPlaylists);

    final validSongIds = library.songs.map((song) => song.id).toSet();
    await _downloadManager.pruneOrphanedDownloads(validSongIds);

    _updateState(_state.copyWith(
      albums: library.albums,
      songs: library.songs,
      isOfflineMode: false,
      isLoading: false,
      isRefreshing: false,
      showDownloadedOnly: false,
      syncWarningMessage: _buildSyncWarningMessage(library),
      clearSyncWarning: !_hasSyncWarning(library),
    ));

    if (library.durationsReady) {
      _clearDurationRetries();
    } else {
      _durationsPending = true;
      _scheduleDurationRetry();
    }

    // Remap stale song IDs first (e.g. after server library rescanned),
    // then rehydrate metadata so titles/album IDs stay current.
    final remappedPlaylists =
        await _playlistService.remapPlaylistSongIds(library.songs);
    if (remappedPlaylists > 0) {
      // Playlists had stale IDs remapped
    }

    // Mirror the playlist remap for listening stats: stale rows are matched
    // back to current library songIds and merged into any existing entry,
    // preventing artist/album aggregations from double-counting plays under
    // multiple ids for the same physical song.
    await _statsService.remapStaleStatIdsFromLibrary(library.songs);

    final updatedPlaylists =
        await _playlistService.rehydrateSongMetadataFromLibrary(library.songs);
    if (updatedPlaylists > 0) {
      // Playlists were updated
    }

    await _loadDownloadedSongs();
  }

  bool _hasSyncWarning(LibraryReadBundle library) {
    return library.isPartialRead || library.syncHealth?.hasSyncFailure == true;
  }

  String? _buildSyncWarningMessage(LibraryReadBundle library) {
    if (library.syncHealth?.hasSyncFailure == true) {
      return 'Library sync failed. Showing cached data.';
    }
    if (library.isPartialRead) {
      return 'Library sync is still in progress. Some content may be missing.';
    }
    return null;
  }

  // ============================================================================
  // Build Library From Downloads (Offline Mode)
  // ============================================================================

  void _buildLibraryFromDownloads() {
    final queue = _downloadManager.queue;
    final completedTasks =
        queue.where((t) => t.status == DownloadStatus.completed).toList();

    final songs = <Song>[];
    final albumMap = <String, List<DownloadTask>>{};

    for (final task in completedTasks) {
      if (task.albumId != null) {
        albumMap.putIfAbsent(task.albumId!, () => []).add(task);
      } else {
        final song = Song(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          album: task.albumName,
          albumId: task.albumId,
          albumArtist: task.albumArtist,
          trackNumber: task.trackNumber,
          discNumber: null,
          year: null,
          genre: null,
          duration: Duration(seconds: task.duration),
          filePath: task.songId,
          fileSize: task.bytesDownloaded,
          modifiedTime: DateTime.now(),
        );
        songs.add(song);
      }
    }

    final albums = <AlbumModel>[];
    for (final entry in albumMap.entries) {
      final albumId = entry.key;
      final albumTasks = entry.value;
      final firstTask = albumTasks.first;

      final totalDuration =
          albumTasks.fold<int>(0, (sum, task) => sum + task.duration);

      final albumTitle = firstTask.albumName ?? '${firstTask.artist} Album';
      final artist = firstTask.albumArtist ?? firstTask.artist;

      albums.add(AlbumModel(
        id: albumId,
        title: albumTitle,
        artist: artist,
        coverArt: resolveAlbumArtworkUrl(albumId: albumId),
        songCount: albumTasks.length,
        duration: totalDuration,
      ));
    }

    songs.sort((a, b) => a.title.compareTo(b.title));
    albums.sort((a, b) => a.title.compareTo(b.title));

    _updateState(_state.copyWith(
      offlineSongs: songs,
      albums: albums,
      isOfflineMode: true,
    ));
  }

  // ============================================================================
  // Test hooks
  // ============================================================================

  @visibleForTesting
  bool get pendingBackgroundReloadForTest => _pendingBackgroundReload;

  @visibleForTesting
  bool get isLibraryLoadInFlightForTest => _isLibraryLoadInFlight;

  @visibleForTesting
  int get lastHandledSyncTokenForTest => _lastHandledSyncToken;

  @visibleForTesting
  void resetLoadSchedulingForTest() {
    _isLibraryLoadInFlight = false;
    _pendingBackgroundReload = false;
    libraryLoadAttemptsForTest = 0;
  }

  @visibleForTesting
  void markLibraryLoadInFlightForTest() {
    _isLibraryLoadInFlight = true;
  }

  @visibleForTesting
  Future<void> loadLibraryForTest({bool background = false}) =>
      _loadLibrary(background: background);

  @visibleForTesting
  Future<void> completeLibraryLoadForTest() => _completeLibraryLoad();

  @visibleForTesting
  Future<bool> refreshFromSyncTokenForTest(int latestToken) =>
      _refreshFromSyncToken(latestToken);

  @visibleForTesting
  Future<void> handleSyncTokenAdvancedForTest(int latestToken) =>
      _handleSyncTokenAdvanced(latestToken);

  @visibleForTesting
  set queuedSongIdsForTest(Set<String>? ids) => _queuedSongIdsForTest = ids;

  @visibleForTesting
  void setStateForTest(LibraryState state) {
    _state = state;
    notifyListeners();
  }

  @visibleForTesting
  void setSelectionForTest({
    bool selectionMode = true,
    Set<String>? songIds,
    Set<String>? albumIds,
    Set<String>? playlistIds,
  }) {
    _isSelectionModeActive = selectionMode;
    _selectedSongIds
      ..clear()
      ..addAll(songIds ?? const {});
    _selectedAlbumIds
      ..clear()
      ..addAll(albumIds ?? const {});
    _selectedPlaylistIds
      ..clear()
      ..addAll(playlistIds ?? const {});
    notifyListeners();
  }

  @visibleForTesting
  BatchDownloadSummary computeBatchDownloadSummaryForTest() =>
      batchDownloadSummary;

  @visibleForTesting
  void resetBatchDownloadTestState() {
    _queuedSongIdsForTest = null;
    exitSelectionMode();
    _state = const LibraryState();
  }

  // ============================================================================
  // Getters for Services (needed by widgets/modals)
  // ============================================================================

  ConnectionService get connectionService => _connectionService;
  PlaybackManager get playbackManager => _playbackManager;
  PlaylistService get playlistService => _playlistService;
  OfflinePlaybackService get offlineService => _offlineService;
  DownloadManager get downloadManager => _downloadManager;
  CacheManager get cacheManager => _cacheManager;
}

/// Summary of what a multi-select batch download would enqueue.
class BatchDownloadSummary {
  const BatchDownloadSummary({
    required this.containerCount,
    required this.resolvedSongCount,
    required this.alreadySavedCount,
    required this.inQueueCount,
    required this.toDownloadCount,
    required this.hasEnqueueTargets,
  });

  final int containerCount;
  final int resolvedSongCount;
  final int alreadySavedCount;
  final int inQueueCount;
  final int toDownloadCount;
  final bool hasEnqueueTargets;

  bool get allSaved => !hasEnqueueTargets;

  bool get hasPartialSkip =>
      (alreadySavedCount + inQueueCount) > 0 && toDownloadCount > 0;
}
