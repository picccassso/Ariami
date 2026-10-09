import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/playback_manager.dart';
import 'playing_collection_builder.dart';
import 'playlist_artwork.dart';

class PlaylistListItem extends StatefulWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<String> albumIds;
  final bool isLikedSongs;
  final bool isImportedFromServer;
  final bool hasDownloadedSongs;
  final bool isOfflineCopy;
  final bool isPinned;
  final bool isSelectionMode;
  final bool isSelected;
  final String? sourceId;

  const PlaylistListItem({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onLongPress,
    this.albumIds = const [],
    this.isLikedSongs = false,
    this.isImportedFromServer = false,
    this.hasDownloadedSongs = false,
    this.isOfflineCopy = false,
    this.isPinned = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.sourceId,
  });

  @override
  State<PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends State<PlaylistListItem> {
  bool? _customImageExists;

  String get _sourceId =>
      widget.sourceId ?? PlaybackManager.playlistSource(widget.playlist.id);

  @override
  void initState() {
    super.initState();
    _checkCustomImage();
  }

  @override
  void didUpdateWidget(PlaylistListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.customImagePath != widget.playlist.customImagePath) {
      _checkCustomImage();
    }
  }

  Future<void> _checkCustomImage() async {
    if (widget.playlist.customImagePath != null) {
      final exists = await File(widget.playlist.customImagePath!).exists();
      if (mounted) {
        setState(() {
          _customImageExists = exists;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.isSelectionMode ? null : widget.onLongPress,
        borderRadius: BorderRadius.circular(0),
        child: Container(
          color: widget.isSelected
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (widget.isSelectionMode) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: widget.isSelected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: Theme.of(context).colorScheme.onPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                ],
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(0),
                        child: _buildPlaylistArt(),
                      ),
                      if (widget.hasDownloadedSongs)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: widget.isOfflineCopy
                                  ? Theme.of(context).colorScheme.secondary
                                  : Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  width: 2),
                            ),
                            child: Icon(
                              widget.isOfflineCopy
                                  ? Icons.cloud_off_rounded
                                  : Icons.download_done,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (widget.isPinned) ...[
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (widget.isImportedFromServer) ...[
                            Icon(
                              Icons.cloud_done_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: PlayingCollectionTitle(
                              sourceId: _sourceId,
                              text: widget.playlist.name,
                              enabled: !widget.isSelectionMode,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isOfflineCopy
                            ? '${widget.playlist.songCount} songs · Offline copy'
                            : '${widget.playlist.songCount} songs',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: widget.isOfflineCopy
                                  ? Theme.of(context).colorScheme.secondary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PlayingCollectionIndicator(
                  sourceId: _sourceId,
                  enabled: !widget.isSelectionMode,
                  leadingSpacing: 8,
                  trailingSpacing: 8,
                ),
                if (!widget.isSelectionMode)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistArt() => PlaylistArtwork(
        playlistName: widget.playlist.name,
        customImagePath: widget.playlist.customImagePath,
        customImageExists: _customImageExists == true,
        albumIds: widget.albumIds,
        isLikedSongs: widget.isLikedSongs,
        iconSize: 24,
        decodeWidth: 56,
      );
}
