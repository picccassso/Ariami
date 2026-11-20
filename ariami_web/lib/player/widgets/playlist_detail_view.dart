import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/utils/format.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../services/track_selection_controller.dart';
import '../theme/player_theme.dart';
import 'add_songs_view.dart';
import 'collection_download_button.dart';
import 'collection_play_buttons.dart';
import 'detail_header.dart';
import 'find_in_page.dart';
import 'playlist_actions.dart';
import 'playlist_artwork.dart';
import 'queue_intent.dart';
import 'reorder_via_search_view.dart';
import 'track_list.dart';
import 'track_selection_bar.dart';

class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({super.key, required this.playlistId});
  final String playlistId;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  bool _reorderViaSearch = false;
  bool _addSongs = false;

  @override
  void didUpdateWidget(PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId) {
      _reorderViaSearch = false;
      _addSongs = false;
    }
  }

  Future<void> _applyPickOrder(
    LibraryController library,
    String playlistId,
    List<String> pickedIds,
    int startIndex,
  ) async {
    setState(() => _reorderViaSearch = false);
    await library.applyPlaylistPickOrder(
      playlistId,
      pickedIds,
      startIndex: startIndex,
    );
    if (mounted) {
      _toast(
        context,
        'Reordered ${pickedIds.length} '
        '${pickedIds.length == 1 ? 'song' : 'songs'} from position '
        '${startIndex + 1}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final playlist = library.playlists.cast<PlaylistSummary?>().firstWhere(
          (p) => p?.id == widget.playlistId,
          orElse: () => null,
        );
    if (playlist == null) {
      return const Center(child: Text('This playlist is no longer available.'));
    }

    // read (not watch): this view only invokes AudioController from button
    // callbacks and shows none of its state, so there's no reason to rebuild the
    // whole playlist screen on every playback position tick.
    final audio = context.read<AudioController>();
    final selection = context.watch<TrackSelectionController>();
    final tracks = library.playlistTracks(playlist);

    if (_reorderViaSearch) {
      return ReorderViaSearchView(
        playlistName: playlist.name,
        tracks: tracks,
        onApply: (pickedIds, startIndex) =>
            _applyPickOrder(library, playlist.id, pickedIds, startIndex),
        onCancel: () => setState(() => _reorderViaSearch = false),
      );
    }

    if (_addSongs) {
      return AddSongsView(
        playlistName: playlist.name,
        playlistSongIds: playlist.songIds.toSet(),
        allSongs: library.songs,
        onAdd: (track) => library.addTrackToPlaylist(playlist.id, track.id),
        onRemove: (track) =>
            library.removeTrackFromPlaylist(playlist.id, track.id),
        onClose: () => setState(() => _addSongs = false),
      );
    }
    // Cmd/Ctrl+F filter: while active, only matching rows are shown. Rows
    // keep their original playlist index, and reordering is disabled because
    // filtered positions don't map back to real playlist positions.
    final find = context.watch<FindInPageController>();
    final filtering = find.active && find.query.trim().isNotEmpty;
    final visibleIndices = <int>[
      for (var i = 0; i < tracks.length; i++)
        if (!filtering || find.matches(tracks[i])) i,
    ];
    final selectedMatch =
        find.active ? find.selectionFor(visibleIndices.length) : -1;
    final total = Duration(
      seconds: tracks.fold(0, (sum, track) => sum + track.durationSeconds),
    );
    final visibleIds = <String>[
      for (final i in visibleIndices) tracks[i].id,
    ];
    final selectedTracks = <Track>[
      for (final track in tracks)
        if (selection.isSelected(track.id)) track,
    ];

    final list = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: DetailHeader(
            kindLabel: 'Playlist',
            title: playlist.name,
            subtitle: 'Your library',
            metaLine: '${tracks.length} songs, ${formatClockDuration(total)}',
            artwork: PlaylistArtwork(
              playlist: playlist,
              size: 200,
              borderRadius: PlayerTheme.coverRadius,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
            child: Row(
              children: [
                CollectionPlayButton(
                  tracks: tracks,
                  sourceId: AudioController.playlistSource(playlist.id),
                  noun: 'playlist',
                ),
                const SizedBox(width: 12),
                CollectionShuffleButton(
                  tracks: tracks,
                  sourceId: AudioController.playlistSource(playlist.id),
                  noun: 'playlist',
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: library.isPlaylistPinned(playlist.id)
                      ? 'Unpin playlist'
                      : 'Pin playlist',
                  icon: Icon(
                    library.isPlaylistPinned(playlist.id)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 27,
                  ),
                  color: library.isPlaylistPinned(playlist.id)
                      ? Theme.of(context).colorScheme.secondary
                      : context.colors.textSecondary,
                  onPressed: () => library.togglePlaylistPin(playlist.id),
                ),
                IconButton(
                  tooltip: 'Add songs to this playlist',
                  icon: const Icon(Icons.playlist_add_rounded, size: 28),
                  color: context.colors.textSecondary,
                  onPressed: () => setState(() => _addSongs = true),
                ),
                IconButton(
                  tooltip: 'Add playlist to end of queue',
                  icon: const Icon(Icons.queue_music_rounded, size: 28),
                  color: context.colors.textSecondary,
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          final at = audio.addToQueue(tracks);
                          showQueueAdditionToast(
                            context,
                            message: 'Playlist added to end of queue',
                            firstPosition: at,
                            count: tracks.length,
                          );
                        },
                ),
                CollectionDownloadButton(
                  tracks: tracks,
                  collectionLabel: 'playlist',
                  collectionName: playlist.name,
                ),
                PopupMenuButton<String>(
                  tooltip: 'Playlist options',
                  icon: const Icon(Icons.more_horiz_rounded),
                  color: context.colors.popover,
                  onSelected: (value) {
                    if (value == 'edit-details') {
                      showEditPlaylistDetailsDialog(context, playlist);
                    } else if (value == 'reorder-search') {
                      setState(() => _reorderViaSearch = true);
                    } else if (value == 'delete') {
                      _deletePlaylist(context, playlist);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit-details',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit details'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reorder-search',
                      enabled: tracks.isNotEmpty,
                      child: const ListTile(
                        dense: true,
                        leading: Icon(Icons.manage_search_rounded),
                        title: Text('Reorder via search'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete playlist'),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SelectModeIconButton(
                  selecting: selection.active,
                  onPressed: () =>
                      selection.active ? selection.exit() : selection.enter(),
                ),
              ],
            ),
          ),
        ),
        if (find.active)
          SliverToBoxAdapter(
            child: FindInPageBar(
              controller: find,
              matchCount: visibleIndices.length,
              totalCount: tracks.length,
              onPlaySelected: (matchIndex) => audio.playTrack(
                tracks[visibleIndices[matchIndex]],
                context: tracks,
                sourceId: AudioController.playlistSource(playlist.id),
              ),
            ),
          ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      library.isCreatedPlaylist(playlist.id)
                          ? 'This playlist is empty.'
                          : 'No playable tracks found for this playlist.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _addSongs = true),
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('Add songs'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverReorderableList(
              itemCount: visibleIndices.length,
              onReorderItem: (oldIndex, newIndex) =>
                  library.movePlaylistTrack(playlist.id, oldIndex, newIndex),
              // The drag proxy is re-built inside the root Overlay, above
              // PlayerRoot's providers, so re-expose the ones TrackRow reads
              // or the proxy dies with ProviderNotFoundException (a gray
              // ErrorWidget box in release builds).
              proxyDecorator: (child, index, animation) => MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(
                    value: context.read<AudioController>(),
                  ),
                  ChangeNotifierProvider.value(
                    value: context.read<ConnectionController>(),
                  ),
                  ChangeNotifierProvider.value(
                    value: context.read<LibraryController>(),
                  ),
                  ChangeNotifierProvider<PlayerDownloadsBridge?>.value(
                    value: maybeReadProvider<PlayerDownloadsBridge?>(context) ??
                        maybeReadProvider<PlayerDownloadsBridge>(context),
                  ),
                ],
                child: Material(
                  color: context.colors.popover,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                ),
              ),
              itemBuilder: (context, i) {
                final trackIndex = visibleIndices[i];
                final track = tracks[trackIndex];
                // Dragging is off while selecting for the same reason it is
                // off while filtering: a click on a row means "select", and a
                // reorder mid-selection has no sensible target.
                final noDrag = filtering || selection.active;
                final handle = SizedBox(
                  width: 32,
                  height: 52,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: noDrag
                        ? Colors.transparent
                        : context.colors.textSecondary,
                  ),
                );
                return Row(
                  key: ValueKey('playlist-${playlist.id}-${track.id}'),
                  children: [
                    if (noDrag)
                      handle
                    else
                      ReorderableDragStartListener(
                        index: i,
                        child: Tooltip(
                          message: 'Drag to reorder',
                          child: handle,
                        ),
                      ),
                    Expanded(
                      child: TrackRow(
                        track: track,
                        context: tracks,
                        sourceId: AudioController.playlistSource(playlist.id),
                        index: trackIndex + 1,
                        showArtwork: true,
                        showAlbum: true,
                        // Playlist titles stay non-navigational.
                        linkTitleToAlbum: false,
                        selected: i == selectedMatch,
                        selectionActive: selection.active,
                        isChecked: selection.isSelected(track.id),
                        onSelectTap: ({required shift, required meta}) =>
                            selection.handleRowTap(
                          visibleIds,
                          i,
                          shift: shift,
                          meta: meta,
                        ),
                        onRemove: () => _removeTrack(
                          context,
                          library,
                          playlist.id,
                          track,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        // Clears the floating bar so the last rows stay reachable.
        SliverToBoxAdapter(
          child: SizedBox(height: selection.active ? 96 : 24),
        ),
      ],
    );

    if (!selection.active) return list;
    return Stack(
      children: [
        list,
        TrackSelectionBar(
          selected: selectedTracks,
          onSelectAll: () => selection.selectAll(visibleIds),
          onDone: selection.exit,
        ),
      ],
    );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    PlaylistSummary playlist,
  ) async {
    final deleted = await confirmDeletePlaylist(context, playlist);
    if (!deleted || !context.mounted) return;
    if (context.mounted) context.read<PlayerNavigator>().goBack();
  }

  /// Removes [track] from the playlist, offering Undo unless nothing changed
  /// (e.g. offline).
  Future<void> _removeTrack(
    BuildContext context,
    LibraryController library,
    String playlistId,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final before = library.playlistSongIds(playlistId);
    await library.removeTrackFromPlaylist(playlistId, track.id);
    if (before == null ||
        listEquals(library.playlistSongIds(playlistId), before)) {
      return;
    }
    showUndoToast(
      messenger,
      'Removed "${track.title}"',
      onUndo: () => unawaited(library.restorePlaylistSongs(playlistId, before)),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }
}
