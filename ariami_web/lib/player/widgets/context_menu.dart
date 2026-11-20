import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'hidden_actions.dart';
import 'liked_song_button.dart';
import 'playback_helpers.dart';
import 'playlist_actions.dart';
import 'playlists_menu.dart';
import 'queue_intent.dart';

enum _TrackMenuAction {
  playNext,
  playNowKeepQueue,
  like,
  queue,
  playlists,
  download,
  album,
  moveUp,
  moveDown,
  remove
}

enum _CollectionMenuAction {
  play,
  playNext,
  queue,
  download,
  pin,
  hide,
  editDetails,
  delete,
}

Future<void> showTrackContextMenu(
  BuildContext context,
  Offset position,
  Track track, {
  bool showGoToAlbum = true,
  VoidCallback? onOpenAlbum,
  VoidCallback? onMoveUp,
  VoidCallback? onMoveDown,
  VoidCallback? onRemove,
}) async {
  final hasReorder = onMoveUp != null || onMoveDown != null || onRemove != null;
  final library = context.read<LibraryController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Downloads only exist when playing from a remote server — when this
  // computer hosts the library, the files are already on its disk.
  final canDownload = !context.read<ConnectionController>().isLocalServer &&
      (maybeReadProvider<PlayerDownloadsBridge?>(context) ??
              maybeReadProvider<PlayerDownloadsBridge>(context)) !=
          null;
  final action = await showPlayerContextMenu<_TrackMenuAction>(
    context,
    position,
    [
      const PopupMenuItem(
        value: _TrackMenuAction.playNext,
        child: Text('Play next'),
      ),
      const PopupMenuItem(
        value: _TrackMenuAction.playNowKeepQueue,
        child: Text('Play now, keep queue'),
      ),
      PopupMenuItem(
        value: _TrackMenuAction.like,
        child:
            Text(library.isLikedSong(track.id) ? 'Dislike song' : 'Like song'),
      ),
      const PopupMenuItem(
        value: _TrackMenuAction.queue,
        child: Text('Add to end of queue'),
      ),
      const PopupMenuItem(
        value: _TrackMenuAction.playlists,
        child: Text('Playlists…'),
      ),
      if (canDownload)
        const PopupMenuItem(
          value: _TrackMenuAction.download,
          child: Text('Download'),
        ),
      if (showGoToAlbum && track.albumId != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _TrackMenuAction.album,
          child: Text('Go to album'),
        ),
      ],
      if (hasReorder) ...[
        const PopupMenuDivider(),
        if (onMoveUp != null)
          const PopupMenuItem(
            value: _TrackMenuAction.moveUp,
            child: Text('Move up'),
          ),
        if (onMoveDown != null)
          const PopupMenuItem(
            value: _TrackMenuAction.moveDown,
            child: Text('Move down'),
          ),
        if (onRemove != null)
          const PopupMenuItem(
            value: _TrackMenuAction.remove,
            child: Text('Remove from playlist'),
          ),
      ],
    ],
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case _TrackMenuAction.playNext:
      final nextAt = context.read<AudioController>().playNext(<Track>[track]);
      showQueueAdditionToast(
        context,
        message: 'Playing next',
        firstPosition: nextAt,
      );
      break;
    case _TrackMenuAction.playNowKeepQueue:
      final playedAt =
          context.read<AudioController>().playNowKeepingQueue(track);
      showQueueAdditionToast(
        context,
        message: 'Playing now',
        firstPosition: playedAt,
      );
      break;
    case _TrackMenuAction.like:
      await toggleLikeWithUndo(library, messenger, track);
      break;
    case _TrackMenuAction.queue:
      final queuedAt =
          context.read<AudioController>().addToQueue(<Track>[track]);
      showQueueAdditionToast(
        context,
        message: 'Added to end of queue',
        firstPosition: queuedAt,
      );
      break;
    case _TrackMenuAction.playlists:
      await showPlaylistsMenu(context, position, <Track>[track]);
      break;
    case _TrackMenuAction.download:
      await enqueueTrackDownloads(context, <Track>[track]);
      break;
    case _TrackMenuAction.album:
      if (onOpenAlbum != null) {
        onOpenAlbum();
      } else {
        context.read<PlayerNavigator>().openAlbum(track.albumId!);
      }
      break;
    case _TrackMenuAction.moveUp:
      onMoveUp?.call();
      break;
    case _TrackMenuAction.moveDown:
      onMoveDown?.call();
      break;
    case _TrackMenuAction.remove:
      onRemove?.call();
      break;
  }
}

