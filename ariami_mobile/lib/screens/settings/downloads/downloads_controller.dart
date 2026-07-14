import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/api_models.dart' show PlaylistModel;
import '../../../models/download_task.dart';
import '../../../models/quality_settings.dart';
import '../../../models/websocket_models.dart';
import '../../../services/api/connection_service.dart';
import '../../../services/cache/cache_manager.dart'
    show CacheManager, CacheUpdateEvent;
import '../../../services/download/download_manager.dart';
import '../../../services/download/download_helpers.dart';
import '../../../services/playlist_service.dart';
import '../../../services/quality/quality_settings_service.dart';
import 'downloads_state.dart';
import 'utils/download_helpers.dart';

/// Business logic and subscriptions for [DownloadsScreen].
///
/// Two output channels:
/// 1. `notifyListeners()` — fires only on **structural** changes (status
///    transitions, queue add/remove, settings, cache stats). The screen
///    rebuilds the section list on this signal.
/// 2. Per-task / per-album / overall [ValueListenable]s — fire on **byte
///    progress** at a throttled cadence (~200ms). Individual rows subscribe
///    so only the changing row repaints; the section list does not rebuild.
class DownloadsController extends ChangeNotifier {
  DownloadsController({
    ConnectionService? connectionService,
    DownloadManager? downloadManager,
    CacheManager? cacheManager,
    QualitySettingsService? qualityService,
  })  : _connectionService = connectionService ?? ConnectionService(),
        _downloadManager = downloadManager ?? DownloadManager(),
        _cacheManager = cacheManager ?? CacheManager(),
        _qualityService = qualityService ?? QualitySettingsService();

  final ConnectionService _connectionService;
  final DownloadManager _downloadManager;
  final CacheManager _cacheManager;
  final QualitySettingsService _qualityService;

  DownloadsState _state = const DownloadsState();
  DownloadsState get state => _state;

  DownloadManager get downloadManager => _downloadManager;

  /// Reference data for download-all counts (not part of public UI state).
  Set<String> _librarySongIds = {};
  Map<String, int> _albumSongCounts = {};
  Set<String> _playlistSongIds = {};
  int _libraryAlbumCount = 0;
  bool _hasLibraryReferenceData = false;

  /// Resolves the songs represented by playlists that exist in the mobile
  /// library. Imported server playlists are local playlists too; server
  /// playlists still waiting in "Import from Server" are intentionally absent.
  @visibleForTesting
  static Set<String> resolveLocalPlaylistSongIds(
    Iterable<PlaylistModel> playlists, {
    Set<String>? validSongIds,
  }) {
    final songIds = <String>{};
    for (final playlist in playlists) {
      songIds.addAll(playlist.songIds);
    }
    if (validSongIds != null) {
      songIds.removeWhere((songId) => !validSongIds.contains(songId));
    }
    return songIds;
  }

  String _lastQueueViewSignature = '';

  StreamSubscription<CacheUpdateEvent>? _cacheSubscription;
  Timer? _cacheStatsRefreshTimer;
  Timer? _countRefreshTimer;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  StreamSubscription<QualitySettings>? _qualitySettingsSubscription;
  StreamSubscription<WsMessage>? _webSocketSubscription;

  // ---- Per-task / per-album / overall progress notifiers ----------------
  static const Duration _flushInterval = Duration(milliseconds: 200);

  final Map<String, ValueNotifier<DownloadProgress>> _taskProgressNotifiers =
      {};
  final Map<String, ValueNotifier<AlbumProgressSnapshot>>
      _albumProgressNotifiers = {};
  final ValueNotifier<OverallProgressSummary> _overallProgressNotifier =
      ValueNotifier(OverallProgressSummary.empty);

  /// Latest seen progress event per task. Used to seed lazily-created task
  /// notifiers and to recompute album/overall snapshots without scanning the
  /// raw queue.
  final Map<String, DownloadProgress> _latestProgress = {};

  /// Maps task id to its currently-rendered album key, so a progress event
  /// can identify which album snapshot to dirty without scanning all groups.
  final Map<String, String> _taskIdToAlbumKey = {};

