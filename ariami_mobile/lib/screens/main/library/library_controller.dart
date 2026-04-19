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

  LibraryController._internal() {
    _connectionService = ConnectionService();
    _playbackManager = PlaybackManager();
    _playlistService = PlaylistService();
    _offlineService = OfflinePlaybackService();
    _downloadManager = DownloadManager();
    _cacheManager = CacheManager();
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
      _loadLibrary();
    });

    // Listen to connection state changes
    _connectionSubscription =
        _connectionService.connectionStateStream.listen((isConnected) {
      if (isConnected) {
        _loadLibrary();
        _loadDownloadedSongs();
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
    await _refreshFromSyncToken(latestToken);
    if (latestToken > 0) {
      _lastHandledSyncToken = latestToken;
    }
  }

  Future<void> _handleLibraryUpdatedMessage() async {
    if (await _isUsingV2LibrarySource()) {
      return;
    }

    if (!_durationsPending) return;
    if (_state.isLoading) return;
    if (_durationRetryCount >= _maxDurationRetries) return;

    _durationRetryCount++;
    await _loadLibrary();
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

  Future<void> _refreshFromSyncToken(int latestToken) async {
    if (!await _isUsingV2LibrarySource()) return;
    if (_state.isLoading) return;

    if (latestToken <= 0) {
      await _loadLibrary();
      return;
    }

    for (var attempt = 0; attempt < 10; attempt++) {
      final appliedToken = await _connectionService.libraryReadFacade
          .getActiveLastAppliedToken();
      if (appliedToken != null && appliedToken >= latestToken) {
        await _loadLibrary();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    await _loadLibrary();
  }

  void _scheduleDurationRetry() {
    if (_durationRetryCount >= _maxDurationRetries) return;

    _durationRetryTimer?.cancel();
    _durationRetryTimer = Timer(_durationRetryDelay, () {
      if (!_durationsPending || _state.isLoading) return;
      if (_durationRetryCount >= _maxDurationRetries) return;

      _durationRetryCount++;
      _loadLibrary();
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
      await _loadLibrary();
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
          await _loadLibrary();
          return LibraryRefreshOutcome.navigateToReconnectScreen;
        }
        if (_connectionService.didLastRestoreFailForAuth) {
          await _loadLibrary();
          return LibraryRefreshOutcome.showSessionExpiredSnack;
        }
        await _loadLibrary();
        return LibraryRefreshOutcome.ok;
      }
    }

    await _loadLibrary();
    return LibraryRefreshOutcome.ok;
  }

  Future<void> _loadLibrary() async {
    // If offline mode is enabled, build library from downloaded songs
    if (_offlineService.isOfflineModeEnabled) {
      _clearDurationRetries();
      await _loadDownloadedSongs();
      _buildLibraryFromDownloads();
      await _loadDownloadedSongs();
      _updateState(_state.copyWith(
        isLoading: false,
        clearError: true,
        showDownloadedOnly: true,
      ));
      return;
    }

    if (_connectionService.apiClient == null) {
      _clearDurationRetries();
      _updateState(_state.copyWith(
        isLoading: false,
        errorMessage: 'Not connected to server',
      ));
      return;
    }

    try {
      _updateState(_state.copyWith(isLoading: true, clearError: true));
      await _loadLibraryFromFacade();
    } catch (e) {
      // If it's a network/timeout error, gracefully fall back to offline mode
      if (e.toString().contains('Network error') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException')) {
        _clearDurationRetries();
        await _loadDownloadedSongs();
        _buildLibraryFromDownloads();
        _updateState(_state.copyWith(
          isLoading: false,
          clearError: true,
          showDownloadedOnly: true,
        ));
      } else {
        _clearDurationRetries();
        _updateState(_state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load library: $e',
        ));
      }
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
      showDownloadedOnly: false,
    ));

    if (library.durationsReady) {
      _clearDurationRetries();
    } else {
      _durationsPending = true;
      _scheduleDurationRetry();
    }

    final updatedPlaylists =
        await _playlistService.rehydrateSongMetadataFromLibrary(library.songs);
    if (updatedPlaylists > 0) {
      // Playlists were updated
    }

    await _loadDownloadedSongs();
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
  // Getters for Services (needed by widgets/modals)
  // ============================================================================

  ConnectionService get connectionService => _connectionService;
  PlaybackManager get playbackManager => _playbackManager;
  PlaylistService get playlistService => _playlistService;
  OfflinePlaybackService get offlineService => _offlineService;
  DownloadManager get downloadManager => _downloadManager;
  CacheManager get cacheManager => _cacheManager;
}
