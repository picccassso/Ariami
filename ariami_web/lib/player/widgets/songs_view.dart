import 'package:ariami_core/services/search/search.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/library_controller.dart';
import '../services/track_selection_controller.dart';
import '../theme/player_theme.dart';
import 'collection_play_buttons.dart';
import 'find_in_page.dart';
import 'track_list.dart';
import 'track_selection_bar.dart';

/// Every song in the library as one flat, alphabetical list — the only view
/// that reaches songs the scanner left outside an album (loose files, singles,
/// anything whose tags never formed an album). Reached from the sidebar's
/// "All Songs" tile. Lazily built, so large libraries stay smooth.
class SongsView extends StatefulWidget {
  const SongsView({super.key});

  @override
  State<SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<SongsView> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Sorting every song is far too costly to redo on every rebuild — a track
  /// change or a hover would each pay for it. Cached and rebuilt only when the
  /// library replaces its song list.
  List<Track>? _source;
  List<Track> _sorted = const <Track>[];

  /// Ranking is likewise per-query work, not per-rebuild work: cached against
  /// both inputs so hovering a row doesn't re-rank the whole library.
  String _rankedQuery = '';
  List<Track>? _rankedSource;
  List<Track> _ranked = const <Track>[];

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The visible list: the whole library A–Z, or search hits ranked by the
  /// shared core engine (same tiers, transliteration and layout correction the
  /// top-bar search uses).
  List<Track> _visible() {
    final query = _search.text.trim();
    if (query.isEmpty) return _sorted;
    if (query == _rankedQuery && identical(_rankedSource, _sorted)) {
      return _ranked;
    }
    _rankedQuery = query;
    _rankedSource = _sorted;
    _ranked = LibrarySearchEngine.rank(
      SearchQuery.parse(query),
      _sorted,
      (track) => [
        SearchField(track.title, isPrimary: true),
        SearchField(track.artist),
        if (track.albumTitle != null) SearchField(track.albumTitle!),
      ],
    );
    return _ranked;
  }

  void _onRowTap(
    TrackSelectionController selection,
    List<Track> visible,
    int index, {
    required bool shift,
    required bool meta,
  }) {
    selection.handleRowTap(
      <String>[for (final track in visible) track.id],
      index,
      shift: shift,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<TrackSelectionController>();
    final songs = context.watch<LibraryController>().songs;
    if (!identical(songs, _source)) {
      _source = songs;
      _sorted = List<Track>.from(songs)
        ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    final visible = _visible();

    // Cmd/Ctrl+F is handled by the shell; here it just focuses the field that
    // is already on screen, rather than opening a second search surface.
    final find = context.watch<FindInPageController>();
    if (find.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !find.active) return;
        _searchFocus.requestFocus();
        _search.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _search.text.length,
        );
        find.close();
      });
    }

    final selected = <Track>[
      for (final track in _sorted)
        if (selection.isSelected(track.id)) track,
    ];

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _SongsHeader(
                total: _sorted.length,
                matches: visible.length,
                searching: _search.text.trim().isNotEmpty,
                controller: _search,
                focusNode: _searchFocus,
                onQueryChanged: () => setState(() {}),
                selecting: selection.active,
                onToggleSelecting: () =>
                    selection.active ? selection.exit() : selection.enter(),
                tracks: _sorted,
              ),
            ),
            if (visible.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      _sorted.isEmpty
                          ? 'No songs yet. Make sure your library has been '
                              'scanned.'
                          : 'No songs match "${_search.text.trim()}".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  // Clear the floating action bar so the last rows stay
                  // reachable while selecting.
                  selection.active ? 96 : 32,
                ),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) => TrackRow(
                    track: visible[i],
                    context: visible,
                    // A filtered list is a subset, not the All Songs
                    // collection, so it must not claim to be playing it.
                    sourceId: identical(visible, _sorted)
                        ? AudioController.allSongsSource
                        : null,
                    showArtwork: true,
                    showAlbum: true,
                    selectionActive: selection.active,
                    isChecked: selection.isSelected(visible[i].id),
                    onSelectTap: ({required shift, required meta}) => _onRowTap(
                        selection, visible, i,
                        shift: shift, meta: meta),
                  ),
                ),
              ),
          ],
        ),
        if (selection.active)
          TrackSelectionBar(
            selected: selected,
            onSelectAll: () => selection
                .selectAll(<String>[for (final track in visible) track.id]),
            onDone: selection.exit,
          ),
      ],
    );
  }
}

class _SongsHeader extends StatelessWidget {
  /// One width for the filter field, whatever the window is doing.
  static const double _filterWidth = 280;

  const _SongsHeader({
    required this.total,
    required this.matches,
    required this.searching,
    required this.controller,
    required this.focusNode,
    required this.onQueryChanged,
    required this.selecting,
    required this.onToggleSelecting,
    required this.tracks,
  });

  final int total;
  final int matches;
  final bool searching;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onQueryChanged;
  final bool selecting;
  final VoidCallback onToggleSelecting;

  /// The full (sorted) song list, in the order Play would start it.
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All Songs',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? '$matches of $total ${total == 1 ? 'song' : 'songs'}'
                : '$total ${total == 1 ? 'song' : 'songs'} in your library',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          // The filter keeps one fixed width at every window size — it only
          // changes which line it sits on, never how big it is. Letting it
          // stretch on the narrow layout made it largest exactly where there
          // was least room, which read as a different control entirely.
          LayoutBuilder(
            builder: (context, constraints) {
              final filter = SizedBox(
                width: _filterWidth,
                child: _SearchField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onQueryChanged,
                ),
              );
              final select = SelectModeButton(
                selecting: selecting,
                onPressed: onToggleSelecting,
              );
              if (constraints.maxWidth >= 680) {
                // Filter sits with the actions it applies to, not marooned
                // against the right edge; only the mode toggle goes right.
                return Row(
                  children: [
                    ..._playButtons(),
                    const SizedBox(width: 16),
                    filter,
                    const Spacer(),
                    select,
                  ],
                );
              }
              // Same arrangement, wrapped: the filter still leads the row and
              // Select still holds the right edge.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: _playButtons()),
                  const SizedBox(height: 10),
                  Row(children: [filter, const Spacer(), select]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _playButtons() => [
        CollectionPlayButton(
          tracks: tracks,
          sourceId: AudioController.allSongsSource,
          noun: 'all songs',
        ),
        const SizedBox(width: 10),
        CollectionShuffleButton(
          tracks: tracks,
          sourceId: AudioController.allSongsSource,
          noun: 'all songs',
        ),
      ];
}

/// Filters the list as you type. Always visible — this list is the one place
/// a user lands specifically to hunt for a song, so the search must not be
/// hidden behind a keyboard shortcut.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: 'Filter songs…',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                tooltip: 'Clear filter',
                splashRadius: 16,
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              );
            },
          ),
          isDense: true,
          filled: true,
          fillColor: context.colors.surfaceHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
