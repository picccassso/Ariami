import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_api_client.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../theme/player_theme.dart';
import 'artist_credit_links.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'track_badge.dart';
import 'playlists_menu.dart';
import 'queue_context_menu.dart';
import 'queue_remove_button.dart';

/// The metrics that differ between the two queue surfaces. Everything else
/// about them — rows, reordering, selection, the right-click menu — is shared.
class QueueListStyle {
  const QueueListStyle({
    required this.artworkSize,
    required this.artworkRadius,
    required this.titleSize,
    required this.subtitleSize,
    required this.rowPadding,
    required this.listPadding,
  });

  final double artworkSize;
  final double artworkRadius;
  final double titleSize;
  final double subtitleSize;
  final EdgeInsets rowPadding;
  final EdgeInsets listPadding;

  /// The right-hand Now Playing panel, whose queue sits inside that panel's
  /// own scroll view.
  static const panel = QueueListStyle(
    artworkSize: 38,
    artworkRadius: PlayerTheme.coverRadius,
    titleSize: 14,
    subtitleSize: 12.5,
    rowPadding: EdgeInsets.only(left: 2, right: 8),
    listPadding: EdgeInsets.zero,
  );

  static const fullScreen = QueueListStyle(
    artworkSize: 42,
    artworkRadius: PlayerTheme.coverRadius,
    titleSize: 14,
    subtitleSize: 12,
    rowPadding: EdgeInsets.symmetric(horizontal: 4),
    listPadding: EdgeInsets.fromLTRB(8, 0, 8, 16),
  );
}

/// The upcoming queue: tap to jump, drag to reorder, right-click for the
/// per-song actions, and shift / cmd-click to work on several rows at once.
///
/// A remote device's queue can only be removed from, so it renders as a plain
/// list with neither drag handles nor selection.
class QueueList extends StatefulWidget {
  const QueueList({
    super.key,
    required this.keyPrefix,
    required this.maxRows,
    this.style = QueueListStyle.panel,
    this.nested = false,
    this.onBeforeNavigate,
  });

  /// Prefix for the per-row widget keys ('main-queue' / 'full-queue').
  final String keyPrefix;

  final int maxRows;

  final QueueListStyle style;

  /// Whether this list lives inside a parent scroll view, in which case it
  /// lays itself out fully and leaves scrolling to the parent.
  final bool nested;

  /// Runs just before an artist view opens (e.g. popping the fullscreen player).
  final VoidCallback? onBeforeNavigate;

  @override
  State<QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<QueueList> {
  /// The selection, held as backing queue indices rather than row positions:
  /// those are unique even when a track is queued twice, and they follow their
  /// rows through a reorder.
  final Set<int> _selected = <int>{};

  /// Queue index of the last toggled row — the origin of a shift-click range.
  int? _anchor;

  /// While a multi-selection is being dragged: the row positions travelling
  /// with the pointer, and which of them is the one actually under it. Empty
  /// at rest, and for a plain single-row drag.
  List<int> _carried = const <int>[];
  int? _carrier;

  /// Holds keyboard focus while a selection is up, so Escape reaches this list
  /// before the handlers above it (the shell's shortcuts, and the fullscreen
  /// player's close). Every other key is passed on, so the transport
  /// shortcuts keep working while rows are selected.
  final FocusNode _focus = FocusNode(debugLabel: 'QueueSelection');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        _selected.isEmpty) {
      return KeyEventResult.ignored;
    }
    _clearSelection();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final client = context.read<ConnectionController>().client;
    final upcoming = audio.upcoming;
    final count = math.min(upcoming.length, widget.maxRows);
    // Empty while a remote device owns the queue, which is also what makes
    // that queue read-only here.
    final keys = audio.upcomingQueueIndices.take(count).toList(growable: false);
    _selected.retainWhere(keys.contains);
    if (!_selected.contains(_anchor)) _anchor = null;

