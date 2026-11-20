import 'dart:async';

import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/library_controller.dart';
import '../theme/player_theme.dart';
import 'queue_intent.dart';

/// Likes or dislikes [track] from a menu, offering Undo. The heart button
/// toggles in place instead: clicking it again is its own undo.
Future<void> toggleLikeWithUndo(
  LibraryController library,
  ScaffoldMessengerState? messenger,
  Track track,
) async {
  final wasLiked = library.isLikedSong(track.id);
  final before = library.playlistSongIds(likedSongsPlaylistId);
  await library.toggleLikedSong(track);
  showUndoToast(
    messenger,
    wasLiked ? 'Removed from Liked Songs' : 'Added to Liked Songs',
    onUndo: () => unawaited(
      before == null
          ? library.toggleLikedSong(track)
          : library.restorePlaylistSongs(likedSongsPlaylistId, before),
    ),
  );
}

class LikedSongButton extends StatefulWidget {
  const LikedSongButton({
    super.key,
    required this.track,
    this.iconSize = 22,
  });

  final Track track;
  final double iconSize;

  @override
  State<LikedSongButton> createState() => _LikedSongButtonState();
}

class _LikedSongButtonState extends State<LikedSongButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<LibraryController>().toggleLikedSong(widget.track);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LibraryController, bool>(
      (library) => library.isLikedSong(widget.track.id),
    );
    final accent = Theme.of(context).colorScheme.secondary;
    return IconButton(
      key: ValueKey('like-${widget.track.id}'),
      tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _toggle,
      color: liked ? accent : context.colors.textSecondary,
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: widget.iconSize,
      ),
    );
  }
}
