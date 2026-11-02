import 'dart:async';
import 'package:flutter/material.dart';
import '../common/mini_player_aware_bottom_sheet.dart';
import '../../models/song.dart';
import 'queue_display_order.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ariami_core/utils/format.dart';
import '../../utils/artwork_url.dart';
import '../../services/offline/offline_playback_service.dart';
import '../common/cached_artwork.dart';
import '../common/track_badge.dart';
import '../common/playing_bars.dart';
import '../player/progress_fill.dart';
import '../../services/playback_manager.dart';
import '../../utils/constants.dart';

class ReorderableQueueList extends StatefulWidget {
  final List<Song> songs;
  final int currentIndex;
  final Function(int oldIndex, int newIndex) onReorder;
  final Function(int index)? onTap;
  final Function(int index)? onRemove;

  const ReorderableQueueList({
    super.key,
    required this.songs,
    required this.currentIndex,
    required this.onReorder,
    this.onTap,
    this.onRemove,
  });

  @override
  State<ReorderableQueueList> createState() => _ReorderableQueueListState();
}

class _ReorderableQueueListState extends State<ReorderableQueueList> {
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();

  /// Map of song ID -> availability (true = available offline or online)
  Map<String, bool> _availabilityMap = {};
  String? _availabilitySignature;
  int _availabilityGeneration = 0;

  StreamSubscription<OfflineMode>? _offlineStateSubscription;

  @override
  void initState() {
    super.initState();
    _checkSongAvailability();

    _offlineStateSubscription = _offlineService.offlineModeStream.listen((_) {
      _checkSongAvailability(force: true);
    });
  }

  @override
  void didUpdateWidget(ReorderableQueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // PlaybackQueue.songs returns a fresh list wrapper on each rebuild, so
    // compare the actual availability inputs instead of list identity.
    if (_availabilitySignatureFor(oldWidget.songs) !=
        _availabilitySignatureFor(widget.songs)) {
      _checkSongAvailability();
    }
  }

