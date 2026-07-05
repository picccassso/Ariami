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
import '../../../services/offline/offline_copy_service.dart';
import '../../../services/offline/offline_playback_service.dart';
import '../../../services/playback_manager.dart';
import '../../../services/playlist_service.dart';
import '../../../services/stats/streaming_stats_service.dart';
import '../../../utils/artwork_url.dart';
import '../../../utils/downloaded_album_metadata.dart';
import 'library_album_remap.dart';
import 'library_state.dart';

part 'library_controller_loading.dart';
part 'library_controller_local_state.dart';
part 'library_controller_preferences.dart';
part 'library_controller_selection.dart';
part 'library_controller_sync.dart';

/// Controller for the LibraryScreen.
/// Manages all business logic and state for the library.
class LibraryController extends ChangeNotifier {
  static final LibraryController _instance = LibraryController._internal();
  factory LibraryController() => _instance;

  late final ConnectionService _connectionService;
  late final PlaybackManager _playbackManager;
  late final PlaylistService _playlistService;
  late final OfflinePlaybackService _offlineService;
  late final OfflineCopyService _offlineCopyService;
  late final DownloadManager _downloadManager;
  late final CacheManager _cacheManager;
  late final StreamingStatsService _statsService;

  static const String _viewPreferenceKey = 'library_view_grid';
  static const String _albumsSectionKey = 'library_section_albums';
  static const String _songsSectionKey = 'library_section_songs';
  static const String _mixedModeKey = 'library_mixed_mode';
  static const String _lastPlayedKey = 'library_last_played';

  static const int _maxDurationRetries = 3;
  static const Duration _durationRetryDelay = Duration(seconds: 3);

  LibraryState _state = const LibraryState();
  LibraryState get state => _state;

  bool _isSelectionModeActive = false;
  bool get isSelectionModeActive => _isSelectionModeActive;

  final Set<String> _selectedPlaylistIds = {};
  Set<String> get selectedPlaylistIds => _selectedPlaylistIds;

  final Set<String> _selectedAlbumIds = {};
  Set<String> get selectedAlbumIds => _selectedAlbumIds;

  final Set<String> _selectedSongIds = {};
  Set<String> get selectedSongIds => _selectedSongIds;

  Set<String>? _queuedSongIdsForTest;

  bool _durationsPending = false;
  int _durationRetryCount = 0;

  String _lastCompletedDownloadsSignature = '';
  int _lastHandledSyncToken = 0;

  Timer? _durationRetryTimer;
  Timer? _downloadStateRefreshTimer;
  Timer? _cacheRefreshTimer;

  // Retain subscriptions for the lifetime of this singleton.
  // ignore: unused_field
  StreamSubscription<OfflineMode>? _offlineSubscription;
  // ignore: unused_field
  StreamSubscription<CacheUpdateEvent>? _cacheSubscription;
  // ignore: unused_field
  StreamSubscription<bool>? _connectionSubscription;
  // ignore: unused_field
  StreamSubscription<List<DownloadTask>>? _downloadSubscription;
  // ignore: unused_field
  StreamSubscription<WsMessage>? _webSocketSubscription;

  bool _isInitialized = false;
  bool _isLibraryLoadInFlight = false;
  bool _pendingBackgroundReload = false;
  bool _pendingScrollRestore = false;
  bool _hasLoadedOnlineLibrary = false;

  @visibleForTesting
  int libraryLoadAttemptsForTest = 0;

  LibraryController._internal() {
    _connectionService = ConnectionService();
    _playbackManager = PlaybackManager();
    _playlistService = PlaylistService();
    _offlineService = OfflinePlaybackService();
    _offlineCopyService = OfflineCopyService();
    _downloadManager = DownloadManager();
    _cacheManager = CacheManager();
    _statsService = StreamingStatsService();
  }

  int get totalSelectedCount =>
      _selectedPlaylistIds.length +
      _selectedAlbumIds.length +
      _selectedSongIds.length;

