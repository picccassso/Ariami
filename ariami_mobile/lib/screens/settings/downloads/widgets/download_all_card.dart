import 'package:flutter/material.dart';

class DownloadAllCard extends StatelessWidget {
  const DownloadAllCard({
    super.key,
    required this.isDark,
    required this.downloadedSongCount,
    required this.totalSongCount,
    required this.downloadedAlbumCount,
    required this.totalAlbumCount,
    required this.downloadedPlaylistSongCount,
    required this.totalPlaylistSongCount,
    required this.isLoadingCounts,
    required this.isDownloadingAllSongs,
    required this.isDownloadingAllAlbums,
    required this.isDownloadingAllPlaylists,
    required this.onDownloadAllSongs,
    required this.onDownloadAllAlbums,
    required this.onDownloadAllPlaylists,
  });

  final bool isDark;
  final int downloadedSongCount;
  final int totalSongCount;
  final int downloadedAlbumCount;
  final int totalAlbumCount;
  final int downloadedPlaylistSongCount;
  final int totalPlaylistSongCount;
  final bool isLoadingCounts;
  final bool isDownloadingAllSongs;
  final bool isDownloadingAllAlbums;
  final bool isDownloadingAllPlaylists;
  final VoidCallback onDownloadAllSongs;
  final VoidCallback onDownloadAllAlbums;
  final VoidCallback onDownloadAllPlaylists;

  @override
  Widget build(BuildContext context) {
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
            DownloadAllRow(
              isDark: isDark,
              icon: Icons.music_note_rounded,
              label: 'All Songs',
              downloadedCount: downloadedSongCount,
              totalCount: totalSongCount,
              countLabel: 'songs',
              isLoading: isLoadingCounts,
              isDownloading: isDownloadingAllSongs,
              onDownload: onDownloadAllSongs,
            ),
            const SizedBox(height: 16),
            DownloadAllRow(
              isDark: isDark,
              icon: Icons.album_rounded,
              label: 'All Albums',
              downloadedCount: downloadedAlbumCount,
              totalCount: totalAlbumCount,
              countLabel: 'albums',
              isLoading: isLoadingCounts,
              isDownloading: isDownloadingAllAlbums,
              onDownload: onDownloadAllAlbums,
            ),
            const SizedBox(height: 16),
            DownloadAllRow(
              isDark: isDark,
              icon: Icons.playlist_play_rounded,
              label: 'All Playlists',
              downloadedCount: downloadedPlaylistSongCount,
              totalCount: totalPlaylistSongCount,
              countLabel: 'songs',
              isLoading: isLoadingCounts,
              isDownloading: isDownloadingAllPlaylists,
              onDownload: onDownloadAllPlaylists,
            ),
            const SizedBox(height: 16),
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
}

class DownloadAllRow extends StatelessWidget {
  const DownloadAllRow({
    super.key,
    required this.isDark,
    required this.icon,
    required this.label,
    required this.downloadedCount,
    required this.totalCount,
    required this.countLabel,
    required this.isLoading,
    required this.isDownloading,
    required this.onDownload,
  });

  final bool isDark;
  final IconData icon;
  final String label;
  final int downloadedCount;
  final int totalCount;
  final String countLabel;
  final bool isLoading;
  final bool isDownloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
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
                      allDownloaded
                          ? Icons.check_circle_rounded
                          : Icons.arrow_downward_rounded,
                      size: 24,
                      color: (isLoading || !hasItemsToDownload)
                          ? (isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1))
                          : (isDark ? Colors.white : Colors.black),
                    ),
                    onPressed:
                        (isLoading || !hasItemsToDownload) ? null : onDownload,
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFF5F5F5),
                      shape: const CircleBorder(),
                    ),
                    tooltip: allDownloaded
                        ? 'Already downloaded'
                        : 'Download $label',
                  ),
          ),
        ],
      ),
    );
  }
}