/// Right-click menu for one library collection: an album, a playlist, or an
/// artist (whose "collection" is every track credited to them).
Future<void> showCollectionContextMenu(
  BuildContext context,
  Offset position, {
  Album? album,
  PlaylistSummary? playlist,
  String? artist,
}) async {
  assert(
    [album, playlist, artist].whereType<Object>().length == 1,
    'exactly one of album, playlist or artist',
  );
  final library = context.read<LibraryController>();
  // Client-created playlists can't be pinned: the server resolves playlist pins
  // against its own catalog, so a created-playlist pin would show as
  // unavailable. Artists aren't a pinnable type at all.
  final canPin = artist == null &&
      (album != null || !library.isCreatedPlaylist(playlist!.id));
  final isPinned = album != null
      ? library.isAlbumPinned(album.id)
      : playlist != null && library.isPlaylistPinned(playlist.id);
  final canDownload = !context.read<ConnectionController>().isLocalServer &&
      (maybeReadProvider<PlayerDownloadsBridge?>(context) ??
              maybeReadProvider<PlayerDownloadsBridge>(context)) !=
          null;
  final action = await showPlayerContextMenu<_CollectionMenuAction>(
    context,
    position,
    [
      const PopupMenuItem(
        value: _CollectionMenuAction.play,
        child: Text('Play'),
      ),
      const PopupMenuItem(
        value: _CollectionMenuAction.playNext,
        child: Text('Play next'),
      ),
      const PopupMenuItem(
        value: _CollectionMenuAction.queue,
        child: Text('Add to end of queue'),
      ),
      if (canDownload)
        const PopupMenuItem(
          value: _CollectionMenuAction.download,
          child: Text('Download'),
        ),
      if (canPin) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _CollectionMenuAction.pin,
          child: Text(isPinned ? 'Unpin' : 'Pin'),
        ),
      ],
      if (!canPin) const PopupMenuDivider(),
      const PopupMenuItem(
        value: _CollectionMenuAction.hide,
        child: Text('Remove from my library'),
      ),
      if (playlist != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CollectionMenuAction.editDetails,
          child: Text('Edit details'),
        ),
        const PopupMenuItem(
          value: _CollectionMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    ],
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case _CollectionMenuAction.play:
      if (album != null) {
        await playAlbum(context, album.id);
      } else if (playlist != null) {
        await playPlaylist(context, playlist);
      } else {
        await playArtist(context, artist!);
      }
      break;
    case _CollectionMenuAction.playNext:
      final tracks = await _collectionTracks(context, album, playlist, artist);
      if (!context.mounted || tracks == null) return;
      final nextAt = context.read<AudioController>().playNext(tracks);
      showQueueAdditionToast(
        context,
        message: 'Playing next',
        firstPosition: nextAt,
        count: tracks.length,
      );
      break;
    case _CollectionMenuAction.queue:
      final tracks = await _collectionTracks(context, album, playlist, artist);
      if (!context.mounted || tracks == null) return;
      final queuedAt = context.read<AudioController>().addToQueue(tracks);
      showQueueAdditionToast(
        context,
        message: 'Added to end of queue',
        firstPosition: queuedAt,
        count: tracks.length,
      );
      break;
    case _CollectionMenuAction.download:
      final tracks = await _collectionTracks(context, album, playlist, artist);
      if (!context.mounted || tracks == null) return;
      await enqueueTrackDownloads(context, tracks);
      break;
    case _CollectionMenuAction.pin:
      if (album != null) {
        await library.toggleAlbumPin(album.id);
      } else {
        await library.togglePlaylistPin(playlist!.id);
      }
      if (!context.mounted) return;
      showQueueToast(context, isPinned ? 'Unpinned' : 'Pinned');
      break;
    case _CollectionMenuAction.hide:
      await hideCollections(context, [
        if (album != null)
          albumHideTarget(album.id)
        else if (playlist != null)
          playlistHideTarget(playlist.id)
        else
          artistHideTarget(artist!),
      ]);
      break;
    case _CollectionMenuAction.editDetails:
      await showEditPlaylistDetailsDialog(context, playlist!);
      break;
    case _CollectionMenuAction.delete:
      await confirmDeletePlaylist(context, playlist!);
      break;
  }
}

Future<List<Track>?> _collectionTracks(
  BuildContext context,
  Album? album,
  PlaylistSummary? playlist,
  String? artist,
) async {
  final library = context.read<LibraryController>();
  try {
    if (album != null) {
      final detail = await library.albumDetail(album.id);
      return detail.tracks;
    }
    if (artist != null) return library.artistTracks(artist);
    return library.playlistTracks(playlist!);
  } catch (e) {
    if (!context.mounted) return null;
    showQueueToast(context, 'Could not load tracks: $e');
    return null;
  }
}

/// Screen position of [context]'s widget, used to anchor a popup menu opened
/// from a button rather than from a right-click.
Offset menuAnchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return Offset.zero;
  return box.localToGlobal(box.size.centerLeft(Offset.zero));
}

/// Shows a popup menu at the pointer with the player's shared menu styling.
///
/// The pointer's [globalPosition] is in window coordinates, but [showMenu]
/// positions within the overlay's space — and the overlay lives inside the
/// interface-zoom transform (`_ScaledApp`), so at any zoom other than 100%
/// the two disagree and the menu opens away from the cursor.
/// [RenderBox.globalToLocal] inverts that transform.
Future<T?> showPlayerContextMenu<T>(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<T>> items, {
  BoxConstraints? constraints,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(local, local),
      Offset.zero & overlay.size,
    ),
    color: context.colors.popover,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: context.colors.border),
    ),
    items: items,
    constraints: constraints,
  );
}