  /// Pending dirty sets between flushes.
  final Set<String> _dirtyTaskIds = {};
  final Set<String> _dirtyAlbumKeys = {};
  bool _overallDirty = false;
  Timer? _flushTimer;

  // ---- Session totals ---------------------------------------------------
  /// Tasks observed in pending/downloading/paused state during this app
  /// session. Sourced from [DownloadManager.sessionTaskIds] (singleton-scoped)
  /// so the "X / Y" counter stays stable across screen navigations.
  Set<String> get _sessionTaskIds => _downloadManager.sessionTaskIds;

  bool _disposed = false;

  late final Future<void> initializeFuture = _initialize();

  Future<void> _initialize() async {
    await _downloadManager.initialize();
    await _cacheManager.initialize();
    await _qualityService.initialize();
    final qualitySettings = _qualityService.settings;
    await _loadCacheStats();
    _state = _state.copyWith(
      downloadQuality: qualitySettings.downloadQuality,
      downloadOriginal: qualitySettings.downloadOriginal,
      autoResumeInterruptedOnLaunch:
          _downloadManager.getAutoResumeInterruptedOnLaunch(),
      coolerDownloads: _downloadManager.getCoolerDownloads(),
      interruptedDownloadCount:
          _countInterruptedDownloads(_downloadManager.queue),
    );

    _qualitySettingsSubscription = _qualityService.settingsStream.listen((
      qualitySettings,
    ) {
      if (_disposed) return;
      final nextDownloadOriginal = qualitySettings.downloadOriginal;
      if (_state.downloadOriginal == nextDownloadOriginal &&
          _state.downloadQuality == qualitySettings.downloadQuality) {
        return;
      }

      _state = _state.copyWith(
        downloadQuality: qualitySettings.downloadQuality,
        downloadOriginal: nextDownloadOriginal,
      );
      notifyListeners();
    });

    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((event) {
      if (!event.affectsSongCache) return;
      _scheduleCacheStatsRefresh();
    });

    _progressSubscription =
        _downloadManager.progressStream.listen(_onProgressEvent);

    _queueSubscription = _downloadManager.queueStream.listen((queue) {
      final interruptedCount = _countInterruptedDownloads(queue);
      if (_state.interruptedDownloadCount != interruptedCount) {
        _state = _state.copyWith(interruptedDownloadCount: interruptedCount);
        if (!_disposed) {
          notifyListeners();
        }
      }
      _countRefreshTimer?.cancel();
      _countRefreshTimer = Timer(
        const Duration(milliseconds: 300),
        _recomputeDownloadAllCounts,
      );
    });
    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleLibrarySyncMessage,
    );

    final playlistService = PlaylistService();
    if (!playlistService.isLoaded) {
      await playlistService.loadPlaylists();
    }