  BatchDownloadSummary get batchDownloadSummary =>
      _computeBatchDownloadSummary();

  bool get hasBatchItemsToDownload => !batchDownloadSummary.allSaved;

  void enterSelectionMode() => _enterSelectionMode();
  void exitSelectionMode() => _exitSelectionMode();
  void togglePlaylistSelection(String playlistId) =>
      _togglePlaylistSelection(playlistId);
  void toggleAlbumSelection(String albumId) => _toggleAlbumSelection(albumId);
  void toggleSongSelection(String songId) => _toggleSongSelection(songId);
  void selectAllVisible() => _selectAllVisible();
  void clearSelection() => _clearSelection();
  Future<int> downloadSelectedItems() => _downloadSelectedItems();

  Future<void> toggleViewMode() => _toggleViewMode();
  Future<void> toggleAlbumsExpanded() => _toggleAlbumsExpanded();
  Future<void> toggleSongsExpanded() => _toggleSongsExpanded();
  Future<void> toggleMixedMode() => _toggleMixedMode();
  Future<void> markAlbumPlayed(String albumId) =>
      _markItemPlayed('album:$albumId');
  Future<void> markPlaylistPlayed(String playlistId) =>
      _markItemPlayed('playlist:$playlistId');
  void toggleShowDownloadedOnly() => _toggleShowDownloadedOnly();
  Future<void> togglePinAlbum(String albumId) => _togglePinAlbum(albumId);
  Future<void> togglePinPlaylist(String playlistId) =>
      _togglePinPlaylist(playlistId);

  /// Refreshes the library; attempts reconnect when offline or disconnected.
  Future<LibraryRefreshOutcome> refreshLibrary() => _refreshLibrary();

  Future<void> refreshOfflineCopyState() async {
    if (_offlineService.isOfflineModeEnabled) {
      _buildLibraryFromDownloads();
      await _loadDownloadedSongs();
      return;
    }
    await _loadLibrary(background: true);
  }

  /// Initialize the controller and load initial data.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    // Downloaded and cached content is read straight from these managers'
    // in-memory queues (e.g. _loadDownloadedSongs reads _downloadManager.queue
    // synchronously), so they must be loaded from disk before the first library
    // load - otherwise an offline launch reads an empty queue and shows zero
    // downloads. Startup also initializes them concurrently; init is idempotent,
    // so this just awaits the shared in-flight future.
    await Future.wait([
      _downloadManager.initialize(),
      _cacheManager.initialize(),
    ]);
    await _offlineCopyService.initialize();
    await _loadUiPreferences();
    await _loadPlayedHistory();
    await _playlistService.loadPlaylists();
    await _loadPinnedItems();
    await _loadLibrary();
    _playlistService.addListener(_onPlaylistsChanged);
    await _loadDownloadedSongs();
    await _loadCachedSongs();
    _setupStreamListeners();
    // Startup intentionally reconnects in the background. Check once after
    // subscribing so a connection completed during initialization cannot fall
    // into the gap between the initial load and the connection-state stream.
    await _loadServerPlaylistEditsIfConnected();
  }

  /// Returns true once when the UI should restore scroll after a library update.
  bool consumeScrollRestorePending() {
    if (!_pendingScrollRestore) return false;
    _pendingScrollRestore = false;
    return true;
  }

  void _updateState(LibraryState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void _notifyListeners() => notifyListeners();

  @override
  void dispose() {
    // Singleton - listeners and subscriptions live for app lifetime.
    super.dispose();
  }

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

  ConnectionService get connectionService => _connectionService;
  PlaybackManager get playbackManager => _playbackManager;
  PlaylistService get playlistService => _playlistService;
  OfflinePlaybackService get offlineService => _offlineService;
  DownloadManager get downloadManager => _downloadManager;
  CacheManager get cacheManager => _cacheManager;
}
