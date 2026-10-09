import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/playback_manager.dart';
import '../../utils/constants.dart';
import 'playing_collection_builder.dart';
import 'playlist_artwork.dart';

class PlaylistCard extends StatefulWidget {
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

  const PlaylistCard({
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
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool? _customImageExists;

  String get _sourceId =>
      widget.sourceId ?? PlaybackManager.playlistSource(widget.playlist.id);

  @override
  void initState() {
    super.initState();
    _checkCustomImage();
  }

  @override
  void didUpdateWidget(PlaylistCard oldWidget) {
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
    } else {
      if (mounted && _customImageExists != null) {
        setState(() {
          _customImageExists = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.isSelectionMode ? null : widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: _buildPlaylistArt(),
                  ),
                ),
                if (widget.isSelected)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Container(
                        color: Colors.black26,
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: PlayingCollectionIndicator(
                    sourceId: _sourceId,
                    enabled: !widget.isSelectionMode,
                    size: 16,
                    artworkBadge: true,
                  ),
                ),
                if (widget.hasDownloadedSongs && !widget.isSelectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: widget.isOfflineCopy
                            ? Theme.of(context).colorScheme.secondary
                            : Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          )
                        ],
                      ),
                      child: Icon(
                        widget.isOfflineCopy
                            ? Icons.cloud_off_rounded
                            : Icons.download_done,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (widget.isPinned && !widget.isSelectionMode)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.push_pin,
                        size: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                if (widget.isSelectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
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
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    letterSpacing: -0.2,
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
                          fontSize: 12,
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
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistArt() => PlaylistArtwork(
        playlistName: widget.playlist.name,
        customImagePath: widget.playlist.customImagePath,
        customImageExists: _customImageExists == true,
        albumIds: widget.albumIds,
        isLikedSongs: widget.isLikedSongs,
        iconSize: 48,
      );
}

class CreatePlaylistCard extends StatelessWidget {
  final VoidCallback onTap;

  const CreatePlaylistCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              'Create Playlist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportFromServerCard extends StatelessWidget {
  final int serverPlaylistCount;
  final VoidCallback onTap;

  const ImportFromServerCard({
    super.key,
    required this.serverPlaylistCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.secondary,
                    Theme.of(context).colorScheme.primary,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_download_rounded,
                      size: 40, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$serverPlaylistCount',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import from Server',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$serverPlaylistCount new available',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: Theme.of(context)
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
        ],
      ),
    );
  }
}