    final positions = _selectedPositions(keys);
    final list = keys.isEmpty
        ? _plainList(context, audio, client, upcoming, count)
        : _reorderableList(context, audio, client, upcoming, count, keys);

    // The bar's slot stays in the tree even when empty: swapping the whole
    // list in and out as the selection comes and goes would remount it, losing
    // its scroll position — and any menu opened from the row that just changed
    // the selection.
    return Focus(
      focusNode: _focus,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (positions.isEmpty)
            const SizedBox.shrink()
          else
            _QueueSelectionBar(
              tracks: [for (final i in positions) upcoming[i]],
              positions: positions,
              onDone: _clearSelection,
            ),
          if (widget.nested) list else Expanded(child: list),
        ],
      ),
    );
  }

  List<int> _selectedPositions(List<int> keys) {
    final positions = <int>[];
    for (var i = 0; i < keys.length; i++) {
      if (_selected.contains(keys[i])) positions.add(i);
    }
    return positions;
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    // Focus deliberately stays here. Key events travel from the focused node
    // up through its ancestors, so the shortcuts above this list keep working
    // either way — whereas unfocusing drops focus on the enclosing scope,
    // which leaves the fullscreen player's own Escape and transport keys dead.
    setState(() {
      _selected.clear();
      _anchor = null;
    });
  }

  /// A click on row [index]: modifiers select, a plain click drops the
  /// selection and plays the row as it always has.
  void _handleTap(AudioController audio, List<int> keys, int index) {
    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    // cmd on macOS, where ctrl-click is the platform's secondary click — the
    // same split the library's track lists use.
    final meta = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (keys.isEmpty || (!shift && !meta)) {
      _clearSelection();
      audio.playFromUpcomingIndex(index);
      return;
    }
    setState(() {
      final anchorIndex = _anchor == null ? -1 : keys.indexOf(_anchor!);
      if (shift && anchorIndex >= 0) {
        final from = math.min(anchorIndex, index);
        final to = math.max(anchorIndex, index);
        _selected.addAll(keys.sublist(from, to + 1));
        return;
      }
      final key = keys[index];
      if (!_selected.remove(key)) _selected.add(key);
      _anchor = _selected.contains(key) ? key : null;
    });
    // Take focus so Escape lands here rather than on whatever owns the
    // shortcuts above this list.
    if (_selected.isNotEmpty) _focus.requestFocus();
  }

  /// Right-click on row [index]. A row outside the selection acts alone —
  /// and takes the selection with it, so the menu always matches what is
  /// highlighted.
  void _openMenu(
    BuildContext context,
    Offset position,
    List<Track> upcoming,
    List<int> keys,
    int index,
  ) {
    var positions = _selectedPositions(keys);
    if (!positions.contains(index)) {
      _clearSelection();
      positions = <int>[index];
    }
    showQueueContextMenu(
      context,
      position,
      tracks: [for (final i in positions) upcoming[i]],
      upcomingIndices: positions,
    );
  }

  Widget _plainList(
    BuildContext context,
    AudioController audio,
    PlayerApiClient? client,
    List<Track> upcoming,
    int count,
  ) {
    Widget row(int i) =>
        _row(context, audio, client, upcoming, const <int>[], i);
    if (widget.nested) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < count; i++) row(i)],
      );
    }
    return ListView.builder(
      padding: widget.style.listPadding,
      itemCount: count,
      itemBuilder: (context, i) => row(i),
    );
  }

  Widget _reorderableList(
    BuildContext context,
    AudioController audio,
    PlayerApiClient? client,
    List<Track> upcoming,
    int count,
    List<int> keys,
  ) {
    return ReorderableListView.builder(
      padding: widget.style.listPadding,
      shrinkWrap: widget.nested,
      physics: widget.nested ? const NeverScrollableScrollPhysics() : null,
      buildDefaultDragHandles: false,
      itemCount: count,
      // The rest of a dragged selection leaves the list for the duration of
      // the drag, so what is on screen is what the drop will produce: one
      // pile under the cursor and a queue without it. Leaving them in place
      // read as dragging a single row that then teleported its neighbours.
      onReorderStart: (index) {
        final positions = _selectedPositions(keys);
        if (positions.length > 1 && positions.contains(index)) {
          setState(() {
            _carried = positions;
            _carrier = index;
          });
        }
      },
      onReorderEnd: (_) {
        if (_carried.isEmpty) return;
        setState(() {
          _carried = const <int>[];
          _carrier = null;
        });
      },
      onReorderItem: (oldIndex, newIndex) {
        // Dragging any row of a multi-selection carries the whole selection.
        final positions = _selectedPositions(keys);
        if (positions.length > 1 && positions.contains(oldIndex)) {
          audio.moveUpcomingAll(
            positions,
            queueBlockTarget(positions, oldIndex, newIndex),
          );
          return;
        }
        audio.moveUpcoming(oldIndex, newIndex);
      },
      // The drag proxy is re-built inside the root Overlay, above
      // PlayerRoot's providers, so re-expose the ones a queue row reads
      // or the proxy dies with ProviderNotFoundException (a gray
      // ErrorWidget box in release builds).
      proxyDecorator: (child, index, animation) {
        final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
            maybeReadProvider<PlayerDownloadsBridge>(context);
        return MultiProvider(
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
              value: downloads,
            ),
            ChangeNotifierProvider.value(
              value: context.read<PlayerNavigator>(),
            ),
          ],
          child: Material(
            color: context.colors.popover,
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: _carried.length > 1
                ? _carriedPile(context, client, upcoming)
                : child,
          ),
        );
      },
      // The row itself is the drag target, with no handle to aim for: the
      // drag only wins the gesture arena once the pointer moves, so a plain
      // click still plays the row and a modifier-click still selects it.
      itemBuilder: (context, i) => ReorderableDragStartListener(
        key: ValueKey('${widget.keyPrefix}-${keys[i]}'),
        index: i,
        // Collapsed rather than omitted: the list is mid-drag and its
        // bookkeeping is by index, so every row has to stay an item.
        child: _carried.contains(i) && i != _carrier
            ? const SizedBox.shrink()
            : _row(context, audio, client, upcoming, keys, i),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AudioController audio,
    PlayerApiClient? client,
    List<Track> upcoming,
    List<int> keys,
    int index,
  ) {
    final selected = keys.isNotEmpty && _selected.contains(keys[index]);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _handleTap(audio, keys, index),
        onSecondaryTapDown: (details) => _openMenu(
          context,
          details.globalPosition,
          upcoming,
          keys,
          index,
        ),
        child: _rowTile(
          context,
          client,
          upcoming[index],
          number: index + 1,
          linksEnabled: _selected.isEmpty,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlaylistsButton(track: upcoming[index], iconSize: 18),
              QueueRemoveButton(
                key: ValueKey('${widget.keyPrefix}-remove-$index'),
                onPressed: () => removeUpcomingWithUndo(
                  audio,
                  ScaffoldMessenger.maybeOf(context),
                  <int>[index],
                  <Track>[upcoming[index]],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A queue row's visuals, shared by the live list and the dragged pile.
  Widget _rowTile(
    BuildContext context,
    PlayerApiClient? client,
    Track track, {
    int? number,
    bool linksEnabled = true,
    Widget? trailing,
  }) {
    final style = widget.style;
    final artwork = Artwork(
      client: client,
      albumId: track.albumId,
      songId: track.albumId == null ? track.id : null,
      size: style.artworkSize,
      borderRadius: style.artworkRadius,
      iconScale: 0.42,
    );
    return ListTile(
      dense: true,
      contentPadding: style.rowPadding,
      horizontalTitleGap: 12,
      // The queue is a running order, so it is numbered.
      leading: number == null
          ? artwork
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$number',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.colors.textSecondary,
                      fontFeatures: PlayerTheme.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                artwork,
              ],
            ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: style.titleSize,
          color: context.colors.textPrimary,
        ),
      ),
      subtitle: Builder(
        builder: (context) {
          final downloads =
              maybeReadProvider<PlayerDownloadsBridge?>(context) ??
                  maybeReadProvider<PlayerDownloadsBridge>(context);
          final hasLyrics = track.hasLyrics ||
              (downloads?.hasDownloadedLyrics(track.id) ?? false);
          return Row(
            children: [
              TrackBadge(
                hasLyrics: hasLyrics,
                isInstrumental: track.isInstrumental,
              ),
              Expanded(
                child: ArtistCreditLinks(
                  name: track.artist,
                  enabled: linksEnabled,
                  maxLines: 1,
                  onBeforeNavigate: widget.onBeforeNavigate,
                  style: TextStyle(
                    fontSize: style.subtitleSize,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      trailing: trailing,
    );
  }

  /// What rides under the cursor while a multi-selection is dragged: the songs
  /// themselves, in queue order, so the pile is literally what will be
  /// dropped. Long selections stop at [_kMaxPileRows] and count the rest —
  /// a fifty-row proxy would cover the window it is being dragged across.
  Widget _carriedPile(
    BuildContext context,
    PlayerApiClient? client,
    List<Track> upcoming,
  ) {
    final tracks = <Track>[
      for (final i in _carried)
        if (i >= 0 && i < upcoming.length) upcoming[i],
    ];
    final shown = tracks.take(_kMaxPileRows).toList(growable: false);
    final extra = tracks.length - shown.length;
    return Column(
      key: const ValueKey('queue-drag-pile'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final track in shown)
          _rowTile(context, client, track, linksEnabled: false),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              '+$extra more',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// How many songs a dragged pile shows before it starts counting instead.
const int _kMaxPileRows = 5;

/// Where a dragged block of [positions] lands, expressed in the list left
/// behind once every selected row is lifted out: the count of unselected rows
/// ahead of the drop. [newIndex] is what ReorderableListView reports, i.e. the
/// destination with only the dragged row removed.
@visibleForTesting
int queueBlockTarget(List<int> positions, int oldIndex, int newIndex) {
  final dropAt = newIndex >= oldIndex ? newIndex + 1 : newIndex;
  var target = 0;
  for (var i = 0; i < dropAt; i++) {
    if (!positions.contains(i)) target++;
  }
  return target;
}

/// Batch actions for a queue multi-selection, mirroring the verbs its
/// right-click menu offers. Moving is not among them: a selection is dragged
/// where it should go, whole.
class _QueueSelectionBar extends StatelessWidget {
  const _QueueSelectionBar({
    required this.tracks,
    required this.positions,
    required this.onDone,
  });

  final List<Track> tracks;
  final List<int> positions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final audio = context.read<AudioController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.surfaceHover,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '${positions.length} selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              const Spacer(),
              Builder(
                builder: (context) => _BarAction(
                  icon: Icons.playlist_add_rounded,
                  label: 'Playlists…',
                  onPressed: () async {
                    await showPlaylistsMenu(
                      context,
                      menuAnchorOf(context),
                      tracks,
                    );
                    onDone();
                  },
                ),
              ),
              _BarAction(
                icon: Icons.playlist_remove_rounded,
                label: 'Remove selected',
                onPressed: () => removeUpcomingWithUndo(
                  audio,
                  ScaffoldMessenger.maybeOf(context),
                  positions,
                  tracks,
                ),
              ),
              _BarAction(
                icon: Icons.close_rounded,
                label: 'Clear selection',
                onPressed: onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: context.colors.textPrimary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
    );
  }
}

/// Discoverability hint for the queue's header: dragging and the selection
/// modifiers are both invisible affordances, since a plain click still plays
/// the row.
String get queueSelectionHint =>
    defaultTargetPlatform == TargetPlatform.macOS
        ? 'Drag rows to reorder\nShift-click or ⌘-click to select several'
            '\nRight-click for more'
        : 'Drag rows to reorder\nShift-click or Ctrl-click to select several'
            '\nRight-click for more';
