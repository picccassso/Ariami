import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../../../services/api/connection_service.dart';
import '../utils/playlist_helpers.dart';
import 'album_art_with_badge.dart';

/// Normal song list item with dismissible action to remove
class SongListItem extends StatefulWidget {
  /// The song to display
  final SongModel song;

  /// Index in the list
  final int index;

  /// Whether the song is available for playback
  final bool isAvailable;

  /// Whether the song is downloaded
  final bool isDownloaded;

  /// Connection service for artwork
  final ConnectionService connectionService;

  /// Callback when song is tapped
  final VoidCallback? onTap;

  /// Callback when song is dismissed/removed
  final VoidCallback? onRemove;

  const SongListItem({
    super.key,
    required this.song,
    required this.index,
    required this.isAvailable,
    required this.isDownloaded,
    required this.connectionService,
    this.onTap,
    this.onRemove,
  });

  @override
  State<SongListItem> createState() => _SongListItemState();
}

class _SongListItemState extends State<SongListItem> {
  static const double _kSwipeEdgeGuard = 24.0;
  static const double _kRemoveDismissThreshold = 0.6;
  bool _dismissSwipeArmed = true;

  void _armDismissSwipe(PointerDownEvent event, double itemWidth) {
    final startX = event.localPosition.dx;
    final isInsideSafeZone =
        startX >= _kSwipeEdgeGuard && startX <= itemWidth - _kSwipeEdgeGuard;

    if (_dismissSwipeArmed != isInsideSafeZone) {
      setState(() {
        _dismissSwipeArmed = isInsideSafeZone;
      });
    }
  }

  void _resetDismissSwipe() {
    if (_dismissSwipeArmed) {
      return;
    }
    setState(() {
      _dismissSwipeArmed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.isAvailable ? 1.0 : 0.4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth;

        return Opacity(
          opacity: opacity,
          child: Listener(
            onPointerDown: (event) => _armDismissSwipe(event, itemWidth),
            onPointerUp: (_) => _resetDismissSwipe(),
            onPointerCancel: (_) => _resetDismissSwipe(),
            child: Dismissible(
              key: ValueKey('dismiss_${widget.song.id}'),
              direction: widget.onRemove != null && _dismissSwipeArmed
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              dismissThresholds: const <DismissDirection, double>{
                DismissDirection.endToStart: _kRemoveDismissThreshold,
              },
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return widget.onRemove != null &&
                    _dismissSwipeArmed &&
                    direction == DismissDirection.endToStart;
              },
              onDismissed: (_) => widget.onRemove?.call(),
              child: ListTile(
                leading: AlbumArtWithBadge(
                  song: widget.song,
                  isDownloaded: widget.isDownloaded,
                  connectionService: widget.connectionService,
                ),
                title: Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isAvailable ? null : Colors.grey,
                  ),
                ),
                subtitle: Text(
                  widget.song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                trailing: Text(
                  formatDuration(widget.song.duration),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: widget.isAvailable ? widget.onTap : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
