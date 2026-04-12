import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/download_task.dart';
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

  String _lastQueueViewSignature = '';
  DateTime _lastProgressUpdate = DateTime.now();

  StreamSubscription<CacheUpdateEvent>? _cacheSubscription;
  Timer? _cacheStatsRefreshTimer;
  Timer? _countRefreshTimer;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  StreamSubscription<WsMessage>? _webSocketSubscription;

  bool _disposed = false;

  late final Future<void> initializeFuture = _initialize();

  Future<void> _initialize() async {
    await _downloadManager.initialize();
    await _cacheManager.initialize();
    await _qualityService.initialize();
    await _loadCacheStats();
    _state = _state.copyWith(
      downloadOriginal: _qualityService.getDownloadOriginal(),
      autoResumeInterruptedOnLaunch:
          _downloadManager.getAutoResumeInterruptedOnLaunch(),
      interruptedDownloadCount:
          _countInterruptedDownloads(_downloadManager.queue),
    );

    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((_) {
      _scheduleCacheStatsRefresh();
    });

    _progressSubscription = _downloadManager.progressStream.listen((progress) {
      final next = Map<String, DownloadProgress>.from(_state.currentProgress)
        ..[progress.taskId] = progress;
      _state = _state.copyWith(currentProgress: next);

      final now = DateTime.now();
      if (now.difference(_lastProgressUpdate).inMilliseconds >= 100) {
        _lastProgressUpdate = now;
        if (!_disposed) {
          notifyListeners();
        }
      }
    });

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

      playlistService.updateServerPlaylists(serverPlaylists);

      final librarySongIds = songs.map((song) => song.id).toSet();
      final albumSongCounts = <String, int>{};
      for (final song in songs) {
        if (song.albumId != null) {
          albumSongCounts[song.albumId!] =
              (albumSongCounts[song.albumId!] ?? 0) + 1;
        }
      }

      final playlistSongIds = <String>{};
      for (final playlist in playlistService.playlists) {
        playlistSongIds.addAll(playlist.songIds);
      }
      for (final serverPlaylist in serverPlaylists) {
        playlistSongIds.addAll(serverPlaylist.songIds);
      }
      playlistSongIds.removeWhere((songId) => !librarySongIds.contains(songId));

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

    final localPlaylistSongIds = <String>{};
    for (final playlist in playlistService.playlists) {
      localPlaylistSongIds.addAll(playlist.songIds);
    }
    for (final serverPlaylist in playlistService.visibleServerPlaylists) {
      localPlaylistSongIds.addAll(serverPlaylist.songIds);
    }

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

  Future<void> downloadAllSongs() async {
    if (_connectionService.apiClient == null) {
      return;
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
    } catch (_) {
      // Silently handle errors
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllSongs: false);
        notifyListeners();
      }
    }
  }

  Future<void> downloadAllAlbums() async {
    if (_connectionService.apiClient == null) {
      return;
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
    } catch (_) {
      // Silently handle errors
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllAlbums: false);
        notifyListeners();
      }
    }
  }

  Future<void> downloadAllPlaylists() async {
    final playlistService = PlaylistService();

    if (_connectionService.apiClient == null) {
      return;
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

      final localPlaylistSongIds = <String>{};
      for (final playlist in playlistService.playlists) {
        localPlaylistSongIds.addAll(playlist.songIds);
      }
      localPlaylistSongIds
          .removeWhere((songId) => !validSongIds.contains(songId));

      final serverPlaylistIds =
          serverPlaylists.map((playlist) => playlist.id).toList();

      await _downloadManager.enqueueDownloadJob(
        songIds: localPlaylistSongIds.toList(),
        playlistIds: serverPlaylistIds,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );
    } catch (_) {
      // Silently handle errors
    } finally {
      if (!_disposed) {
        _state = _state.copyWith(isDownloadingAllPlaylists: false);
        notifyListeners();
      }
    }
  }

  Future<void> _loadCacheStats() async {
    final sizeMB = await _cacheManager.getTotalCacheSizeMB();
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

  /// Called from [StreamBuilder] when the queue updates. Does not call
  /// [notifyListeners] — the stream already triggers a rebuild.
  void syncVisibleQueueState(List<DownloadTask> queue) {
    final signature = _buildQueueViewSignature(queue);
    if (signature == _lastQueueViewSignature) {
      return;
    }

    final activeTasks = <DownloadTask>[];
    final pendingTasks = <DownloadTask>[];
    final completedTasks = <DownloadTask>[];
    final failedTasks = <DownloadTask>[];

    for (final task in queue) {
      switch (task.status) {
        case DownloadStatus.downloading:
        case DownloadStatus.paused:
          activeTasks.add(task);
          break;
        case DownloadStatus.pending:
          pendingTasks.add(task);
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
      activeTasks: activeTasks,
      pendingTasks: pendingTasks,
      completedTasks: completedTasks,
      failedTasks: failedTasks,
      interruptedDownloadCount: _countInterruptedDownloads(queue),
      groupedCompletedTasks: groupedCompleted,
      sortedCompletedAlbumKeys: sortedCompletedAlbumKeys,
    );
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

  Future<void> clearAllDownloads() async {
    await _downloadManager.clearAllDownloads();
  }

  Future<void> clearCache() async {
    await _cacheManager.clearAllCache();
    await _loadCacheStats();
  }

  Future<void> setDownloadOriginal(bool value) async {
    await _qualityService.setDownloadOriginal(value);
    if (!_disposed) {
      _state = _state.copyWith(downloadOriginal: value);
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
    _cacheSubscription?.cancel();
    _progressSubscription?.cancel();
    _queueSubscription?.cancel();
    _webSocketSubscription?.cancel();
    _cacheStatsRefreshTimer?.cancel();
    _countRefreshTimer?.cancel();
    super.dispose();
  }
}
