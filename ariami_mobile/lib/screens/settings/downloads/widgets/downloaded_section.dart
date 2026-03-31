import 'package:flutter/material.dart';

import '../../../../models/download_task.dart';
import 'album_card.dart';
import 'singles_card.dart';

/// "Downloaded" header plus album / singles groups.
class DownloadedSection extends StatelessWidget {
  const DownloadedSection({
    super.key,
    required this.completedTasks,
    required this.sortedAlbumKeys,
    required this.groupedByAlbum,
    required this.expandedAlbums,
    required this.isDark,
    required this.onToggleAlbum,
    required this.onDeleteAlbumGroup,
    required this.onRemoveSong,
  });

  final List<DownloadTask> completedTasks;
  final List<String?> sortedAlbumKeys;
  final Map<String?, List<DownloadTask>> groupedByAlbum;
  final Set<String> expandedAlbums;
  final bool isDark;
  final void Function(String key) onToggleAlbum;
  final Future<void> Function(String? albumId, String albumName, int songCount)
      onDeleteAlbumGroup;
  final void Function(String taskId) onRemoveSong;

  @override
  Widget build(BuildContext context) {
    if (completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final widgets = <Widget>[
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
    ];

    for (var i = 0; i < sortedAlbumKeys.length; i++) {
      final albumId = sortedAlbumKeys[i];
      final songs = groupedByAlbum[albumId]!;
      final isLast = i == sortedAlbumKeys.length - 1;

      if (albumId == null) {
        widgets.add(
          SinglesCard(
            songs: songs,
            isDark: isDark,
            isLast: isLast,
            isExpanded: expandedAlbums.contains(SinglesCard.singlesKey),
            onToggleExpand: () => onToggleAlbum(SinglesCard.singlesKey),
            onDeleteSingles: () => onDeleteAlbumGroup(null, 'Singles', songs.length),
            onRemoveSong: onRemoveSong,
          ),
        );
      } else {
        widgets.add(
          AlbumCard(
            albumId: albumId,
            songs: songs,
            isDark: isDark,
            isLast: isLast,
            isExpanded: expandedAlbums.contains(albumId),
            onToggleExpand: () => onToggleAlbum(albumId),
            onDeleteAlbum: () {
              final name = songs.first.albumName ?? 'Unknown Album';
              onDeleteAlbumGroup(albumId, name, songs.length);
            },
            onRemoveSong: onRemoveSong,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}
