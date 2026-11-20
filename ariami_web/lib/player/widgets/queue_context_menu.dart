import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import 'context_menu.dart';
import 'liked_song_button.dart';
import 'playback_helpers.dart';
import 'playlists_menu.dart';
import 'queue_remove_button.dart';

enum _QueueMenuAction {
  like,
  playlists,
  download,
  album,
  remove,
}

/// Right-click menu for rows of the upcoming queue.
///
/// Reordering is drag-only, so this menu carries none of it: what is left are
/// the verbs that say something about the songs themselves, plus removal.
/// [upcomingIndices] are the rows' positions in [AudioController.upcoming], in
/// queue order and parallel to [tracks], and carry a whole multi-selection when
/// one is active.
Future<void> showQueueContextMenu(
  BuildContext context,
  Offset position, {
  required List<Track> tracks,
  required List<int> upcomingIndices,
}) async {
  if (tracks.isEmpty || tracks.length != upcomingIndices.length) return;
  final single = tracks.length == 1 ? tracks.first : null;
  // Held across the menu: the removal below must land even if the row the menu
  // was opened from has since been rebuilt out from under it.
  final audio = context.read<AudioController>();
  final library = context.read<LibraryController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Downloads only exist when playing from a remote server — when this
  // computer hosts the library, the files are already on its disk.
  final canDownload = !context.read<ConnectionController>().isLocalServer &&
      (maybeReadProvider<PlayerDownloadsBridge?>(context) ??
              maybeReadProvider<PlayerDownloadsBridge>(context)) !=
          null;

  final action = await showPlayerContextMenu<_QueueMenuAction>(
    context,
    position,
    [
      if (single != null)
        PopupMenuItem(
          value: _QueueMenuAction.like,
          child: Text(
            library.isLikedSong(single.id) ? 'Dislike song' : 'Like song',
          ),
        ),
      const PopupMenuItem(
        value: _QueueMenuAction.playlists,
        child: Text('Playlists…'),
      ),
      if (canDownload)
        const PopupMenuItem(
          value: _QueueMenuAction.download,
          child: Text('Download'),
        ),
      if (single?.albumId != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _QueueMenuAction.album,
          child: Text('Go to album'),
        ),
      ],
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: _QueueMenuAction.remove,
        child: Text('Remove from queue'),
      ),
    ],
  );
  if (action == null) return;

  switch (action) {
    case _QueueMenuAction.like:
      await toggleLikeWithUndo(library, messenger, single!);
      break;
    case _QueueMenuAction.playlists:
      if (!context.mounted) return;
      await showPlaylistsMenu(context, position, tracks);
      break;
    case _QueueMenuAction.download:
      if (!context.mounted) return;
      await enqueueTrackDownloads(context, tracks);
      break;
    case _QueueMenuAction.album:
      if (!context.mounted) return;
      context.read<PlayerNavigator>().openAlbum(single!.albumId!);
      break;
    case _QueueMenuAction.remove:
      removeUpcomingWithUndo(audio, messenger, upcomingIndices, tracks);
      break;
  }
}