  @override
  void dispose() {
    _offlineStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkSongAvailability({bool force = false}) async {
    final signature = _availabilitySignatureFor(widget.songs);
    if (!force &&
        _availabilitySignature == signature &&
        _availabilityMap.isNotEmpty) {
      return;
    }

    final generation = ++_availabilityGeneration;
    final newAvailability = <String, bool>{};
    final isOffline = _offlineService.isOffline;

    for (final song in widget.songs) {
      if (isOffline) {
        final isAvailable =
            await _offlineService.isSongAvailableOffline(song.id);
        newAvailability[song.id] = isAvailable;
      } else {
        newAvailability[song.id] = true;
      }
    }

    if (mounted && generation == _availabilityGeneration) {
      setState(() {
        _availabilityMap = newAvailability;
        _availabilitySignature = signature;
      });
    }
  }

  String _availabilitySignatureFor(List<Song> songs) {
    final ids = songs.map((song) => song.id).toSet().toList()..sort();
    return ids.join('\u{1f}');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.listMusic,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Queue is empty',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    final displayedSongs = QueueDisplayOrder.songsInDisplayOrder(
      widget.songs,
      widget.currentIndex,
    );
    final currentSong = displayedSongs.first;
    final upcomingSongs = displayedSongs.skip(1).toList();
    final currentRealIndex = QueueDisplayOrder.displayIndexToReal(
      0,
      widget.songs.length,
      widget.currentIndex,
    );
    final currentRowKey = ObjectKey(currentSong);

    return Column(
      children: [
        QueueItem(
          key: currentRowKey,
          rowKey: currentRowKey,
          song: currentSong,
          index: 0,
          isCurrentlyPlaying: true,
          isAvailable: _availabilityMap[currentSong.id] ?? true,
          onTap: widget.onTap != null
              ? () => widget.onTap!(currentRealIndex)
              : null,
          onRemove: widget.onRemove != null
              ? () => widget.onRemove!(currentRealIndex)
              : null,
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerScrollBottomPadding(context),
            ),
            itemCount: upcomingSongs.length,
            onReorder: (oldUpcomingIndex, newUpcomingIndex) {
              widget.onReorder(oldUpcomingIndex + 1, newUpcomingIndex + 1);
            },
            itemBuilder: (context, upcomingIndex) {
              final displayIndex = upcomingIndex + 1;
              final song = upcomingSongs[upcomingIndex];
              final realIndex = QueueDisplayOrder.displayIndexToReal(
                displayIndex,
                widget.songs.length,
                widget.currentIndex,
              );
              // Default to available if not yet checked (avoids flicker)
              final isAvailable = _availabilityMap[song.id] ?? true;
              final rowKey = ObjectKey(song);

              return QueueItem(
                key: rowKey,
                rowKey: rowKey,
                song: song,
                index: displayIndex,
                isCurrentlyPlaying: false,
                isAvailable: isAvailable,
                onTap: widget.onTap != null
                    ? () => widget.onTap!(realIndex)
                    : null,
                onRemove: widget.onRemove != null
                    ? () => widget.onRemove!(realIndex)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class QueueItem extends StatelessWidget {
  final Key rowKey;
  final Song song;
  final int index;
  final bool isCurrentlyPlaying;
  final bool isAvailable;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const QueueItem({
    super.key,
    required this.rowKey,
    required this.song,
    required this.index,
    required this.isCurrentlyPlaying,
    this.isAvailable = true,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final opacity = isAvailable ? 1.0 : 0.4;

    return Dismissible(
      key: rowKey,
      direction: onRemove != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      // Require a deliberate 60% drag (default is 40%) so a stray horizontal
      // flick while scrolling the queue doesn't remove the song.
      dismissThresholds: const {DismissDirection.endToStart: 0.6},
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colors.surfaceHigh,
        child: Icon(LucideIcons.trash2, color: colors.textSecondary, size: 24),
      ),
      onDismissed: (_) => onRemove?.call(),
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            // Up next starts with the playing song, its progress sweeping
            // across it, as on Premium Desktop.
            Positioned.fill(
              child: isCurrentlyPlaying
                  ? ProgressFill(fill: colors.fill)
                  : const SizedBox.shrink(),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isAvailable ? onTap : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Center(child: _buildNumber(context)),
                      ),
                      const SizedBox(width: 8),
                      _buildLeading(context),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    song.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TrackBadge(
                                  hasLyrics: song.hasLyrics,
                                  isInstrumental: song.isInstrumental,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatDurationMinSec(song.duration),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                          fontFeatures: AppTheme.tabular,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildDragHandle(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The row's place in Up next; the playing song shows playing bars.
  Widget _buildNumber(BuildContext context) {
    final colors = context.colors;
    if (!isCurrentlyPlaying) {
      return Text(
        '$index',
        style: TextStyle(
          fontSize: 13,
          color: colors.textSecondary,
          fontFeatures: AppTheme.tabular,
        ),
      );
    }
    final playback = PlaybackManager();
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => PlayingBars(
        playing: playback.isPlaying,
        color: colors.textPrimary,
        size: 14,
      ),
    );
  }

  Widget _buildDragHandle(BuildContext context) {
    final color = context.colors.textSecondary;
    if (isCurrentlyPlaying || !isAvailable) {
      return Icon(
        LucideIcons.gripHorizontal,
        color: color.withValues(alpha: 0.3),
        size: 20,
      );
    }

    return ReorderableDragStartListener(
      index: index,
      child: Icon(LucideIcons.gripHorizontal, color: color, size: 20),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final artwork = resolveSongArtwork(songId: song.id, albumId: song.albumId);
    return CachedArtwork(
      albumId: artwork.cacheId,
      artworkUrl: artwork.url,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(AppTheme.coverRadius),
      fallback: Container(
        width: 44,
        height: 44,
        color: context.colors.surfaceHigh,
        child: Icon(
          LucideIcons.music,
          color: context.colors.textSecondary,
          size: 22,
        ),
      ),
      fallbackIcon: LucideIcons.music,
      fallbackIconSize: 22,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }
}
