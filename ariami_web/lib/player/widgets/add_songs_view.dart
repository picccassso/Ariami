import 'dart:async';

import 'package:ariami_core/services/search/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/utils/format.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/player_api_client.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'pill_search_field.dart';

/// "Add songs" mode for a playlist.
///
/// Search the whole library and click a song (or press Enter for the active
/// match) to add it to the playlist. Songs already in the playlist show a
/// remove button instead, so the same list also lets you undo a mis-add —
/// mirroring mobile's add-to-playlist picker.
class AddSongsView extends StatefulWidget {
  const AddSongsView({
    super.key,
    required this.playlistName,
    required this.playlistSongIds,
    required this.allSongs,
    required this.onAdd,
    required this.onRemove,
    required this.onClose,
  });

  final String playlistName;

  /// Ids currently in the playlist (kept fresh by the parent's rebuilds).
  final Set<String> playlistSongIds;

  final List<Track> allSongs;

  final Future<void> Function(Track track) onAdd;
  final Future<void> Function(Track track) onRemove;
  final VoidCallback onClose;

  @override
  State<AddSongsView> createState() => _AddSongsViewState();
}

class _AddSongsViewState extends State<AddSongsView> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  int _activeCandidate = 0;

  // Songs added from this view briefly show a checkmark before flipping to
  // the remove state (same 1s transition as mobile's picker).
  final Map<String, Timer> _justAdded = {};

  static const double _rowHeight = 52;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    for (final timer in _justAdded.values) {
      timer.cancel();
    }
    super.dispose();
  }

  /// Library songs matching the query. Ranked by the shared engine when
  /// searching; the plain library order otherwise.
  List<Track> _candidates() {
    final raw = _search.text.trim();
    if (raw.isEmpty) return widget.allSongs;
    final parsed = SearchQuery.parse(raw);
    return LibrarySearchEngine.rank(
      parsed,
      widget.allSongs,
      (track) => [
        SearchField(track.title, isPrimary: true),
        SearchField(track.artist),
        if (track.albumTitle != null) SearchField(track.albumTitle!),
      ],
    );
  }

  Future<void> _add(Track track) async {
    if (widget.playlistSongIds.contains(track.id)) return;
    _justAdded[track.id]?.cancel();
    setState(() {
      _justAdded[track.id] = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _justAdded.remove(track.id));
      });
    });
    _searchFocus.requestFocus();
    await widget.onAdd(track);
  }

  Future<void> _remove(Track track) async {
    _justAdded.remove(track.id)?.cancel();
    setState(() {});
    _searchFocus.requestFocus();
    await widget.onRemove(track);
  }

  void _addActiveCandidate() {
    final candidates = _candidates();
    if (candidates.isEmpty) return;
    final selected = _activeCandidate.clamp(0, candidates.length - 1);
    _add(candidates[selected]);
  }

  void _moveCandidate(int delta) {
    final candidates = _candidates();
    if (candidates.isEmpty) return;
    final next = (_activeCandidate + delta).clamp(0, candidates.length - 1);
    if (next == _activeCandidate) return;
    setState(() => _activeCandidate = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final rowStart = next * _rowHeight;
      final visibleRows = (position.viewportDimension / _rowHeight).floor();
      final firstVisible = (position.pixels / _rowHeight).floor();
      final lastVisible = firstVisible + visibleRows - 1;
      final target = next < firstVisible
          ? rowStart
          : next > lastVisible
              ? (next - visibleRows + 1) * _rowHeight
              : position.pixels;
      if (target != position.pixels) {
        _scroll.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveCandidate(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveCandidate(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _addActiveCandidate();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // First Esc clears an in-progress search; a second one leaves the mode.
      if (_search.text.isNotEmpty) {
        setState(_search.clear);
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSearchBar() {
    return PillSearchField(
      controller: _search,
      focusNode: _searchFocus,
      hintText: 'Search your library…',
      onKeyEvent: _onSearchKey,
      onChanged: (_) {
        setState(() => _activeCandidate = 0);
        _resetScroll();
      },
      onSubmitted: (_) => _addActiveCandidate(),
      onClear: () {
        setState(() {
          _search.clear();
          _activeCandidate = 0;
        });
        _resetScroll();
        _searchFocus.requestFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final client = context.read<ConnectionController>().client;
    final candidates = _candidates();
    final inPlaylist = widget.playlistSongIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add songs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.playlistName} — search your library and click '
                      'a song (or press Enter) to add it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$inPlaylist ${inPlaylist == 1 ? 'song' : 'songs'} '
                      'in playlist',
                      key: const ValueKey('add-songs-status'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceHigh,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: _buildSearchBar(),
                  ),
                  Expanded(
                    child: candidates.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                widget.allSongs.isEmpty
                                    ? 'Your library has no songs yet.'
                                    : 'No songs match.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                              itemExtent: _rowHeight,
                              itemCount: candidates.length,
                              itemBuilder: (context, i) {
                                final track = candidates[i];
                                return _SongRow(
                                  track: track,
                                  client: client,
                                  selected: i == _activeCandidate,
                                  justAdded: _justAdded.containsKey(track.id),
                                  inPlaylist: widget.playlistSongIds
                                      .contains(track.id),
                                  onAdd: () => _add(track),
                                  onRemove: () => _remove(track),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.client,
    required this.selected,
    required this.justAdded,
    required this.inPlaylist,
    required this.onAdd,
    required this.onRemove,
  });

  final Track track;
  final PlayerApiClient? client;
  final bool selected;

  /// Added moments ago: show a confirming checkmark before the remove state.
  final bool justAdded;
  final bool inPlaylist;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;

    final Widget trailing;
    final VoidCallback? onTap;
    if (justAdded) {
      trailing = Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.check_rounded, size: 20, color: scheme.secondary),
      );
      onTap = null;
    } else if (inPlaylist) {
      trailing = IconButton(
        tooltip: 'Remove from playlist',
        iconSize: 20,
        color: scheme.error,
        icon: const Icon(Icons.remove_rounded),
        onPressed: onRemove,
      );
      onTap = onRemove;
    } else {
      trailing = IconButton(
        tooltip: 'Add to playlist',
        iconSize: 20,
        color: colors.textSecondary,
        icon: const Icon(Icons.add_rounded),
        onPressed: onAdd,
      );
      onTap = onAdd;
    }

    return Material(
      color: selected
          ? scheme.secondary.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Artwork(
                client: client,
                albumId: track.albumId,
                songId: track.albumId == null ? track.id : null,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatClockDuration(track.duration),
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(width: 4),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
