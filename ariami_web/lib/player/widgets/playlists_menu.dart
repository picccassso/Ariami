import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../theme/player_theme.dart';
import 'context_menu.dart';
import 'playlist_actions.dart';
import 'playlist_artwork.dart';
import 'queue_intent.dart';

const String _newPlaylistValue = ' __new_playlist__';

/// Checklist of every playlist for one or more tracks: a tick means the
/// playlist holds them all, a dash that it holds some. Clicking a row adds or
/// removes the tracks on the spot and keeps the menu open, so several
/// playlists can be changed in one visit.
///
/// Returns whether anything changed, so a caller can tell a dismissed menu
/// from a real edit.
Future<bool> showPlaylistsMenu(
  BuildContext context,
  Offset position,
  List<Track> tracks,
) async {
  final library = context.read<LibraryController>();
  final connection = context.read<ConnectionController>();
  final ids = <String>[for (final track in tracks) track.id];
  var changed = false;

  // Playlists already holding any of the tracks lead, like Spotify's
  // "Saved in". The split is fixed at open so rows don't jump as they toggle.
  final saved = <PlaylistSummary>[];
  final others = <PlaylistSummary>[];
  for (final playlist in library.playlists) {
    final held = playlist.songIds.toSet();
    (ids.any(held.contains) ? saved : others).add(playlist);
  }

  PopupMenuEntry<String> header(String label) => PopupMenuItem<String>(
        enabled: false,
        height: 32,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      );
  PopupMenuEntry<String> row(PlaylistSummary playlist) => _PlaylistToggleEntry(
        library: library,
        connection: connection,
        playlist: playlist,
        songIds: ids,
        onChanged: () => changed = true,
      );

  final selected = await showPlayerContextMenu<String>(
    context,
    position,
    [
      PopupMenuItem<String>(
        value: _newPlaylistValue,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: context.colors.border),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 18,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            const Text('New playlist…'),
          ],
        ),
      ),
      if (saved.isNotEmpty) ...[
        const PopupMenuDivider(),
        header('Saved in'),
        for (final playlist in saved) row(playlist),
      ],
      if (others.isNotEmpty) ...[
        const PopupMenuDivider(),
        if (saved.isNotEmpty) header('Other playlists'),
        for (final playlist in others) row(playlist),
      ],
    ],
    constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
  );
  if (!context.mounted || selected != _newPlaylistValue) return changed;

  final id = await showCreatePlaylistDialog(context, initialSongIds: ids);
  if (!context.mounted || id == null) return changed;
  final name = library.playlists
      .firstWhere((p) => p.id == id,
          orElse: () => const PlaylistSummary(id: '', name: 'playlist'))
      .name;
  final count = ids.length == 1 ? '1 song' : '${ids.length} songs';
  showQueueToast(context, '$count added to "$name"');
  return true;
}

/// One checkable playlist row. Unlike a [PopupMenuItem], a click toggles the
/// tracks' membership in place instead of closing the menu.
class _PlaylistToggleEntry extends PopupMenuEntry<String> {
  const _PlaylistToggleEntry({
    required this.library,
    required this.connection,
    required this.playlist,
    required this.songIds,
    required this.onChanged,
  });

  // Menu entries are built inside the overlay route, above the player's
  // providers, so the controllers are passed in rather than read.
  final LibraryController library;
  final ConnectionController connection;

  /// The playlist as it was when the menu opened; membership is re-read live.
  final PlaylistSummary playlist;
  final List<String> songIds;
  final VoidCallback onChanged;

  @override
  double get height => 52;

  @override
  bool represents(String? value) => false;

  @override
  State<_PlaylistToggleEntry> createState() => _PlaylistToggleEntryState();
}

class _PlaylistToggleEntryState extends State<_PlaylistToggleEntry> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        // An emptied Liked Songs leaves the list; it then just holds nothing.
        final live = widget.library.playlists
                .where((p) => p.id == widget.playlist.id)
                .firstOrNull ??
            widget.playlist.copyWith(songIds: const <String>[], songCount: 0);
        final held = live.songIds.toSet();
        final count = widget.songIds.where(held.contains).length;
        final holdsAll = count == widget.songIds.length;

        void toggle() {
          widget.onChanged();
          if (holdsAll) {
            widget.library.removeTracksFromPlaylist(live.id, widget.songIds);
          } else {
            widget.library.addTracksToPlaylist(live.id, widget.songIds);
          }
        }

        return InkWell(
          onTap: toggle,
          child: SizedBox(
            height: widget.height,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  // Re-exposed for the artwork, which reads both controllers.
                  MultiProvider(
                    providers: [
                      ChangeNotifierProvider.value(value: widget.library),
                      ChangeNotifierProvider.value(value: widget.connection),
                    ],
                    child: PlaylistArtwork(
                      playlist: live,
                      size: 36,
                      borderRadius: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          live.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${live.songCount} '
                          '${live.songCount == 1 ? 'song' : 'songs'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    tristate: true,
                    value: holdsAll ? true : (count == 0 ? false : null),
                    activeColor: Theme.of(context).colorScheme.secondary,
                    onChanged: (_) => toggle(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens [showPlaylistsMenu] for [track]. Ticked and accent-coloured while the
/// song is in any playlist, with a tooltip naming them.
class PlaylistsButton extends StatelessWidget {
  const PlaylistsButton({super.key, required this.track, this.iconSize = 20});

  final Track track;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final names = context.select<LibraryController, String>((library) {
      final names = library.playlistNamesContaining(track.id).toList();
      return names.length <= 4
          ? names.join(', ')
          : '${names.take(3).join(', ')} and ${names.length - 3} more';
    });
    final saved = names.isNotEmpty;
    return IconButton(
      tooltip: saved ? 'Saved in $names' : 'Add to playlist',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: iconSize + 14,
        height: iconSize + 14,
      ),
      color: saved
          ? Theme.of(context).colorScheme.secondary
          : context.colors.textSecondary,
      icon: Icon(
        saved ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded,
        size: iconSize,
      ),
      onPressed: () =>
          showPlaylistsMenu(context, menuAnchorOf(context), <Track>[track]),
    );
  }
}