    await _refreshLibraryReferenceData();
    _recomputeDownloadAllCounts();
  }

  // ---- Public listenables -----------------------------------------------

  ValueListenable<OverallProgressSummary> get overallProgress =>
      _overallProgressNotifier;

  /// Returns a notifier for an individual song's live progress. Creates one
  /// on first request and seeds it from the task's current state. Notifiers
  /// are kept for the controller's lifetime.
  ValueListenable<DownloadProgress> taskProgressFor(DownloadTask task) {
    final existing = _taskProgressNotifiers[task.id];
    if (existing != null) {
      return existing;
    }
    final seed = _latestProgress[task.id] ??
        DownloadProgress(
          taskId: task.id,
          progress: task.progress,
          bytesDownloaded: task.bytesDownloaded,
          totalBytes: task.totalBytes,
        );
    final notifier = ValueNotifier<DownloadProgress>(seed);
    _taskProgressNotifiers[task.id] = notifier;
    return notifier;
  }

  /// Returns a notifier for an album's aggregate progress. Created lazily
  /// for any album that exists in the current in-progress section.
  ValueListenable<AlbumProgressSnapshot> albumProgressFor(String key) {
    return _albumProgressNotifiers.putIfAbsent(
      key,
      () => ValueNotifier(_computeAlbumSnapshotForKey(key)),
    );
  }

  // ---- Progress flush pipeline ------------------------------------------

  void _onProgressEvent(DownloadProgress event) {
    _latestProgress[event.taskId] = event;
    _dirtyTaskIds.add(event.taskId);
    final albumKey = _taskIdToAlbumKey[event.taskId];
    if (albumKey != null) {
      _dirtyAlbumKeys.add(albumKey);
    }
    _overallDirty = true;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(_flushInterval, _flushProgress);
  }

  void _flushProgress() {
    _flushTimer = null;
    if (_disposed) return;

    for (final taskId in _dirtyTaskIds) {
      final notifier = _taskProgressNotifiers[taskId];
      final progress = _latestProgress[taskId];
      if (notifier != null && progress != null) {
        notifier.value = progress;
      }
    }
    _dirtyTaskIds.clear();

    for (final key in _dirtyAlbumKeys) {
      final snapshot = _computeAlbumSnapshotForKey(key);
      final notifier = _albumProgressNotifiers[key];
      if (notifier != null) {
        notifier.value = snapshot;
      }
    }
    _dirtyAlbumKeys.clear();

    if (_overallDirty) {
      _recomputeOverallProgress();
      _overallDirty = false;
    }
  }

  AlbumProgressSnapshot _computeAlbumSnapshotForKey(String key) {
    AlbumGroup? album;
    for (final candidate in _state.inProgressAlbums) {
      if (candidate.key == key) {
        album = candidate;
        break;
      }
    }
    if (album == null) return AlbumProgressSnapshot.empty;
    var bytesDone = 0;
    var bytesTotal = 0;
    for (final song in album.songs) {
      final progress = _latestProgress[song.id];
      bytesDone += progress?.bytesDownloaded ?? song.bytesDownloaded;
      bytesTotal += progress?.totalBytes ?? song.totalBytes;
    }
    return AlbumProgressSnapshot(bytesDone: bytesDone, bytesTotal: bytesTotal);
  }

  void _recomputeOverallProgress() {
    var bytesDone = 0;
    var bytesTotal = 0;
    var inProgressSongs = 0;

    for (final album in _state.inProgressAlbums) {
      for (final song in album.songs) {
        final progress = _latestProgress[song.id];
        bytesDone += progress?.bytesDownloaded ?? song.bytesDownloaded;
        bytesTotal += progress?.totalBytes ?? song.totalBytes;
        inProgressSongs++;
      }
    }

    final completedInSession = _completedInSessionCount();
    final totalSongs = inProgressSongs + completedInSession;

    _overallProgressNotifier.value = OverallProgressSummary(
      totalSongs: totalSongs,
      completedSongs: completedInSession,
      inProgressSongs: inProgressSongs,
      bytesDone: bytesDone,
      bytesTotal: bytesTotal,
    );
  }

  int _completedInSessionCount() {
    if (_sessionTaskIds.isEmpty) return 0;
    var count = 0;
    for (final task in _downloadManager.queue) {
      if (task.status == DownloadStatus.completed &&
          _sessionTaskIds.contains(task.id)) {
        count++;
      }
    }
    return count;
  }

  void _scheduleCacheStatsRefresh() {
    _cacheStatsRefreshTimer?.cancel();
    _cacheStatsRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      _loadCacheStats,
    );
  }

  void _handleLibrarySyncMessage(WsMessage message) {
    if (message.type != WsMessageType.syncTokenAdvanced &&
        message.type != WsMessageType.libraryUpdated) {
      return;
    }

    _countRefreshTimer?.cancel();
    _countRefreshTimer = Timer(const Duration(milliseconds: 300), () async {
      await _refreshLibraryReferenceData();
      _recomputeDownloadAllCounts();
    });
  }

  Future<void> _refreshLibraryReferenceData() async {
    final playlistService = PlaylistService();

    if (!_downloadManager.isInitialized) {
      await _downloadManager.initialize();
    }

    try {
      final library =
          await _connectionService.libraryReadFacade.getLibraryBundle();
      final songs = library.songs;
      final serverPlaylists = library.serverPlaylists;

      // Repair older queue rows that were created before album metadata was
      // resolved from the normalized album ID. This also makes the Downloads
      // screen self-healing when opened directly, without relying on the main
      // library screen having been visited first.
      await _downloadManager.refreshDownloadAlbumMetadata(
        libraryAlbums: library.albums,
        librarySongs: songs,
      );

      playlistService.updateServerPlaylists(serverPlaylists);

      final librarySongIds = songs.map((song) => song.id).toSet();
      final albumSongCounts = <String, int>{};
      for (final song in songs) {
        if (song.albumId != null) {
          albumSongCounts[song.albumId!] =
              (albumSongCounts[song.albumId!] ?? 0) + 1;
        }
      }

      final playlistSongIds = resolveLocalPlaylistSongIds(
        playlistService.playlists,
        validSongIds: librarySongIds,
      );

      _librarySongIds = librarySongIds;
      _albumSongCounts = albumSongCounts;
      _playlistSongIds = playlistSongIds;
      _libraryAlbumCount = library.albums.length;
      _hasLibraryReferenceData = true;
    } catch (_) {
      _librarySongIds = {};
      _albumSongCounts = {};
      _playlistSongIds = {};
      _libraryAlbumCount = 0;
      _hasLibraryReferenceData = false;
    }
  }

  void _recomputeDownloadAllCounts() {
    final playlistService = PlaylistService();

    final allDownloadedTasks = _downloadManager.queue
        .where((t) => t.status == DownloadStatus.completed)
        .toList();
    final downloadedSongIds = allDownloadedTasks.map((t) => t.songId).toSet();
    final localDownloadedSongs = allDownloadedTasks.length;
    final localAlbumIds = allDownloadedTasks
        .where((t) => t.albumId != null)
        .map((t) => t.albumId!)
        .toSet();

    final localPlaylistSongIds =
        resolveLocalPlaylistSongIds(playlistService.playlists);

    final localDownloadedPlaylistSongs =
        localPlaylistSongIds.where(downloadedSongIds.contains).length;

    if (!_hasLibraryReferenceData) {
      if (_disposed) return;
      _state = _state.copyWith(
        totalSongCount: localDownloadedSongs,
        totalAlbumCount: localAlbumIds.length,
        downloadedSongCount: localDownloadedSongs,
        downloadedAlbumCount: localAlbumIds.length,
        totalPlaylistSongCount: localDownloadedPlaylistSongs,
        downloadedPlaylistSongCount: localDownloadedPlaylistSongs,
        isLoadingCounts: false,
      );
      notifyListeners();
      return;
    }

    final downloadedAlbumSongIds = <String, Set<String>>{};
    for (final task in allDownloadedTasks) {
      final albumId = task.albumId;
      if (albumId == null) {
        continue;
      }
      downloadedAlbumSongIds
          .putIfAbsent(albumId, () => <String>{})
          .add(task.songId);
    }

    var downloadedAlbums = 0;
    for (final entry in _albumSongCounts.entries) {
      final downloadedSongsForAlbum = downloadedAlbumSongIds[entry.key];
      if (downloadedSongsForAlbum != null &&
          downloadedSongsForAlbum.length >= entry.value &&
          entry.value > 0) {
        downloadedAlbums++;
      }
    }

    final downloadedSongs =
        downloadedSongIds.where(_librarySongIds.contains).length;
    final downloadedPlaylistSongs =
        downloadedSongIds.where(_playlistSongIds.contains).length;

    if (_disposed) return;
    _state = _state.copyWith(
      totalSongCount: _librarySongIds.length,
      totalAlbumCount: _libraryAlbumCount,
      downloadedSongCount: downloadedSongs,
      downloadedAlbumCount: downloadedAlbums,
      totalPlaylistSongCount: _playlistSongIds.length,
      downloadedPlaylistSongCount: downloadedPlaylistSongs,
      isLoadingCounts: false,
    );
    notifyListeners();
  }

  /// Returns false when the request failed, so the screen can tell the user
  /// instead of the button silently doing nothing.
  Future<bool> downloadAllSongs() async {
    if (_connectionService.apiClient == null) {
      return false;
    }

    _state = _state.copyWith(isDownloadingAllSongs: true);
    notifyListeners();

    try {
      final downloadQuality = _qualityService.getDownloadQuality();
      final downloadOriginal = _qualityService.getDownloadOriginal();
      final songs = await _connectionService.libraryReadFacade.getSongs();
      await _downloadManager.enqueueDownloadJob(
        songIds: songs.map((song) => song.id).toList(),
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );
      return true;
    } catch (e) {
      debugPrint('[DownloadsController] Download all songs failed: $e');
      return false;
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllSongs: false);
        notifyListeners();
      }
    }
  }

  /// Returns false when the request failed. See [downloadAllSongs].
  Future<bool> downloadAllAlbums() async {
    if (_connectionService.apiClient == null) {
      return false;
    }

    _state = _state.copyWith(isDownloadingAllAlbums: true);
    notifyListeners();

    try {
      final downloadQuality = _qualityService.getDownloadQuality();
      final downloadOriginal = _qualityService.getDownloadOriginal();
      final albums = await _connectionService.libraryReadFacade.getAlbums();
      await _downloadManager.enqueueDownloadJob(
        albumIds: albums.map((album) => album.id).toList(),
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );
      return true;
    } catch (e) {
      debugPrint('[DownloadsController] Download all albums failed: $e');
      return false;
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllAlbums: false);
        notifyListeners();
      }
    }
  }

  /// Returns false when the request failed. See [downloadAllSongs].
  Future<bool> downloadAllPlaylists() async {
    final playlistService = PlaylistService();

    if (_connectionService.apiClient == null) {
      return false;
    }

    _state = _state.copyWith(isDownloadingAllPlaylists: true);
    notifyListeners();

    try {
      final downloadQuality = _qualityService.getDownloadQuality();
      final downloadOriginal = _qualityService.getDownloadOriginal();
      if (!playlistService.isLoaded) {
        await playlistService.loadPlaylists();
      }

      final library =
          await _connectionService.libraryReadFacade.getLibraryBundle();
      final songs = library.songs;
      final serverPlaylists = library.serverPlaylists;
      playlistService.updateServerPlaylists(serverPlaylists);
      final validSongIds = songs.map((song) => song.id).toSet();

      final localPlaylistSongIds = resolveLocalPlaylistSongIds(
        playlistService.playlists,
        validSongIds: validSongIds,
      );

      await _downloadManager.enqueueDownloadJob(
        songIds: localPlaylistSongIds.toList(),
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );
      return true;
    } catch (e) {
      debugPrint('[DownloadsController] Download all playlists failed: $e');
      return false;
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllPlaylists: false);
        notifyListeners();
      }
    }
  }

  Future<void> _loadCacheStats() async {
    final songSizeBytes = await _cacheManager.getSongCacheSize();
    final sizeMB = songSizeBytes / (1024 * 1024);
    final songCount = await _cacheManager.getSongCacheCount();
    final limit = _cacheManager.getCacheLimit();

    if (_disposed) return;
    _state = _state.copyWith(
      cacheSizeMB: sizeMB,
      cachedSongCount: songCount,
      cacheLimitMB: limit,
    );
    notifyListeners();
  }

  /// Called from [StreamBuilder] when the queue updates. Builds the grouped
  /// structures for the In Progress and Failed sections. Does not call
  /// [notifyListeners] — the stream already triggers a rebuild. Also flushes
  /// pending byte progress immediately so a status transition (e.g.
  /// downloading → completed) doesn't have to wait for the throttle window.
  void syncVisibleQueueState(List<DownloadTask> queue) {
    final signature = _buildQueueViewSignature(queue);
    if (signature == _lastQueueViewSignature) {
      return;
    }

    final completedTasks = <DownloadTask>[];
    final failedTasks = <DownloadTask>[];
    final inProgressTasks = <DownloadTask>[];

    for (var i = 0; i < queue.length; i++) {
      final task = queue[i];
      switch (task.status) {
        case DownloadStatus.downloading:
        case DownloadStatus.paused:
        case DownloadStatus.pending:
          inProgressTasks.add(task);
          _sessionTaskIds.add(task.id);
          break;
        case DownloadStatus.completed:
          completedTasks.add(task);
          break;
        case DownloadStatus.failed:
          failedTasks.add(task);
          break;
        case DownloadStatus.cancelled:
          break;
      }
    }

    final inProgressAlbums = _buildAlbumGroups(
      inProgressTasks,
      queue,
      sortByActivity: true,
    );
    final failedAlbums = _buildAlbumGroups(
      failedTasks,
      queue,
      sortByActivity: false,
    );

    _taskIdToAlbumKey
      ..clear()
      ..addEntries([
        for (final album in inProgressAlbums)
          for (final song in album.songs) MapEntry(song.id, album.key),
      ]);

    final groupedCompleted = groupByAlbum(completedTasks);
    final sortedCompletedAlbumKeys = groupedCompleted.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        final nameA = groupedCompleted[a]!.first.albumName ?? '';
        final nameB = groupedCompleted[b]!.first.albumName ?? '';
        return nameA.compareTo(nameB);
      });

    _lastQueueViewSignature = signature;
    _state = _state.copyWith(
      inProgressAlbums: inProgressAlbums,
      failedAlbums: failedAlbums,
      completedTasks: completedTasks,
      interruptedDownloadCount: _countInterruptedDownloads(queue),
      groupedCompletedTasks: groupedCompleted,
      sortedCompletedAlbumKeys: sortedCompletedAlbumKeys,
      hasAnyInProgress: inProgressAlbums.isNotEmpty,
      hasAnyFailed: failedAlbums.isNotEmpty,
    );

    _reconcileAlbumNotifiers(inProgressAlbums);
    _overallDirty = true;
    _flushProgress();
  }

  List<AlbumGroup> _buildAlbumGroups(
    List<DownloadTask> tasks,
    List<DownloadTask> orderingSource, {
    required bool sortByActivity,
  }) {
    if (tasks.isEmpty) return const <AlbumGroup>[];

    final orderHint = <String, int>{};
    for (var i = 0; i < orderingSource.length; i++) {
      final task = orderingSource[i];
      final key = task.albumId ?? '__singles__';
      orderHint.putIfAbsent(key, () => i);
    }

    final byKey = <String, List<DownloadTask>>{};
    for (final task in tasks) {
      final key = task.albumId ?? '__singles__';
      byKey.putIfAbsent(key, () => []).add(task);
    }

    final groups = <AlbumGroup>[];
    byKey.forEach((key, songs) {
      songs.sort(
        (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0),
      );
      final first = songs.first;
      var downloading = 0;
      var paused = 0;
      var queued = 0;
      var failed = 0;
      for (final song in songs) {
        switch (song.status) {
          case DownloadStatus.downloading:
            downloading++;
            break;
          case DownloadStatus.paused:
            paused++;
            break;
          case DownloadStatus.pending:
            queued++;
            break;
          case DownloadStatus.failed:
            failed++;
            break;
          case DownloadStatus.completed:
          case DownloadStatus.cancelled:
            break;
        }
      }
      groups.add(AlbumGroup(
        albumId: first.albumId,
        albumName: first.albumName ?? 'Singles',
        albumArtist: first.albumArtist ?? first.artist,
        albumArt: first.albumArt,
        songs: songs,
        downloadingCount: downloading,
        pausedCount: paused,
        queuedCount: queued,
        failedCount: failed,
        orderHint: orderHint[key] ?? 0,
      ));
    });

    groups.sort((a, b) {
      if (sortByActivity) {
        final aActive = a.downloadingCount > 0 ? 0 : 1;
        final bActive = b.downloadingCount > 0 ? 0 : 1;
        if (aActive != bActive) return aActive - bActive;
      }
      return a.orderHint.compareTo(b.orderHint);
    });

    return groups;
  }

  /// Drops album notifiers for albums that have left the in-progress set, and
  /// recomputes snapshots for albums that are still present (their song
  /// composition may have changed).
  void _reconcileAlbumNotifiers(List<AlbumGroup> currentAlbums) {
    final liveKeys = currentAlbums.map((a) => a.key).toSet();
    _albumProgressNotifiers.removeWhere((key, notifier) {
      if (liveKeys.contains(key)) return false;
      notifier.dispose();
      return true;
    });
    for (final album in currentAlbums) {
      final notifier = _albumProgressNotifiers[album.key];
      if (notifier != null) {
        notifier.value = _computeAlbumSnapshotForKey(album.key);
      }
    }
  }

  String _buildQueueViewSignature(List<DownloadTask> queue) {
    final buffer = StringBuffer();
    for (final task in queue) {
      buffer
        ..write(task.id)
        ..write(':')
        ..write(task.status.index)
        ..write('|');
    }
    return '${queue.length}#$buffer';
  }

  void pauseDownload(String taskId) {
    _downloadManager.pauseDownload(taskId);
  }

  Future<void> resumeDownload(String taskId) async {
    await _downloadManager.resumeDownload(taskId);
  }

  Future<int> resumeInterruptedDownloads() async {
    return _downloadManager.resumeInterruptedDownloads();
  }

  void cancelDownload(String taskId) {
    _downloadManager.cancelDownload(taskId);
  }

  Future<int> cancelInterruptedDownloads() async {
    return _downloadManager.cancelInterruptedDownloads();
  }

  void retryDownload(String taskId) {
    _downloadManager.retryDownload(taskId);
  }

  /// Retry every retryable failed task in the given album (`albumId == null`
  /// means singles). Used by the FailedAlbumCard "Retry all" action.
  void retryAlbum(String? albumId) {
    final key = albumId ?? '__singles__';
    AlbumGroup? album;
    for (final candidate in _state.failedAlbums) {
      if (candidate.key == key) {
        album = candidate;
        break;
      }
    }
    if (album == null) return;
    for (final song in album.songs) {
      if (song.status == DownloadStatus.failed && song.canRetry()) {
        _downloadManager.retryDownload(song.id);
      }
    }
  }

  Future<void> clearAllDownloads() async {
    await _downloadManager.clearAllDownloads();
  }

  Future<void> clearCache() async {
    await _cacheManager.clearSongCache();
    await _loadCacheStats();
  }

  Future<void> setDownloadOriginal(bool value) async {
    if (value && _state.downloadQuality != StreamingQuality.high) {
      return;
    }
    await _qualityService.setDownloadOriginal(value);
    if (!_disposed) {
      final qualitySettings = _qualityService.settings;
      _state = _state.copyWith(
        downloadQuality: qualitySettings.downloadQuality,
        downloadOriginal: qualitySettings.downloadOriginal,
      );
      notifyListeners();
    }
  }

  Future<void> setAutoResumeInterruptedOnLaunch(bool enabled) async {
    await _downloadManager.setAutoResumeInterruptedOnLaunch(enabled);
    if (!_disposed) {
      _state = _state.copyWith(autoResumeInterruptedOnLaunch: enabled);
      notifyListeners();
    }
  }

  Future<void> setCoolerDownloads(bool enabled) async {
    await _downloadManager.setCoolerDownloads(enabled);
    if (!_disposed) {
      _state = _state.copyWith(coolerDownloads: enabled);
      notifyListeners();
    }
  }

  void setCacheLimitDuringDrag(int limitMB) {
    _state = _state.copyWith(cacheLimitMB: limitMB);
    notifyListeners();
  }

  Future<void> commitCacheLimit(int limitMB) async {
    await _cacheManager.setCacheLimit(limitMB);
  }

  void toggleAlbumExpanded(String key) {
    final next = Set<String>.from(_state.expandedAlbums);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _state = _state.copyWith(expandedAlbums: next);
    notifyListeners();
  }

  Future<void> deleteAlbumDownloads(String? albumId) async {
    await _downloadManager.deleteAlbumDownloads(albumId);
  }

  int _countInterruptedDownloads(List<DownloadTask> queue) {
    return queue.where(isInterruptedDownloadTask).length;
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _cacheSubscription?.cancel();
    _progressSubscription?.cancel();
    _queueSubscription?.cancel();
    _qualitySettingsSubscription?.cancel();
    _webSocketSubscription?.cancel();
    _cacheStatsRefreshTimer?.cancel();
    _countRefreshTimer?.cancel();
    for (final notifier in _taskProgressNotifiers.values) {
      notifier.dispose();
    }
    _taskProgressNotifiers.clear();
    for (final notifier in _albumProgressNotifiers.values) {
      notifier.dispose();
    }
    _albumProgressNotifiers.clear();
    _overallProgressNotifier.dispose();
    super.dispose();
  }
}
