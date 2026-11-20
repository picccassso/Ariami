import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/utils/format.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/track_selection_controller.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'artwork_preview.dart';
import 'collection_download_button.dart';
import 'collection_play_buttons.dart';
import 'detail_header.dart';
import 'find_in_page.dart';
import 'genre_label.dart';
import 'queue_intent.dart';
import 'track_list.dart';
import 'track_selection_bar.dart';

class AlbumDetailView extends StatefulWidget {
  const AlbumDetailView({super.key, required this.albumId});
  final String albumId;

  @override
  State<AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends State<AlbumDetailView> {
  late Future<AlbumDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LibraryController>().albumDetail(widget.albumId);
  }

  @override
  void didUpdateWidget(AlbumDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId) {
      _future = context.read<LibraryController>().albumDetail(widget.albumId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.read<ConnectionController>().client;
    return FutureBuilder<AlbumDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load album.\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        final album = snapshot.data!;
        final selection = context.watch<TrackSelectionController>();
        final audio = context.watch<AudioController>();
        final library = context.watch<LibraryController>();
        final pinned = library.isAlbumPinned(album.id);
        final totalDuration = Duration(
          seconds: album.tracks.fold(0, (sum, t) => sum + t.durationSeconds),
        );
        final albumGenreLine = genreDetail(library.albumGenres(album.id));
        // Cmd/Ctrl+F filter: rows keep their original album positions.
        final find = context.watch<FindInPageController>();
        final filtering = find.active && find.query.trim().isNotEmpty;
        final visibleIndices = <int>[
          for (var i = 0; i < album.tracks.length; i++)
            if (!filtering || find.matches(album.tracks[i])) i,
        ];
        final selectedMatch =
            find.active ? find.selectionFor(visibleIndices.length) : -1;

        final visibleIds = <String>[
          for (final i in visibleIndices) album.tracks[i].id,
        ];
        final selectedTracks = <Track>[
          for (final track in album.tracks)
            if (selection.isSelected(track.id)) track,
        ];

        final list = ListView(
          padding: EdgeInsets.zero,
          children: [
            DetailHeader(
              kindLabel: 'Album',
              title: album.title,
              subtitle: album.artist,
              linkSubtitle: true,
              metaLine: [
                '${album.tracks.length} songs',
                formatClockDuration(totalDuration),
                if (albumGenreLine != null) albumGenreLine,
              ].join(', '),
              artwork: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showArtworkPreview(
                    context,
                    client: client,
                    albumId: album.id,
                  ),
                  child: Artwork(
                    client: client,
                    albumId: album.id,
                    thumbnail: false,
                    size: 232,
                    borderRadius: PlayerTheme.coverRadius,
                    iconScale: 0.4,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
              child: Row(
                children: [
                  CollectionPlayButton(
                    tracks: album.tracks,
                    sourceId: AudioController.albumSource(album.id),
                    noun: 'album',
                  ),
                  const SizedBox(width: 12),
                  CollectionShuffleButton(
                    tracks: album.tracks,
                    sourceId: AudioController.albumSource(album.id),
                    noun: 'album',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: pinned ? 'Unpin album' : 'Pin album',
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 27,
                    ),
                    color: pinned
                        ? Theme.of(context).colorScheme.secondary
                        : context.colors.textSecondary,
                    onPressed: () => library.toggleAlbumPin(album.id),
                  ),
                  IconButton(
                    tooltip: 'Add album to end of queue',
                    icon: const Icon(Icons.queue_music_rounded, size: 28),
                    color: context.colors.textSecondary,
                    onPressed: () {
                      final at = audio.addToQueue(album.tracks);
                      showQueueAdditionToast(
                        context,
                        message: 'Album added to end of queue',
                        firstPosition: at,
                        count: album.tracks.length,
                      );
                    },
                  ),
                  CollectionDownloadButton(
                    tracks: album.tracks,
                    collectionLabel: 'album',
                    collectionName: album.title,
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
            if (find.active)
              FindInPageBar(
                controller: find,
                matchCount: visibleIndices.length,
                totalCount: album.tracks.length,
                onPlaySelected: (matchIndex) => audio.playTrack(
                  album.tracks[visibleIndices[matchIndex]],
                  context: album.tracks,
                  sourceId: AudioController.albumSource(album.id),
                ),
              ),
            const _TrackListHeader(),
            Divider(height: 1, color: context.colors.border),
            const SizedBox(height: 4),
            for (var v = 0; v < visibleIndices.length; v++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TrackRow(
                  track: album.tracks[visibleIndices[v]],
                  context: album.tracks,
                  sourceId: AudioController.albumSource(album.id),
                  index: visibleIndices[v] + 1,
                  showGoToAlbum: false,
                  // Already inside this album — the title has nowhere to go.
                  linkTitleToAlbum: false,
                  selected: v == selectedMatch,
                  selectionActive: selection.active,
                  isChecked: selection.isSelected(
                    album.tracks[visibleIndices[v]].id,
                  ),
                  onSelectTap: ({required shift, required meta}) =>
                      selection.handleRowTap(
                    visibleIds,
                    v,
                    shift: shift,
                    meta: meta,
                  ),
                ),
              ),
            // Clears the floating bar so the last rows stay reachable.
            SizedBox(height: selection.active ? 96 : 24),
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
      },
    );
  }
}

class _TrackListHeader extends StatelessWidget {
  const _TrackListHeader();

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(
      color: context.colors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 36, 6),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: headerStyle)),
          const SizedBox(width: 12),
          Expanded(child: Text('Title', style: headerStyle)),
          Icon(Icons.access_time_rounded,
              size: 16, color: context.colors.textSecondary),
        ],
      ),
    );
  }
}
