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

typedef ApplyPickOrder = void Function(
  List<String> pickedIds,
  int startIndex,
);

/// "Reorder via search" mode for a playlist.
///
/// Search for the song you want next and click it (or press Enter for the top
/// match) to place it in the next position. Picks become the playlist's first
/// positions in pick order; if you stop early, every unpicked song keeps its
/// relative order after them.
class ReorderViaSearchView extends StatefulWidget {
  const ReorderViaSearchView({
    super.key,
    required this.playlistName,
    required this.tracks,
    required this.onApply,
    required this.onCancel,
  });

  final String playlistName;

  final List<Track> tracks;

  /// Called with the picked song ids, in pick order.
  final ApplyPickOrder onApply;
  final VoidCallback onCancel;

  @override
  State<ReorderViaSearchView> createState() => _ReorderViaSearchViewState();
}

class _ReorderViaSearchViewState extends State<ReorderViaSearchView> {
  // Store playlist positions rather than song ids so duplicate entries can be
  // picked independently. The API still receives the corresponding ids.
  final List<int> _picked = <int>[];
  int _startPosition = 1;
  int _skippedCount = 0;
  int _activeCandidate = 0;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _candidateScroll = ScrollController();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _candidateScroll.dispose();
    super.dispose();
  }

  // Shared-engine matching (normalization, transliteration, layout
  // correction, fuzz) but never its ranking: candidates must stay in
  // playlist order so Enter-picks-top-match remains position-based.
  bool _matches(Track track, SearchQuery query) {
    return LibrarySearchEngine.matches(query, [
      SearchField(track.title, isPrimary: true),
      SearchField(track.artist),
      if (track.albumTitle != null) SearchField(track.albumTitle!),
    ]);
  }

  List<int> _candidates() {
    final raw = _search.text.trim();
    final query = raw.isEmpty ? null : SearchQuery.parse(raw);
    return <int>[
      for (var i = _startPosition - 1; i < widget.tracks.length; i++)
        if (!_picked.contains(i) &&
            (query == null || _matches(widget.tracks[i], query)))
          i,
    ];
  }

  void _pick(int trackIndex) {
    setState(() {
      _picked.add(trackIndex);
      _activeCandidate = 0;
      _search.clear();
    });
    _resetCandidateScroll();
    _searchFocus.requestFocus();
  }

  void _unpick(int trackIndex) {
    setState(() => _picked.remove(trackIndex));
    _searchFocus.requestFocus();
  }

  void _undoLastPick() {
    if (_picked.isEmpty) return;
    setState(_picked.removeLast);
    _searchFocus.requestFocus();
  }

  void _skipMissing() {
    setState(() {
      _skippedCount++;
      _activeCandidate = 0;
      _search.clear();
    });
    _resetCandidateScroll();
    _searchFocus.requestFocus();
  }

  void _pickActiveCandidate() {
    final candidates = _candidates();
    if (candidates.isEmpty) return;
    final selected = _activeCandidate.clamp(0, candidates.length - 1);
    _pick(candidates[selected]);
  }

  void _moveCandidate(int delta) {
    final candidates = _candidates();
    if (candidates.isEmpty) return;
    final next = (_activeCandidate + delta).clamp(0, candidates.length - 1);
    if (next == _activeCandidate) return;
    setState(() => _activeCandidate = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_candidateScroll.hasClients) return;
      const rowHeight = 52.0;
      final position = _candidateScroll.position;
      final rowStart = next * rowHeight;
      final visibleRows = (position.viewportDimension / rowHeight).floor();
      final firstVisible = (position.pixels / rowHeight).floor();
      final lastVisible = firstVisible + visibleRows - 1;
      final target = next < firstVisible
          ? rowStart
          : next > lastVisible
              ? (next - visibleRows + 1) * rowHeight
              : position.pixels;
      if (target != position.pixels) {
        _candidateScroll.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resetCandidateScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_candidateScroll.hasClients) _candidateScroll.jumpTo(0);
    });
  }

  Future<void> _chooseStartPosition() async {
    if (widget.tracks.isEmpty) return;
    var input = '$_startPosition';
    final position = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int value() => (int.tryParse(input) ?? _startPosition).clamp(
              1,
              widget.tracks.length,
            );

        return AlertDialog(
          title: const Text('Choose start position'),
          content: TextFormField(
            initialValue: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) => input = value,
            decoration: InputDecoration(
              labelText: 'Start at',
              helperText: _picked.isEmpty && _skippedCount == 0
                  ? 'Earlier songs will stay exactly where they are.'
                  : 'Changing this clears your current picks and skips.',
            ),
            onFieldSubmitted: (_) => Navigator.of(dialogContext).pop(value()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value()),
              child: const Text('Set position'),
            ),
          ],
        );
      },
    );
    if (!mounted || position == null || position == _startPosition) return;
    setState(() {
      _startPosition = position;
      _picked.clear();
      _skippedCount = 0;
      _activeCandidate = 0;
      _search.clear();
    });
    _resetCandidateScroll();
    _searchFocus.requestFocus();
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
      _pickActiveCandidate();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // First Esc clears an in-progress search; a second one leaves the mode.
      if (_search.text.isNotEmpty) {
        setState(_search.clear);
      } else {
        widget.onCancel();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSearchBar(int nextPosition) {
    return PillSearchField(
      controller: _search,
      focusNode: _searchFocus,
      hintText: 'Find the song for position $nextPosition…',
      onKeyEvent: _onSearchKey,
      onChanged: (_) {
        setState(() => _activeCandidate = 0);
        _resetCandidateScroll();
      },
      onSubmitted: (_) => _pickActiveCandidate(),
    );
  }

  Widget _buildPickedPane(
    BuildContext context,
    PlayerApiClient? client,
  ) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _SectionLabel('New order (${_picked.length})')),
              OutlinedButton.icon(
                onPressed: widget.tracks.isEmpty ? null : _chooseStartPosition,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.pin_drop_outlined, size: 16),
                label: Text('Start at $_startPosition'),
              ),
              IconButton(
                tooltip: 'Undo last pick',
                onPressed: _picked.isEmpty ? null : _undoLastPick,
                icon: const Icon(Icons.undo_rounded, size: 18),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: _picked.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Your picks will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: _picked.length,
                      itemBuilder: (context, i) => _PickedRow(
                        position: _startPosition + i,
                        track: widget.tracks[_picked[i]],
                        client: client,
                        onRemove: () => _unpick(_picked[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidatePane(
    BuildContext context,
    PlayerApiClient? client,
    List<int> candidates,
    int nextPosition,
  ) {
    final colors = context.colors;
    final editableCount = widget.tracks.length - (_startPosition - 1);
    final allEditablePicked = _picked.length >= editableCount;
    return Container(
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _buildSearchBar(nextPosition),
          ),
          Row(
            children: [
              Expanded(
                child: _SectionLabel(
                  _search.text.trim().isEmpty
                      ? 'Pick position $nextPosition'
                      : 'Matches for position $nextPosition '
                          '(${candidates.length})',
                ),
              ),
              Tooltip(
                message: 'The source track is not in this playlist',
                child: TextButton.icon(
                  onPressed: allEditablePicked ? null : _skipMissing,
                  icon: const Icon(Icons.skip_next_rounded, size: 17),
                  label: const Text('Skip / missing'),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: candidates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        allEditablePicked
                            ? 'Every song has a new position — apply the order!'
                            : 'No songs match.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _candidateScroll,
                    child: ListView.builder(
                      controller: _candidateScroll,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemExtent: 52,
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final trackIndex = candidates[i];
                        return _CandidateRow(
                          track: widget.tracks[trackIndex],
                          client: client,
                          selected: i == _activeCandidate,
                          onPick: () => _pick(trackIndex),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final client = context.read<ConnectionController>().client;
    final candidates = _candidates();
    final startIndex = _startPosition - 1;
    final nextPosition = _startPosition + _picked.length + _skippedCount;
    final remaining = widget.tracks.length - startIndex - _picked.length;
    final status = '${formatCountWithCommas(_picked.length)} picked · '
        '${formatCountWithCommas(remaining)} remaining'
        '${_skippedCount == 0 ? '' : ' · ${formatCountWithCommas(_skippedCount)} skipped'}';

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
                      'Reorder via search',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.playlistName} — search a song and click it '
                      '(or press Enter) to place it next. Unpicked songs keep '
                      'their order after your picks.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status,
                      key: const ValueKey('reorder-status'),
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
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => widget.onApply(
                          [
                            for (final index in _picked)
                              widget.tracks[index].id,
                          ],
                          startIndex,
                        ),
                child: Text(
                  _picked.isEmpty
                      ? 'Apply order'
                      : 'Apply order (${_picked.length})',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pickedPane = _buildPickedPane(context, client);
                final candidatePane = _buildCandidatePane(
                  context,
                  client,
                  candidates,
                  nextPosition,
                );
                if (constraints.maxWidth >= 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: pickedPane),
                      const SizedBox(width: 12),
                      Expanded(flex: 6, child: candidatePane),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: _picked.isEmpty ? 1 : 2, child: pickedPane),
                    const SizedBox(height: 12),
                    Expanded(
                        flex: _picked.isEmpty ? 4 : 3, child: candidatePane),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _PickedRow extends StatelessWidget {
  const _PickedRow({
    required this.position,
    required this.track,
    required this.client,
    required this.onRemove,
  });

  final int position;
  final Track track;
  final PlayerApiClient? client;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$position',
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Artwork(
            client: client,
            albumId: track.albumId,
            songId: track.albumId == null ? track.id : null,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TitleArtist(track: track),
          ),
          IconButton(
            tooltip: 'Remove from new order',
            iconSize: 18,
            color: colors.textSecondary,
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.track,
    required this.client,
    required this.selected,
    required this.onPick,
  });

  final Track track;
  final PlayerApiClient? client;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.secondary.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.arrow_forward_rounded : Icons.add_rounded,
                size: 20,
                color: selected ? scheme.secondary : colors.textSecondary,
              ),
              const SizedBox(width: 16),
              Artwork(
                client: client,
                albumId: track.albumId,
                songId: track.albumId == null ? track.id : null,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(child: _TitleArtist(track: track)),
              const SizedBox(width: 8),
              Text(
                formatClockDuration(track.duration),
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleArtist extends StatelessWidget {
  const _TitleArtist({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
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
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}
