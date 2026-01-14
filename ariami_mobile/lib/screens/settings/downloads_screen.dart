import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/download_task.dart';
import '../../services/download/download_manager.dart';
import '../../services/cache/cache_manager.dart';
import '../../services/api/connection_service.dart';
import '../../widgets/common/cached_artwork.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  late Future<void> _initFuture;

  // Cache statistics
  double _cacheSizeMB = 0;
  int _cachedArtworkCount = 0;
  int _cachedSongCount = 0;
  int _cacheLimitMB = 500;
  StreamSubscription<void>? _cacheSubscription;

  // Progress tracking for smooth UI updates
  StreamSubscription<DownloadProgress>? _progressSubscription;
  final Map<String, DownloadProgress> _currentProgress = {};
  DateTime _lastProgressUpdate = DateTime.now();

  // Track which albums are expanded in the Downloaded section
  // Uses albumId as key, 'singles' for songs without album
  final Set<String> _expandedAlbums = {};

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    await _downloadManager.initialize();
    await _cacheManager.initialize();
    await _loadCacheStats();

    // Listen to cache updates
    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((_) {
      _loadCacheStats();
    });

    // Listen to progress updates (separate from queue changes)
    _progressSubscription = _downloadManager.progressStream.listen((progress) {
      // Store latest progress
      _currentProgress[progress.taskId] = progress;

      // Throttle UI updates to ~10 FPS (100ms intervals) for smooth rendering
      final now = DateTime.now();
      if (now.difference(_lastProgressUpdate).inMilliseconds >= 100) {
        if (mounted) {
          setState(() {
            _lastProgressUpdate = now;
          });
        }
      }
    });
  }

  Future<void> _loadCacheStats() async {
    final sizeMB = await _cacheManager.getTotalCacheSizeMB();
    final artworkCount = await _cacheManager.getArtworkCacheCount();
    final songCount = await _cacheManager.getSongCacheCount();
    final limit = _cacheManager.getCacheLimit();

    if (mounted) {
      setState(() {
        _cacheSizeMB = sizeMB;
        _cachedArtworkCount = artworkCount;
        _cachedSongCount = songCount;
        _cacheLimitMB = limit;
      });
    }
  }

  @override
  void dispose() {
    _cacheSubscription?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _pauseDownload(String taskId) {
    _downloadManager.pauseDownload(taskId);
  }

  Future<void> _resumeDownload(String taskId) async {
    await _downloadManager.resumeDownload(taskId);
  }

  void _cancelDownload(String taskId) {
    _downloadManager.cancelDownload(taskId);
  }

  void _retryDownload(String taskId) {
    _downloadManager.retryDownload(taskId);
  }

  Future<void> _clearAllDownloads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Downloads'),
        content: const Text(
          'Are you sure you want to delete all downloaded songs? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadManager.clearAllDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloads cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (_downloadManager.queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAllDownloads,
              tooltip: 'Clear all downloads',
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error initializing downloads: ${snapshot.error}'),
            );
          }

          return StreamBuilder<List<DownloadTask>>(
            stream: _downloadManager.queueStream,
            initialData: _downloadManager.queue,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? [];

              if (queue.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.download_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No downloads yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start downloading songs to see them here',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                padding: EdgeInsets.only(
                  bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
                ),
                children: [
                  // Downloads statistics card
                  _buildStatisticsCard(context, isDark),

                  // Cache section
                  _buildCacheSection(context, isDark),

                  const SizedBox(height: 16),

                  // Active downloads section
                  ..._buildSection(
                    context,
                    'Active Downloads',
                    queue
                        .where((t) =>
                            t.status == DownloadStatus.downloading ||
                            t.status == DownloadStatus.paused)
                        .toList(),
                    isDark,
                  ),

                  // Pending downloads section
                  ..._buildSection(
                    context,
                    'Pending',
                    queue.where((t) => t.status == DownloadStatus.pending).toList(),
                    isDark,
                  ),

                  // Completed downloads section - grouped by album
                  ..._buildDownloadedSection(
                    context,
                    queue
                        .where((t) => t.status == DownloadStatus.completed)
                        .toList(),
                    isDark,
                  ),

                  // Failed downloads section
                  ..._buildSection(
                    context,
                    'Failed',
                    queue.where((t) => t.status == DownloadStatus.failed).toList(),
                    isDark,
                  ),

                  const SizedBox(height: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCacheSection(BuildContext context, bool isDark) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_done,
                  size: 20,
                  color: Colors.blue[400],
                ),
                const SizedBox(width: 8),
                Text(
                  'Cache',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Cache size info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_cacheSizeMB.toStringAsFixed(1)} MB / $_cacheLimitMB MB',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  '$_cachedSongCount songs, $_cachedArtworkCount artworks',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _cacheLimitMB > 0 ? (_cacheSizeMB / _cacheLimitMB).clamp(0.0, 1.0) : 0.0,
                minHeight: 6,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
              ),
            ),
            const SizedBox(height: 12),
            
            // Cache limit slider
            Row(
              children: [
                Text(
                  'Limit:',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _cacheLimitMB.toDouble(),
                    min: 100,
                    max: 2000,
                    divisions: 19,
                    label: '$_cacheLimitMB MB',
                    onChanged: (value) {
                      setState(() {
                        _cacheLimitMB = value.round();
                      });
                    },
                    onChangeEnd: (value) {
                      _cacheManager.setCacheLimit(value.round());
                    },
                  ),
                ),
                Text(
                  '$_cacheLimitMB MB',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Clear cache button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _cacheSizeMB > 0 ? _clearCache : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear Cache'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
            
            // Cache info text
            Text(
              'Cached content is auto-downloaded when you play songs. It can be cleared to free space.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will remove all cached songs and artwork. Explicitly downloaded songs will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cacheManager.clearAllCache();
      await _loadCacheStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    }
  }

  Widget _buildStatisticsCard(BuildContext context, bool isDark) {
    final stats = _downloadManager.getQueueStats();
    final sizeMB = _downloadManager.getTotalDownloadedSizeMB();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage Used',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sizeMB.toStringAsFixed(2)} MB',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.completed} song${stats.completed != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (stats.downloading > 0)
                      Text(
                        '${stats.downloading} downloading',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[600],
                        ),
                      ),
                    if (stats.failed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '${stats.failed} failed',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSection(
    BuildContext context,
    String title,
    List<DownloadTask> tasks,
    bool isDark,
  ) {
    if (tasks.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.blue[700],
            letterSpacing: 0.5,
          ),
        ),
      ),
      ...tasks.asMap().entries.map((entry) {
        final index = entry.key;
        final task = entry.value;
        final isLast = index == tasks.length - 1;

        return _buildDownloadItem(context, task, isDark, isLast);
      }),
    ];
  }

  /// Group completed downloads by album
  Map<String?, List<DownloadTask>> _groupByAlbum(List<DownloadTask> tasks) {
    final Map<String?, List<DownloadTask>> grouped = {};
    for (final task in tasks) {
      final key = task.albumId; // null key = Singles
      grouped.putIfAbsent(key, () => []).add(task);
    }
    // Sort songs within each album by track number
    for (final songs in grouped.values) {
      songs.sort((a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));
    }
    return grouped;
  }

  /// Calculate total size in bytes for a list of tasks
  int _calculateTotalBytes(List<DownloadTask> tasks) {
    return tasks.fold(0, (sum, task) => sum + task.bytesDownloaded);
  }

  /// Format bytes to human-readable string
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Build the Downloaded section with album grouping
  List<Widget> _buildDownloadedSection(
    BuildContext context,
    List<DownloadTask> completedTasks,
    bool isDark,
  ) {
    if (completedTasks.isEmpty) return [];

    final grouped = _groupByAlbum(completedTasks);
    final widgets = <Widget>[];

    // Section header
    widgets.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(
          'Downloaded',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.blue[700],
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    // Sort albums: albums with names first (alphabetically), then Singles (null) at the end
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1; // null (Singles) goes last
        if (b == null) return -1;
        // Sort by album name
        final nameA = grouped[a]!.first.albumName ?? '';
        final nameB = grouped[b]!.first.albumName ?? '';
        return nameA.compareTo(nameB);
      });

    // Build album cards
    for (int i = 0; i < sortedKeys.length; i++) {
      final albumId = sortedKeys[i];
      final songs = grouped[albumId]!;
      final isLast = i == sortedKeys.length - 1;

      if (albumId == null) {
        // Singles section
        widgets.add(_buildSinglesCard(context, songs, isDark, isLast));
      } else {
        // Album card
        widgets.add(_buildAlbumCard(context, albumId, songs, isDark, isLast));
      }
    }

    return widgets;
  }

  /// Build an album card with expand/collapse functionality
  Widget _buildAlbumCard(
    BuildContext context,
    String albumId,
    List<DownloadTask> songs,
    bool isDark,
    bool isLast,
  ) {
    final isExpanded = _expandedAlbums.contains(albumId);
    final firstSong = songs.first;
    final albumName = firstSong.albumName ?? 'Unknown Album';
    final albumArtist = firstSong.albumArtist ?? firstSong.artist;
    final totalBytes = _calculateTotalBytes(songs);
    final artworkUrl = firstSong.albumArt;

    return Column(
      children: [
        Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Column(
            children: [
              // Album header
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedAlbums.remove(albumId);
                    } else {
                      _expandedAlbums.add(albumId);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Album artwork
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: CachedArtwork(
                            albumId: albumId,
                            artworkUrl: artworkUrl.isNotEmpty ? artworkUrl : null,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            fallbackIcon: Icons.album,
                            fallbackIconSize: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Album info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              albumArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${songs.length} song${songs.length != 1 ? 's' : ''} • ${_formatBytes(totalBytes)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete album button
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red[400],
                          size: 22,
                        ),
                        onPressed: () => _confirmDeleteAlbum(
                          context,
                          albumId,
                          albumName,
                          songs.length,
                        ),
                        tooltip: 'Delete album',
                      ),
                      // Expand/collapse icon
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded songs list
              if (isExpanded)
                Container(
                  color: isDark ? Colors.grey[850] : Colors.grey[50],
                  child: Column(
                    children: songs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final song = entry.value;
                      final isLastSong = index == songs.length - 1;
                      return _buildAlbumSongItem(
                          context, song, isDark, isLastSong);
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),
      ],
    );
  }

  /// Build the Singles card for songs without an album
  Widget _buildSinglesCard(
    BuildContext context,
    List<DownloadTask> songs,
    bool isDark,
    bool isLast,
  ) {
    const singlesKey = 'singles';
    final isExpanded = _expandedAlbums.contains(singlesKey);
    final totalBytes = _calculateTotalBytes(songs);
    final connectionService = ConnectionService();

    // Get first song for cover artwork
    final firstSong = songs.isNotEmpty ? songs.first : null;
    final artworkUrl = firstSong != null && connectionService.apiClient != null
        ? '${connectionService.apiClient!.baseUrl}/song-artwork/${firstSong.songId}'
        : null;
    final cacheId = firstSong != null ? 'song_${firstSong.songId}' : '';

    return Column(
      children: [
        Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Column(
            children: [
              // Singles header
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedAlbums.remove(singlesKey);
                    } else {
                      _expandedAlbums.add(singlesKey);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // First song's artwork or fallback
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: firstSong != null
                              ? CachedArtwork(
                                  albumId: cacheId,
                                  artworkUrl: artworkUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  fallbackIcon: Icons.music_note,
                                  fallbackIconSize: 28,
                                )
                              : Container(
                                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                                  child: Icon(
                                    Icons.music_note,
                                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                                    size: 28,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Singles info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Singles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Songs without album',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${songs.length} song${songs.length != 1 ? 's' : ''} • ${_formatBytes(totalBytes)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete all singles button
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red[400],
                          size: 22,
                        ),
                        onPressed: () => _confirmDeleteAlbum(
                          context,
                          null,
                          'Singles',
                          songs.length,
                        ),
                        tooltip: 'Delete all singles',
                      ),
                      // Expand/collapse icon
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded songs list
              if (isExpanded)
                Container(
                  color: isDark ? Colors.grey[850] : Colors.grey[50],
                  child: Column(
                    children: songs.asMap().entries.map((entry) {
                      final index = entry.key;
                      final song = entry.value;
                      final isLastSong = index == songs.length - 1;
                      return _buildAlbumSongItem(
                          context, song, isDark, isLastSong);
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),
      ],
    );
  }

  /// Build a song item within an expanded album
  Widget _buildAlbumSongItem(
    BuildContext context,
    DownloadTask task,
    bool isDark,
    bool isLast,
  ) {
    final connectionService = ConnectionService();

    // Determine artwork URL and cache ID based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (task.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${task.albumId}'
          : null;
      cacheId = task.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${task.songId}'
          : null;
      cacheId = 'song_${task.songId}';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Song artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CachedArtwork(
                    albumId: cacheId,
                    artworkUrl: artworkUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.music_note,
                    fallbackIconSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Song info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // File size
              Text(
                _formatBytes(task.bytesDownloaded),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: Colors.red[400],
                  size: 18,
                ),
                onPressed: () => _cancelDownload(task.id),
                tooltip: 'Remove song',
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
          ),
      ],
    );
  }

  /// Confirm deletion of an album's downloads
  Future<void> _confirmDeleteAlbum(
    BuildContext context,
    String? albumId,
    String albumName,
    int songCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $albumName'),
        content: Text(
          'Are you sure you want to delete $songCount downloaded song${songCount != 1 ? 's' : ''} from "$albumName"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadManager.deleteAlbumDownloads(albumId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted downloads from "$albumName"')),
        );
      }
    }
  }

  Widget _buildDownloadItem(
    BuildContext context,
    DownloadTask task,
    bool isDark,
    bool isLast,
  ) {
    return Column(
      children: [
        Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and artist
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            task.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusIcon(task),
                  ],
                ),
                const SizedBox(height: 8),

                // Progress bar or status text
                if (task.status == DownloadStatus.downloading)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _currentProgress[task.id]?.progress ?? task.progress,
                          minHeight: 4,
                          backgroundColor:
                              isDark ? Colors.grey[800] : Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue[600]!,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_currentProgress[task.id]?.percentage ?? task.getPercentage()}% • ${_formatBytes(_currentProgress[task.id]?.bytesDownloaded ?? task.bytesDownloaded)} / ${_formatBytes(_currentProgress[task.id]?.totalBytes ?? task.totalBytes)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (task.status == DownloadStatus.paused)
                  Text(
                    'Paused • ${_currentProgress[task.id]?.percentage ?? task.getPercentage()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[600],
                    ),
                  )
                else if (task.status == DownloadStatus.completed)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.green[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Downloaded • ${task.getFormattedTotalBytes()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                        ),
                      ),
                    ],
                  )
                else if (task.status == DownloadStatus.failed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              task.errorMessage ?? 'Download failed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (task.canRetry())
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Retries remaining: ${DownloadTask.maxRetries - task.retryCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  )
                else
                  Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),

                const SizedBox(height: 8),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _buildActionButtons(task),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildActionButtons(DownloadTask task) {
    final buttons = <Widget>[];

    if (task.status == DownloadStatus.downloading) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _pauseDownload(task.id),
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('Pause'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        TextButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.red,
          ),
        ),
      );
    } else if (task.status == DownloadStatus.paused) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _resumeDownload(task.id),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Resume'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.orange,
          ),
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        TextButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.red,
          ),
        ),
      );
    } else if (task.status == DownloadStatus.failed && task.canRetry()) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _retryDownload(task.id),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.orange,
          ),
        ),
      );
    } else if (task.status == DownloadStatus.completed) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Remove'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.red,
          ),
        ),
      );
    } else if (task.status == DownloadStatus.pending) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Remove'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.red,
          ),
        ),
      );
    }

    return buttons;
  }

  Widget _buildStatusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: _currentProgress[task.id]?.progress ?? task.progress,
            strokeWidth: 2,
          ),
        );
      case DownloadStatus.paused:
        return Icon(Icons.pause_circle, size: 20, color: Colors.orange[600]);
      case DownloadStatus.completed:
        return Icon(Icons.check_circle, size: 20, color: Colors.green[600]);
      case DownloadStatus.failed:
        return Icon(Icons.error, size: 20, color: Colors.red[600]);
      case DownloadStatus.pending:
      case DownloadStatus.cancelled:
        return Icon(Icons.schedule, size: 20, color: Colors.grey[600]);
    }
  }
}
