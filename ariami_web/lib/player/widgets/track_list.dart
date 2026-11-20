import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/utils/format.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'artist_credit_links.dart';
import 'context_menu.dart';
import 'downloaded_badge.dart';
import 'hover_surface.dart';
import 'track_badge.dart';
import 'playing_indicator.dart';
import 'playlists_menu.dart';
import 'progress_fill.dart';
import 'queue_intent.dart';
import 'track_title_link.dart';

class TrackRow extends StatefulWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.context,
    this.sourceId,
    this.index,
    this.showArtwork = false,
    this.showAlbum = false,
    this.showGoToAlbum = true,
    this.linkTitleToAlbum = true,
    this.selected = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
    this.onPlayOverride,
    this.selectionActive = false,
    this.isChecked = false,
    this.onSelectTap,
    this.trailing,
    this.inRecentSearch = false,
    this.showInlinePlayingBars = false,
    this.lyricSnippet,
  });

  final Track track;

  /// The list this track belongs to (used as the play queue when tapped).
  final List<Track> context;

  /// The collection [context] came from (see [AudioController.albumSource]).
  /// Playing a row keeps it marked as the playing collection; null for lists
  /// that aren't one, like search results.
  final String? sourceId;

  /// 1-based index to show on the left (album/playlist views). Null hides it.
  final int? index;

  final bool showArtwork;
  final bool showAlbum;

  /// Whether the "Go to album" action appears in the right-click menu.
  /// Hidden when the row already lives inside that album's view.
  final bool showGoToAlbum;

  /// Whether tapping the title opens the track's album. Playlist views opt
  /// out so their titles stay non-navigational, and the album view opts out
  /// because the row already lives inside that album.
  final bool linkTitleToAlbum;

  /// Highlights this row as the keyboard selection (find-in-page ↑/↓) and
  /// keeps it scrolled into view.
  final bool selected;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  /// When set, replaces the default "play [track] within [context]" behavior
  /// (e.g. search results shouldn't queue up every match — just the one track).
  final void Function(Track track)? onPlayOverride;

  /// Whether the list is in multi-select mode. The index/play cell becomes a
  /// checkbox and a single click selects instead of doing nothing.
  final bool selectionActive;

  final bool isChecked;

  /// Called on a single click while [selectionActive]. Receives the modifier
  /// state so the list can implement shift-range and cmd/ctrl-toggle.
  final void Function({required bool shift, required bool meta})? onSelectTap;

  /// Optional trailing widget placed on the right of the duration (e.g. remove
  /// button in recent searches).
  final Widget? trailing;

  /// Whether this track was previously in the user's recent search history.
  final bool inRecentSearch;

  /// Whether to render equalizer bars inline next to the duration.
  final bool showInlinePlayingBars;

  /// Optional matched lyric line snippet displayed under the artist row.
  final String? lyricSnippet;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hover = false;

  /// Whether the pointer is over the hover play button rather than the rest of
  /// the row. The two want opposite things from the same modifiers — the
  /// button queues the track, the row extends a selection — so the row's
  /// selection handler stands down while the pointer is on the button.
  bool _overPlayButton = false;

  /// Whether the pointer is over the trailing action (e.g. remove from search).
  /// Disables double-tap playback on the row so rapid clicks on the trailing
  /// action clear items immediately without double-tap delay or playing.
  bool _overTrailing = false;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _revealRow();
  }

  @override
  void didUpdateWidget(TrackRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _revealRow();
  }

  /// Scrolls just enough to keep the keyboard-selected row on screen. The two
  /// alignment policies each only scroll when the row is past that edge, so a
  /// row already in view stays put.
  void _revealRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.selected) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  /// Starts or extends a selection on the way down.
  ///
  /// A modifier click works whether or not the list is already selecting —
  /// that is what lets cmd/shift-click turn the mode on. Unmodified clicks are
  /// only claimed once the mode is on, so outside it the row's normal gestures
  /// are untouched. cmd is the modifier on macOS and ctrl elsewhere: ctrl-click
  /// is the platform's secondary click on a Mac and already opens the context
  /// menu.
  void _handlePointerDown(PointerDownEvent event) {
    final onSelectTap = widget.onSelectTap;
    if (onSelectTap == null || _overPlayButton || _overTrailing) return;
    if (event.buttons & kPrimaryButton == 0) return;
    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final meta = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!widget.selectionActive && !shift && !meta) return;
    onSelectTap(shift: shift, meta: meta);
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe only to the two slices of AudioController this row cares about,
    // rather than watch()-ing the whole controller. The controller fires
    // notifyListeners() on every position tick (several times a second during
    // playback); watching it rebuilt every visible row on each tick. With
    // select() a row only rebuilds when it becomes / stops being the current
    // track, or when play/pause toggles.
    final isCurrent = context.select<AudioController, bool>(
      (a) => a.currentTrack?.id == widget.track.id,
    );
    final isPlaying = context.select<AudioController, bool>(
      (a) => a.isPlaying && a.currentTrack?.id == widget.track.id,
    );
    final client = context.read<ConnectionController>().client;
    // O(1) against the controller's cached index, and select() only rebuilds
    // the row when this song's downloaded state actually flips.
    final isDownloaded = maybeSelectProvider<PlayerDownloadsBridge?, bool>(
      context,
      (d) => d?.isDownloaded(widget.track.id) ?? false,
      fallback: false,
    );
    final hasLyrics = widget.track.hasLyrics ||
        maybeSelectProvider<PlayerDownloadsBridge?, bool>(
          context,
          (d) => d?.hasDownloadedLyrics(widget.track.id) ?? false,
          fallback: false,
        );
    // Offline, songs without a downloaded file can't play — dim them.
    final offline = context.select<ConnectionController, bool>(
      (c) => c.isOfflineActive,
    );
    final unavailableOffline = offline && !isDownloaded;
    final inPlaylist = context.select<LibraryController, bool>(
      (l) => l.playlistNamesContaining(widget.track.id).isNotEmpty,
    );
    final activeColor = Theme.of(context).colorScheme.secondary;
    void playTrack() {
      if (_overTrailing) return;
      if (applyKeepQueueModifier(context, widget.track)) return;
      final audio = context.read<AudioController>();
      if (widget.onPlayOverride != null) {
        widget.onPlayOverride!(widget.track);
      } else {
        audio.playTrack(
          widget.track,
          context: widget.context,
          sourceId: widget.sourceId,
        );
      }
    }

    // Rows can be dragged onto a playlist in the library sidebar to add the
    // track there (Spotify-style). Mouse drags don't scroll desktop lists and
    // the playlist reorder drag lives on its separate handle, so claiming the
    // pan gesture here conflicts with nothing.
    return Draggable<Track>(
      data: widget.track,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _TrackDragChip(track: widget.track),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        // Clearing the play-button and trailing flags here too.
        onExit: (_) => setState(() {
          _hover = false;
          _overPlayButton = false;
          _overTrailing = false;
        }),
        child: Listener(
          // Selection runs off the raw pointer-down, not a tap: a tap
          // recognizer sharing this detector with onDoubleTap would sit on
          // every click for the double-tap deadline before the row responded,
          // and cmd/shift-click has to work before selection mode even exists.
          onPointerDown: _handlePointerDown,
          child: GestureDetector(
            // While selecting, a double-click is two selection clicks, not a
            // play request.
            onDoubleTap: widget.selectionActive ? null : playTrack,
            onSecondaryTapDown: (details) => showTrackContextMenu(
              context,
              details.globalPosition,
              widget.track,
              showGoToAlbum: widget.showGoToAlbum,
              onMoveUp: widget.onMoveUp,
              onMoveDown: widget.onMoveDown,
              onRemove: widget.onRemove,
            ),
            child: Stack(
              children: [
                // The playing row fills with the sleeve tone as the song
                // plays, echoing the transport bar.
                if (isCurrent)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(PlayerTheme.cardRadius),
                        child: ProgressFill(
                          audio: context.read<AudioController>(),
                          fill: context.colors.fill,
                          ink: context.colors.textPrimary,
                          edge: false,
                        ),
                      ),
                    ),
                  ),
                HoverSurface(
                  active: _hover,
                  base: widget.selected || widget.isChecked
                      ? activeColor.withValues(alpha: 0.14)
                      : Colors.transparent,
                  highlight: context.colors.surfaceHover,
                  borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Opacity(
                    opacity: unavailableOffline ? 0.45 : 1,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: _LeadingCell(
                            selectionActive: widget.selectionActive,
                            isChecked: widget.isChecked,
                            hover: _hover,
                            isCurrent: isCurrent,
                            isPlaying: isPlaying,
                            index: widget.index,
                            onPlay: playTrack,
                            onPause: () =>
                                context.read<AudioController>().pause(),
                            onResume: () =>
                                context.read<AudioController>().resume(),
                            onQueueModifier: () => applyQueueModifiers(
                                context, <Track>[widget.track]),
                            onPlayButtonHover: (over) =>
                                setState(() => _overPlayButton = over),
                          ),
                        ),
                        if (widget.showArtwork) ...[
                          const SizedBox(width: 8),
                          ArtworkWithDownloadedBadge(
                            downloaded: isDownloaded,
                            inRecentSearch: widget.inRecentSearch,
                            artwork: Artwork(
                              client: client,
                              albumId: widget.track.albumId,
                              songId: widget.track.albumId == null
                                  ? widget.track.id
                                  : null,
                              size: 40,
                              deferDuringScroll: true,
                            ),
                          ),
                        ],
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TrackTitleLink(
                                title: widget.track.title,
                                albumId: widget.track.albumId,
                                // While selecting, the title must not stay a link —
                                // it would eat the click that selects the row.
                                enabled: widget.linkTitleToAlbum &&
                                    !widget.selectionActive,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  TrackBadge(
                                    hasLyrics: hasLyrics,
                                    isInstrumental: widget.track.isInstrumental,
                                  ),
                                  Expanded(
                                    child: ArtistCreditLinks(
                                      name: widget.track.artist,
                                      // While selecting, the artist and album must not
                                      // stay links — they would eat the click that selects
                                      // the row.
                                      enabled: !widget.selectionActive,
                                      albumTitle: widget.showAlbum
                                          ? widget.track.albumTitle
                                          : null,
                                      albumId: widget.showAlbum
                                          ? widget.track.albumId
                                          : null,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.lyricSnippet != null &&
                                  widget.lyricSnippet!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '“${widget.lyricSnippet}”',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontStyle: FontStyle.italic,
                                    color: context.colors.textSecondary
                                        .withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Rows without artwork have no corner to badge, so the
                        // downloaded check sits inline next to the duration.
                        if (isDownloaded && !widget.showArtwork) ...[
                          Icon(
                            Icons.download_done_rounded,
                            size: 15,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 4),
                        ],
                        // Always shown once the song is in a playlist, so the
                        // tick doubles as a marker; otherwise only on hover.
                        SizedBox(
                          width: 32,
                          child:
                              inPlaylist || (_hover && !widget.selectionActive)
                                  ? IgnorePointer(
                                      ignoring: widget.selectionActive,
                                      child: PlaylistsButton(
                                        track: widget.track,
                                        iconSize: 18,
                                      ),
                                    )
                                  : null,
                        ),
                        _TrackActions(
                          track: widget.track,
                          // Hidden while selecting: a pointer-down landing on one
                          // of these would toggle the row underneath it too.
                          visible: !widget.selectionActive,
                          onMoveUp: widget.onMoveUp,
                          onMoveDown: widget.onMoveDown,
                          onRemove: widget.onRemove,
                        ),
                        // Reserve the bars' slot on every row (same trick as
                        // _TrackActions) so the playlist button, duration and
                        // trailing actions don't shift when a song starts playing.
                        if (widget.showInlinePlayingBars) ...[
                          const SizedBox(width: 8),
                          SizedBox.square(
                            dimension: 14,
                            child: isCurrent
                                ? PlayingBars(
                                    playing: isPlaying,
                                    color: activeColor,
                                    size: 14,
                                  )
                                : null,
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          formatClockDuration(widget.track.duration),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (widget.trailing != null) ...[
                          const SizedBox(width: 8),
                          MouseRegion(
                            onEnter: (_) => _overTrailing = true,
                            onExit: (_) => _overTrailing = false,
                            child: Listener(
                              onPointerDown: (_) => _overTrailing = true,
                              child: widget.trailing!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackDragChip extends StatelessWidget {
  const _TrackDragChip({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    // Nudged away from the pointer so the cursor doesn't cover the label.
    return Transform.translate(
      offset: const Offset(14, 12),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: context.colors.popover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded,
                    size: 16, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${track.title} — ${track.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingCell extends StatelessWidget {
  const _LeadingCell({
    required this.hover,
    required this.isCurrent,
    required this.isPlaying,
    required this.index,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onQueueModifier,
    required this.onPlayButtonHover,
    this.selectionActive = false,
    this.isChecked = false,
  });

  final bool selectionActive;
  final bool isChecked;
  final bool hover;
  final bool isCurrent;
  final bool isPlaying;
  final int? index;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;

  /// Queues the track when a modifier is held; returns whether it did, so an
  /// unmodified click falls through to the transport action.
  final bool Function() onQueueModifier;

  /// Reports whether the pointer is over the play button, so the row can leave
  /// its modifier clicks alone.
  final ValueChanged<bool> onPlayButtonHover;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    // In selection mode the cell is a checkbox at all times — including on
    // hover, where a play button would otherwise invite a click that selects.
    if (selectionActive) {
      return Center(
        child: Icon(
          isChecked
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 19,
          color: isChecked ? accent : context.colors.textSecondary,
        ),
      );
    }
    if (hover) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onPlayButtonHover(true),
        onExit: (_) => onPlayButtonHover(false),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          iconSize: 18,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow_rounded),
          color: context.colors.textPrimary,
          onPressed: () {
            if (onQueueModifier()) return;
            if (!isCurrent) {
              onPlay();
            } else if (isPlaying) {
              onPause();
            } else {
              onResume();
            }
          },
        ),
      );
    }
    if (isCurrent) {
      return Center(
        child: PlayingBars(playing: isPlaying, color: accent, size: 16),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        index != null ? '$index' : '',
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.track,
    required this.visible,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
  });
  final Track track;
  final bool visible;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // The button is always shown, so every row constructs the PopupMenuButton.
    // Rows in selection mode reserve the same-width slot with a cheap SizedBox
    // instead, so the duration column never shifts when selection starts/stops.
    if (!visible) return const SizedBox(width: 32, height: 18);
    final audio = context.read<AudioController>();
    return SizedBox(
      width: 32,
      child: PopupMenuButton<String>(
        tooltip: 'More',
        iconSize: 18,
        padding: EdgeInsets.zero,
        color: context.colors.popover,
        icon:
            Icon(Icons.more_horiz_rounded, color: context.colors.textSecondary),
        onSelected: (value) {
          switch (value) {
            case 'next':
              final nextAt = audio.playNext(<Track>[track]);
              showQueueAdditionToast(
                context,
                message: 'Playing next',
                firstPosition: nextAt,
              );
              break;
            case 'keep':
              final playedAt = audio.playNowKeepingQueue(track);
              showQueueAdditionToast(
                context,
                message: 'Playing now',
                firstPosition: playedAt,
              );
              break;
            case 'queue':
              final queuedAt = audio.addToQueue(<Track>[track]);
              showQueueAdditionToast(
                context,
                message: 'Added to end of queue',
                firstPosition: queuedAt,
              );
              break;
            case 'up':
              onMoveUp?.call();
              break;
            case 'down':
              onMoveDown?.call();
              break;
            case 'remove':
              onRemove?.call();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'next', child: Text('Play next')),
          const PopupMenuItem(
            value: 'keep',
            child: Text('Play now, keep queue'),
          ),
          const PopupMenuItem(
              value: 'queue', child: Text('Add to end of queue')),
          if (onMoveUp != null || onMoveDown != null || onRemove != null)
            const PopupMenuDivider(),
          if (onMoveUp != null)
            const PopupMenuItem(value: 'up', child: Text('Move up')),
          if (onMoveDown != null)
            const PopupMenuItem(value: 'down', child: Text('Move down')),
          if (onRemove != null)
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove from playlist'),
            ),
        ],
      ),
    );
  }
}
