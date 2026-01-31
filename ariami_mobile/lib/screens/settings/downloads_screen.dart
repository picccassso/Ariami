import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../models/download_task.dart';
import '../../services/download/download_manager.dart';
import '../../services/cache/cache_manager.dart';
import '../../services/api/connection_service.dart';
import '../../services/playlist_service.dart';
import '../../services/quality/quality_settings_service.dart';
import '../../widgets/common/cached_artwork.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final QualitySettingsService _qualityService = QualitySettingsService();
  late Future<void> _initFuture;

  // Cache statistics
  double _cacheSizeMB = 0;
  int _cachedSongCount = 0;
  int _cacheLimitMB = 500;
  StreamSubscription<void>? _cacheSubscription;

  // Progress tracking for smooth UI updates
  StreamSubscription<DownloadProgress>? _progressSubscription;
  StreamSubscription<List<DownloadTask>>? _queueSubscription;
  final Map<String, DownloadProgress> _currentProgress = {};
  DateTime _lastProgressUpdate = DateTime.now();

  // Track which albums are expanded in the Downloaded section
  // Uses albumId as key, 'singles' for songs without album
  final Set<String> _expandedAlbums = {};

  // Download All section state
  int _totalSongCount = 0;
  int _totalAlbumCount = 0;
  int _downloadedSongCount = 0;
  int _downloadedAlbumCount = 0;
  int _downloadedPlaylistSongCount = 0;
  int _totalPlaylistSongCount = 0;
  bool _isDownloadingAllSongs = false;
  bool _isDownloadingAllAlbums = false;
  bool _isDownloadingAllPlaylists = false;
  bool _isLoadingCounts = true;
  bool _downloadOriginal = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    await _downloadManager.initialize();
    await _cacheManager.initialize();
    await _qualityService.initialize();
    await _loadCacheStats();
    _downloadOriginal = _qualityService.getDownloadOriginal();

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

    // Listen to queue changes to refresh Download All counts when downloads complete
    _queueSubscription = _downloadManager.queueStream.listen((_) {
      // Refresh counts when queue changes (e.g., download completes)
      _loadDownloadAllCounts();
    });

    // Load counts for Download All section
    await _loadDownloadAllCounts();
  }

  Future<void> _loadDownloadAllCounts() async {
    final connectionService = ConnectionService();
    final playlistService = PlaylistService();

    // Ensure download manager is initialized
    if (!_downloadManager.isInitialized) {
      await _downloadManager.initialize();
    }

    // Ensure playlist service is loaded
    if (!playlistService.isLoaded) {
      await playlistService.loadPlaylists();
    }

    // Initialize counts with local data first (useful for offline mode)
    final allDownloadedTasks = _downloadManager.queue.where((t) => t.status == DownloadStatus.completed).toList();
    final downloadedSongIds = allDownloadedTasks.map((t) => t.songId).toSet();
    int localDownloadedSongs = allDownloadedTasks.length;
    
    // Group local downloads by album to estimate downloaded album count
    final Set<String> localAlbumIds = allDownloadedTasks
        .where((t) => t.albumId != null)
        .map((t) => t.albumId!)
        .toSet();
        
    // Calculate playlist counts from local service data
    final Set<String> localPlaylistSongIds = {};
    for (final playlist in playlistService.playlists) {
      localPlaylistSongIds.addAll(playlist.songIds);
    }
    for (final serverPlaylist in playlistService.visibleServerPlaylists) {
      localPlaylistSongIds.addAll(serverPlaylist.songIds);
    }
    
    int localDownloadedPlaylistSongs = 0;
    for (final songId in localPlaylistSongIds) {
      if (downloadedSongIds.contains(songId)) {
        localDownloadedPlaylistSongs++;
      }
    }

    // Get song and album counts from API if connected
    if (connectionService.apiClient != null) {
      try {
        final library = await connectionService.apiClient!.getLibrary();

        // Count downloaded songs
        int downloadedSongs = 0;
        for (final song in library.songs) {
          if (await _downloadManager.isSongDownloaded(song.id)) {
            downloadedSongs++;
          }
        }

        // Count fully downloaded albums (all songs in album are downloaded)
        int downloadedAlbums = 0;
        final albumSongsMap = <String, List<String>>{};
        for (final song in library.songs) {
          if (song.albumId != null) {
            albumSongsMap.putIfAbsent(song.albumId!, () => []).add(song.id);
          }
        }
        for (final album in library.albums) {
          final albumSongIds = albumSongsMap[album.id] ?? [];
          if (albumSongIds.isNotEmpty) {
            bool allDownloaded = true;
            for (final songId in albumSongIds) {
              if (!await _downloadManager.isSongDownloaded(songId)) {
                allDownloaded = false;
                break;
              }
            }
            if (allDownloaded) {
              downloadedAlbums++;
            }
          }
        }

        // Count downloaded playlist songs
        final Set<String> allPlaylistSongIds = {};
        for (final playlist in playlistService.playlists) {
          allPlaylistSongIds.addAll(playlist.songIds);
        }
        for (final serverPlaylist in playlistService.visibleServerPlaylists) {
          allPlaylistSongIds.addAll(serverPlaylist.songIds);
        }

        // Build a set of library song IDs for comparison
        final librarySongIds = library.songs.map((s) => s.id).toSet();

        int downloadedPlaylistSongs = 0;
        for (final songId in allPlaylistSongIds) {
          if (!librarySongIds.contains(songId)) {
            continue; 
          }
          if (await _downloadManager.isSongDownloaded(songId)) {
            downloadedPlaylistSongs++;
          }
        }

        // Recalculate total to only count valid playlist songs
        final validPlaylistSongCount = allPlaylistSongIds.where((id) => librarySongIds.contains(id)).length;

        if (mounted) {
          setState(() {
            _totalSongCount = library.songs.length;
            _totalAlbumCount = library.albums.length;
            _downloadedSongCount = downloadedSongs;
            _downloadedAlbumCount = downloadedAlbums;
            _totalPlaylistSongCount = validPlaylistSongCount;
            _downloadedPlaylistSongCount = downloadedPlaylistSongs;
            _isLoadingCounts = false;
          });
        }
      } catch (e) {
        // Error loading library counts - fallback to local counts
        if (mounted) {
          setState(() {
            _totalSongCount = localDownloadedSongs; 
            _totalAlbumCount = localAlbumIds.length;
            _downloadedSongCount = localDownloadedSongs;
            _downloadedAlbumCount = localAlbumIds.length;
            _totalPlaylistSongCount = localPlaylistSongIds.length;
            _downloadedPlaylistSongCount = localDownloadedPlaylistSongs;
            _isLoadingCounts = false;
          });
        }
      }
    } else {
      // Disconnected - show local counts
      if (mounted) {
        setState(() {
          _totalSongCount = localDownloadedSongs;
          _totalAlbumCount = localAlbumIds.length;
          _downloadedSongCount = localDownloadedSongs;
          _downloadedAlbumCount = localAlbumIds.length;
          _totalPlaylistSongCount = localPlaylistSongIds.length;
          _downloadedPlaylistSongCount = localDownloadedPlaylistSongs;
          _isLoadingCounts = false;
        });
      }
    }
  }

  Future<void> _downloadAllSongs() async {
    final connectionService = ConnectionService();
    if (connectionService.apiClient == null) {
      return;
    }

    setState(() {
      _isDownloadingAllSongs = true;
    });

    try {
      // Use getLibrary() instead of getSongs() as it returns the full library
      final library = await connectionService.apiClient!.getLibrary();
      int queuedCount = 0;

      // Build album lookup map for album metadata
      final albumMap = {for (final album in library.albums) album.id: album};

      for (final song in library.songs) {
        // Build download URL with current download mode/quality
        final baseDownloadUrl = connectionService.apiClient!.getDownloadUrl(song.id);
        final downloadUrl = _qualityService.getDownloadUrlWithQuality(baseDownloadUrl);

        // Build artwork URL and get album metadata
        String artworkUrl = '';
        String? albumName;
        String? albumArtist;
        if (song.albumId != null) {
          artworkUrl = '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}';
          final album = albumMap[song.albumId];
          if (album != null) {
            albumName = album.title;
            albumArtist = album.artist;
          }
        }

        await _downloadManager.downloadSong(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
          albumName: albumName,
          albumArtist: albumArtist,
          albumArt: artworkUrl,
          downloadUrl: downloadUrl,
          duration: song.duration,
          trackNumber: song.trackNumber,
          totalBytes: 0, // Will be determined during download
        );
        queuedCount++;

        // Small delay to avoid overwhelming the server
        if (queuedCount % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

    } catch (e) {
      // Silently handle errors
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAllSongs = false;
        });
      }
    }
  }

  Future<void> _downloadAllAlbums() async {
    final connectionService = ConnectionService();
    if (connectionService.apiClient == null) {
      return;
    }

    setState(() {
      _isDownloadingAllAlbums = true;
    });

    try {
      // Use getLibrary() to get albums with their songs
      final library = await connectionService.apiClient!.getLibrary();
      int totalSongsQueued = 0;

      // Build a map of albumId -> songs for quick lookup
      final Map<String, List<dynamic>> albumSongsMap = {};
      for (final song in library.songs) {
        if (song.albumId != null) {
          albumSongsMap.putIfAbsent(song.albumId!, () => []).add(song);
        }
      }

      for (final album in library.albums) {
        final albumSongs = albumSongsMap[album.id] ?? [];

        // Build song maps for downloadAlbum
        final songMaps = albumSongs.map((song) {
          final baseDownloadUrl = connectionService.apiClient!.getDownloadUrl(song.id);
          final downloadUrl = _qualityService.getDownloadUrlWithQuality(baseDownloadUrl);
          final artworkUrl = '${connectionService.apiClient!.baseUrl}/artwork/${album.id}';

          return {
            'id': song.id,
            'title': song.title,
            'artist': song.artist,
            'albumId': album.id,
            'albumName': album.title,
            'albumArtist': album.artist,
            'albumArt': artworkUrl,
            'downloadUrl': downloadUrl,
            'duration': song.duration,
            'trackNumber': song.trackNumber,
            'fileSize': 0, // Will be determined during download
          };
        }).toList();

        if (songMaps.isNotEmpty) {
          await _downloadManager.downloadAlbum(
            songs: songMaps,
            albumId: album.id,
            albumName: album.title,
            albumArtist: album.artist,
          );
          totalSongsQueued += songMaps.length;

          // Small delay to avoid overwhelming the server
          if (totalSongsQueued % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      }

    } catch (e) {
      // Silently handle errors
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAllAlbums = false;
        });
      }
    }
  }

  Future<void> _downloadAllPlaylists() async {
    final connectionService = ConnectionService();
    final playlistService = PlaylistService();

    if (connectionService.apiClient == null) {
      return;
    }

    setState(() {
      _isDownloadingAllPlaylists = true;
    });

    try {
      // Collect all unique song IDs from all playlists
      final Set<String> allSongIds = {};

      // From local playlists
      for (final playlist in playlistService.playlists) {
        allSongIds.addAll(playlist.songIds);
      }

      // From visible server playlists
      for (final serverPlaylist in playlistService.visibleServerPlaylists) {
        allSongIds.addAll(serverPlaylist.songIds);
      }

      if (allSongIds.isEmpty) {
        return;
      }

      // Fetch library to get song metadata
      final library = await connectionService.apiClient!.getLibrary();
      final songMap = {for (final s in library.songs) s.id: s};
      final albumMap = {for (final album in library.albums) album.id: album};

      int queuedCount = 0;
      for (final songId in allSongIds) {
        final song = songMap[songId];
        if (song == null) continue;

        final baseDownloadUrl = connectionService.apiClient!.getDownloadUrl(song.id);
        final downloadUrl = _qualityService.getDownloadUrlWithQuality(baseDownloadUrl);
        String artworkUrl = '';
        String? albumName;
        String? albumArtist;
        if (song.albumId != null) {
          artworkUrl = '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}';
          final album = albumMap[song.albumId];
          if (album != null) {
            albumName = album.title;
            albumArtist = album.artist;
          }
        }

        await _downloadManager.downloadSong(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
          albumName: albumName,
          albumArtist: albumArtist,
          albumArt: artworkUrl,
          downloadUrl: downloadUrl,
          duration: song.duration,
          trackNumber: song.trackNumber,
          totalBytes: 0, // Will be determined during download
        );
        queuedCount++;

        // Small delay to avoid overwhelming the server
        if (queuedCount % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

    } catch (e) {
      // Silently handle errors
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAllPlaylists = false;
        });
      }
    }
  }

  Future<void> _loadCacheStats() async {
    final sizeMB = await _cacheManager.getTotalCacheSizeMB();
    final songCount = await _cacheManager.getSongCacheCount();
    final limit = _cacheManager.getCacheLimit();

    if (mounted) {
      setState(() {
        _cacheSizeMB = sizeMB;
        _cachedSongCount = songCount;
        _cacheLimitMB = limit;
      });
    }
  }

  @override
  void dispose() {
    _cacheSubscription?.cancel();
    _progressSubscription?.cancel();
    _queueSubscription?.cancel();
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

              return ListView(
                padding: EdgeInsets.only(
                  bottom: getMiniPlayerAwareBottomPadding(),
                ),
                children: [
                  // Downloads statistics card
                  _buildStatisticsCard(context, isDark),

                  // Download mode (original vs transcoded)
                  _buildDownloadModeCard(context, isDark),

                  // Download All section
                  _buildDownloadAllCard(context, isDark),

                  // Cache section
                  _buildCacheSection(context, isDark),

                  const SizedBox(height: 24),

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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cached_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 10),
                Text(
                  'Media Cache',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Cache size info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cacheSizeMB.toStringAsFixed(1)} MB',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      'of $_cacheLimitMB MB limit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Text(
                  '$_cachedSongCount songs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _cacheLimitMB > 0 ? (_cacheSizeMB / _cacheLimitMB).clamp(0.0, 1.0) : 0.0,
                minHeight: 8,
                backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
                valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : Colors.black),
              ),
            ),
            const SizedBox(height: 20),
            
            // Cache limit slider
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: _cacheLimitMB.toDouble(),
                      min: 100,
                      max: 2000,
                      divisions: 19,
                      label: '$_cacheLimitMB MB',
                      activeColor: isDark ? Colors.white : Colors.black,
                      inactiveColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
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
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Clear cache button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _cacheSizeMB > 0 ? _clearCache : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                label: const Text(
                  'Clear Media Cache',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                  foregroundColor: isDark ? Colors.white : Colors.black,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Cache info text
            Text(
              'Cached content is automatically managed when you stream songs. Clearing cache won\'t affect your downloads.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
                height: 1.4,
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
    }
  }

  Widget _buildDownloadAllCard(BuildContext context, bool isDark) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 10),
                Text(
                  'Quick Download',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // All Songs row
            _buildDownloadAllRow(
              context,
              isDark: isDark,
              icon: Icons.music_note_rounded,
              label: 'All Songs',
              downloadedCount: _downloadedSongCount,
              totalCount: _totalSongCount,
              countLabel: 'songs',
              isLoading: _isLoadingCounts,
              isDownloading: _isDownloadingAllSongs,
              onDownload: _downloadAllSongs,
            ),

            const SizedBox(height: 16),

            // All Albums row
            _buildDownloadAllRow(
              context,
              isDark: isDark,
              icon: Icons.album_rounded,
              label: 'All Albums',
              downloadedCount: _downloadedAlbumCount,
              totalCount: _totalAlbumCount,
              countLabel: 'albums',
              isLoading: _isLoadingCounts,
              isDownloading: _isDownloadingAllAlbums,
              onDownload: _downloadAllAlbums,
            ),

            const SizedBox(height: 16),

            // All Playlists row
            _buildDownloadAllRow(
              context,
              isDark: isDark,
              icon: Icons.playlist_play_rounded,
              label: 'All Playlists',
              downloadedCount: _downloadedPlaylistSongCount,
              totalCount: _totalPlaylistSongCount,
              countLabel: 'songs',
              isLoading: _isLoadingCounts,
              isDownloading: _isDownloadingAllPlaylists,
              onDownload: _downloadAllPlaylists,
            ),

            const SizedBox(height: 16),

            // Info text
            Text(
              'Downloads are optimized and processed in the background.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadAllRow(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String label,
    required int downloadedCount,
    required int totalCount,
    required String countLabel,
    required bool isLoading,
    required bool isDownloading,
    required VoidCallback onDownload,
  }) {
    final bool allDownloaded = downloadedCount >= totalCount && totalCount > 0;
    final bool hasItemsToDownload = totalCount > 0 && !allDownloaded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                if (isLoading)
                  Text(
                    'Loading library data...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[600] : Colors.grey[500],
                    ),
                  )
                else
                  Text(
                    allDownloaded
                        ? 'All matched $countLabel downloaded'
                        : '$downloadedCount / $totalCount $countLabel saved',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: allDownloaded
                          ? Colors.green[600]
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                      letterSpacing: 0.1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            height: 44,
            child: isDownloading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      allDownloaded ? Icons.check_circle_rounded : Icons.arrow_downward_rounded,
                      size: 24,
                      color: (isLoading || !hasItemsToDownload)
                          ? (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1))
                          : (isDark ? Colors.white : Colors.black),
                    ),
                    onPressed: (isLoading || !hasItemsToDownload) ? null : onDownload,
                    style: IconButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                      shape: const CircleBorder(),
                    ),
                    tooltip: allDownloaded ? 'Already downloaded' : 'Download $label',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(BuildContext context, bool isDark) {
    final stats = _downloadManager.getQueueStats();
    final sizeMB = _downloadManager.getTotalDownloadedSizeMB();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Offline Library',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
                if (stats.downloading > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${stats.downloading} active',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sizeMB.toStringAsFixed(1)} MB',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.completed} songs saved locally',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadModeCard(BuildContext context, bool isDark) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.speed_rounded,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fast Downloads (Original)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _downloadOriginal
                        ? 'Downloads bypass transcoding for maximum speed'
                        : 'Use transcoding to reduce download size',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _downloadOriginal,
              onChanged: (value) async {
                await _qualityService.setDownloadOriginal(value);
                if (mounted) {
                  setState(() {
                    _downloadOriginal = value;
                  });
                }
              },
              activeThumbColor: isDark ? Colors.white : Colors.black,
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
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[400] : Colors.grey[700],
            letterSpacing: 1.2,
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
          color: Colors.transparent,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Album artwork
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: CachedArtwork(
                            albumId: albumId,
                            artworkUrl: artworkUrl.isNotEmpty ? artworkUrl : null,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            fallbackIcon: Icons.album_rounded,
                            fallbackIconSize: 24,
                            sizeHint: ArtworkSizeHint.thumbnail,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
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
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              albumArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${songs.length} songs • ${_formatBytes(totalBytes)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete album button - Standardized modern circular button
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: const Color(0xFFFF4B4B).withOpacity(0.8),
                            size: 20,
                          ),
                          onPressed: () => _confirmDeleteAlbum(
                            context,
                            albumId,
                            albumName,
                            songs.length,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                            shape: const CircleBorder(),
                          ),
                          tooltip: 'Delete album',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Expand/collapse icon
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded songs list
              if (isExpanded)
                Container(
                  color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
            ),
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
          color: Colors.transparent,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // First song's artwork or fallback
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: firstSong != null
                              ? CachedArtwork(
                                  albumId: cacheId,
                                  artworkUrl: artworkUrl,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  fallbackIcon: Icons.music_note_rounded,
                                  fallbackIconSize: 24,
                                  sizeHint: ArtworkSizeHint.thumbnail,
                                )
                              : Container(
                                  color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                                    size: 24,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Singles info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Singles',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Songs without album',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${songs.length} songs • ${_formatBytes(totalBytes)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete all singles button - Standardized modern circular button
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: const Color(0xFFFF4B4B).withOpacity(0.8),
                            size: 20,
                          ),
                          onPressed: () => _confirmDeleteAlbum(
                            context,
                            null,
                            'Singles',
                            songs.length,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                            shape: const CircleBorder(),
                          ),
                          tooltip: 'Delete all singles',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Expand/collapse icon
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded songs list
              if (isExpanded)
                Container(
                  color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Song artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(10), // Standardized radius
                child: SizedBox(
                  width: 44, // Slightly larger for better detail
                  height: 44,
                  child: CachedArtwork(
                    albumId: cacheId,
                    artworkUrl: artworkUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.music_note_rounded,
                    fallbackIconSize: 20,
                    sizeHint: ArtworkSizeHint.thumbnail,
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              // Delete button - Standardized modern circular button
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: const Color(0xFFFF4B4B).withOpacity(0.8),
                    size: 16,
                  ),
                  onPressed: () => _cancelDownload(task.id),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                    shape: const CircleBorder(),
                  ),
                  tooltip: 'Remove song',
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 76.0, right: 16.0), // Aligned with artwork spacing
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? const Color(0xFF1A1A1A).withOpacity(0.5) : const Color(0xFFEEEEEE),
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
    }
  }

  Widget _buildDownloadItem(
    BuildContext context,
    DownloadTask task,
    bool isDark,
    bool isLast,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Boxed Status Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: _buildStatusIcon(task)),
                ),
                const SizedBox(width: 14),
                // Title and artist
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
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Progress bar or status text
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _currentProgress[task.id]?.progress ?? task.progress,
                  minHeight: 6,
                  backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
                  valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : Colors.black),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_currentProgress[task.id]?.percentage ?? task.getPercentage()}% • ${_formatBytes(_currentProgress[task.id]?.bytesDownloaded ?? task.bytesDownloaded)} / ${_formatBytes(_currentProgress[task.id]?.totalBytes ?? task.totalBytes)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  letterSpacing: 0.2,
                ),
              ),
            ] else if (task.status == DownloadStatus.completed) ...[
              const SizedBox(height: 12),
              Text(
                'Saved Locally • ${task.getFormattedTotalBytes()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ] else if (task.status == DownloadStatus.failed) ...[
              const SizedBox(height: 12),
              Text(
                task.errorMessage ?? 'Download failed',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF4B4B),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: _buildActionButtons(task),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(DownloadTask task) {
    final buttons = <Widget>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      minimumSize: const Size(0, 36),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
    );

    if (task.status == DownloadStatus.downloading) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _pauseDownload(task.id),
          icon: const Icon(Icons.pause_rounded, size: 14),
          label: const Text('PAUSE'),
          style: buttonStyle,
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('CANCEL'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.paused) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _resumeDownload(task.id),
          icon: const Icon(Icons.play_arrow_rounded, size: 14),
          label: const Text('RESUME'),
          style: buttonStyle,
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('CANCEL'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.failed && task.canRetry()) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _retryDownload(task.id),
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('RETRY'),
          style: buttonStyle,
        ),
      );
    } else if (task.status == DownloadStatus.completed) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.delete_outline_rounded, size: 14),
          label: const Text('REMOVE'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    } else if (task.status == DownloadStatus.pending) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _cancelDownload(task.id),
          icon: const Icon(Icons.close_rounded, size: 14),
          label: const Text('REMOVE'),
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFF4B4B)),
          ),
        ),
      );
    }

    return buttons;
  }

  Widget _buildStatusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_filled_rounded, size: 22, color: Color(0xFFFFB300));
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle_rounded, size: 22, color: Color(0xFF00C853));
      case DownloadStatus.failed:
        return const Icon(Icons.error_rounded, size: 22, color: Color(0xFFFF4B4B));
      case DownloadStatus.pending:
      case DownloadStatus.cancelled:
        return Icon(Icons.schedule_rounded, size: 22, color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[600] : Colors.grey[400]);
    }
  }
}
