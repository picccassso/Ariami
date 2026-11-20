import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/utils/format.dart';

import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/lyrics_controller.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'ariami_connect_sheet.dart';
import 'artist_credit_links.dart';
import 'context_menu.dart';
import 'hover_slider.dart';
import 'liked_song_button.dart';
import 'playlists_menu.dart';
import 'progress_fill.dart';
import 'seek_slider.dart';
import 'now_playing_full_view.dart';
import 'track_title_link.dart';

/// The transport strip along the window's bottom edge. The strip itself is
/// the progress bar: its ground fills with the sleeve tone as the song plays.
/// Seeking is confined to a thin strip along its top edge, above the
/// controls, so a slightly missed click on a button never seeks and a seek
/// never lands on a button.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.band,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 76,
            child: ProgressBand(
              audio: audio,
              seekStripHeight: 12,
              child: _PlayerBarBody(audio: audio),
            ),
          ),
          if (audio.autoplayBlocked)
            _AutoplayBlockedBanner(
              onResume: () => audio.resume(),
              onDismiss: audio.dismissAutoplayBlocked,
            ),
          if (audio.isRemoteActive)
            _RemotePlaybackBanner(
              deviceName: audio.remoteCastDeviceName == null
                  ? audio.remoteDeviceName ?? 'device'
                  : '${audio.remoteCastDeviceName} via '
                      '${audio.remoteDeviceName ?? 'device'}',
              icon: audio.remoteCastDeviceName == null
                  ? Icons.volume_up_rounded
                  : Icons.cast_connected_rounded,
            )
          else if (audio.isCastActive)
            _RemotePlaybackBanner(
              deviceName: audio.castDeviceName ?? 'Google Cast',
              icon: Icons.cast_connected_rounded,
            ),
        ],
      ),
    );
  }
}

class _AutoplayBlockedBanner extends StatelessWidget {
  const _AutoplayBlockedBanner({
    required this.onResume,
    required this.onDismiss,
  });

  final VoidCallback onResume;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_off_rounded, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Browser blocked autoplay — click Play to resume listening.',
              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
            ),
          ),
          TextButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Play'),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A progress fill: [PlayerColors.fill] up to the playhead, with an ink edge
/// at the playhead. Paints straight from [AudioController.progress], so
/// playback never rebuilds a widget.
///
/// Clicking or dragging seeks — across the whole band, or, when
/// [seekStripHeight] is set, only within a strip that tall along its top
/// edge, where a visible seek bar shows the playhead (see
/// [ProgressFillPainter.hoverBand]).
class ProgressBand extends StatefulWidget {
  const ProgressBand({
    super.key,
    required this.audio,
    this.seekStripHeight,
    this.child,
  });

  final AudioController audio;
  final double? seekStripHeight;

  /// Content laid over the fill and under the seek strip — the transport's
  /// controls. The strip sits on top so no control's hit area (the volume
  /// slider's reaches well beyond its track) can swallow a seek.
  final Widget? child;

  @override
  State<ProgressBand> createState() => _ProgressBandState();
}

class _ProgressBandState extends State<ProgressBand> {
  /// The drag position as a fraction of the bar, while scrubbing.
  double? _drag;

  /// The pointer position as a fraction of the bar, while hovering.
  double? _hover;

  double _fraction(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _seek(double fraction) {
    final total = widget.audio.duration ?? Duration.zero;
    if (total <= Duration.zero) return;
    widget.audio.seek(total * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    final colors = context.colors;
    final strip = widget.seekStripHeight;
    final seekable = (audio.duration ?? Duration.zero) > Duration.zero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final seekZone = Semantics(
          slider: true,
          label: 'Seek',
          value: formatClockDuration(audio.position),
          child: MouseRegion(
            cursor:
                seekable ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onHover: seekable
                ? (e) =>
                    setState(() => _hover = _fraction(e.localPosition, width))
                : null,
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: seekable
                  ? (d) => _seek(_fraction(d.localPosition, width))
                  : null,
              onHorizontalDragStart: seekable
                  ? (d) =>
                      setState(() => _drag = _fraction(d.localPosition, width))
                  : null,
              onHorizontalDragUpdate: seekable
                  ? (d) =>
                      setState(() => _drag = _fraction(d.localPosition, width))
                  : null,
              onHorizontalDragEnd: seekable
                  ? (_) {
                      final drag = _drag;
                      setState(() => _drag = null);
                      if (drag != null) _seek(drag);
                    }
                  : null,
              child: const SizedBox.expand(),
            ),
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            ProgressFill(
              audio: audio,
              drag: _drag,
              hover: _hover,
              hoverBand: strip,
              fill: colors.fill,
              ink: colors.textPrimary,
              ground: colors.base,
            ),
            if (widget.child != null) widget.child!,
            if (strip == null)
              seekZone
            else
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: strip,
                child: seekZone,
              ),
          ],
        );
      },
    );
  }
}

/// Strip below the transport bar while another Connect device or Cast device
/// is playing; tapping it opens the device picker.
class _RemotePlaybackBanner extends StatelessWidget {
  const _RemotePlaybackBanner({
    required this.deviceName,
    this.icon = Icons.volume_up_rounded,
  });

  final String deviceName;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.textPrimary,
      child: InkWell(
        onTap: () => showAriamiConnectSheet(context),
        child: SizedBox(
          height: 26,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, size: 14, color: colors.base),
              const SizedBox(width: 6),
              Text(
                'Playing on $deviceName',
                style: TextStyle(
                  color: colors.base,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerBarBody extends StatefulWidget {
  const _PlayerBarBody({required this.audio});
  final AudioController audio;

  @override
  State<_PlayerBarBody> createState() => _PlayerBarBodyState();
}

class _PlayerBarBodyState extends State<_PlayerBarBody> {
  /// Hovering the cover underlines the title, so the pair reads as one link.
  bool _artHover = false;

  AudioController get audio => widget.audio;

  @override
  Widget build(BuildContext context) {
    final client = context.read<ConnectionController>().client;
    final track = audio.currentTrack;
    final colors = context.colors;
    // Selects, not watches: the bar must not rebuild on every navigation or
    // download progress tick.
    final panelOpen =
        context.select<PlayerNavigator, bool>((n) => n.rightPanelOpen);
    final (hasLyrics, lyricsActive) =
        context.select<LyricsController?, (bool, bool)>(
            (c) => (c?.hasLyrics ?? false, c?.isLyricsActive ?? false));
    final showingLyrics = panelOpen && lyricsActive;
    final showingQueue = panelOpen && !lyricsActive;

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final medium = constraints.maxWidth < 1050;
          final leftWidth =
              compact ? (track == null ? 0.0 : 52.0) : (medium ? 220.0 : 320.0);
          // Room for Connect, Lyrics and Up next; wide adds the clock and
          // volume.
          final rightWidth = compact ? 152.0 : (medium ? 190.0 : 330.0);
          return Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: AnimatedSwitcher(
                  duration: Motion.medium,
                  switchInCurve: Motion.standard,
                  transitionBuilder: Motion.fadeSlideUp,
                  child: track == null
                      ? const SizedBox.shrink(key: ValueKey('no-track'))
                      : GestureDetector(
                          key: ValueKey(track.id),
                          onSecondaryTapDown: (details) => showTrackContextMenu(
                            context,
                            details.globalPosition,
                            track,
                          ),
                          child: Row(
                            children: [
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) =>
                                    setState(() => _artHover = true),
                                onExit: (_) =>
                                    setState(() => _artHover = false),
                                child: GestureDetector(
                                  onTap: () => showFullNowPlaying(context),
                                  child: Artwork(
                                    client: client,
                                    albumId: track.albumId,
                                    songId:
                                        track.albumId == null ? track.id : null,
                                    size: 48,
                                    borderRadius: PlayerTheme.coverRadius,
                                  ),
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TrackTitleLink(
                                        title: track.title,
                                        albumId: track.albumId,
                                        marquee: true,
                                        forceUnderline: _artHover,
                                        style: PlayerTheme.heading(16),
                                      ),
                                      const SizedBox(height: 1),
                                      ArtistCreditLinks(
                                        name: track.artist,
                                        maxLines: 1,
                                        marquee: true,
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                LikedSongButton(track: track, iconSize: 20),
                                PlaylistsButton(track: track),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
              Expanded(child: Center(child: _TransportControls(audio: audio))),
              SizedBox(
                width: rightWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!medium) ...[
                      // The one flexible piece: it gives way first.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Clock(audio: audio),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const AriamiConnectButton(),
                    TransportToggle(
                      tooltip: 'Lyrics',
                      icon: Icons.lyrics_outlined,
                      active: showingLyrics,
                      onPressed: hasLyrics
                          ? () => _toggleRightPanelView(context, lyrics: true)
                          : null,
                    ),
                    TransportToggle(
                      tooltip: 'Up next',
                      icon: Icons.queue_music_rounded,
                      active: showingQueue,
                      onPressed: () =>
                          _toggleRightPanelView(context, lyrics: false),
                    ),
                    if (!medium) VolumeControl(audio: audio, sliderWidth: 96),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows the right panel on lyrics or the queue, or closes it when that view
/// is already showing. The lyrics choice is shared with the fullscreen player.
void _toggleRightPanelView(BuildContext context, {required bool lyrics}) {
  final navigator = context.read<PlayerNavigator>();
  final controller = context.read<LyricsController?>();
  final showingLyrics = controller?.isLyricsActive ?? false;
  if (navigator.rightPanelOpen && showingLyrics == lyrics) {
    if (lyrics) controller?.setLyricsPreferred(false);
    navigator.toggleRightPanel();
    return;
  }
  controller?.setLyricsPreferred(lyrics);
  if (!navigator.rightPanelOpen) navigator.toggleRightPanel();
}

/// Elapsed / total, in tabular figures so the digits don't jitter.
class _Clock extends StatelessWidget {
  const _Clock({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const base = TextStyle(fontSize: 13, fontFeatures: PlayerTheme.tabular);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PositionClock(
          audio: audio,
          style: base.copyWith(color: colors.textPrimary),
        ),
        Text(
          ' / ${formatClockDuration(audio.duration ?? Duration.zero)}',
          style: base.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// An icon toggle: ink with a dot beneath while on, pencil while off — there
/// is no accent colour to mark it.
class TransportToggle extends StatelessWidget {
  const TransportToggle({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.size = 20,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: tooltip,
          isSelected: active,
          icon: Icon(icon, size: size),
          color: active ? colors.textPrimary : colors.textSecondary,
          onPressed: onPressed,
        ),
        if (active)
          Positioned(
            bottom: 4,
            child: IgnorePointer(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasTrack = audio.currentTrack != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TransportToggle(
          tooltip: 'Shuffle',
          icon: Icons.shuffle_rounded,
          active: audio.shuffle,
          onPressed: hasTrack ? audio.toggleShuffle : null,
        ),
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.skip_previous_rounded, size: 26),
          color: colors.textPrimary,
          onPressed: hasTrack ? audio.previous : null,
        ),
        const SizedBox(width: 6),
        _PlayPauseButton(audio: audio),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.skip_next_rounded, size: 26),
          color: colors.textPrimary,
          onPressed: hasTrack && audio.hasNext ? audio.next : null,
        ),
        TransportToggle(
          tooltip: 'Repeat',
          icon: audio.repeat == PlayerRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          active: audio.repeat != PlayerRepeatMode.off,
          onPressed: hasTrack ? audio.cycleRepeat : null,
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasTrack = audio.currentTrack != null;
    final Widget inner;
    if (audio.isLoading) {
      inner = SizedBox(
        key: const ValueKey('loading'),
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(colors.base),
        ),
      );
    } else {
      inner = Icon(
        audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(audio.isPlaying ? 'pause' : 'play'),
        color: colors.base,
        size: 24,
      );
    }

    return Tooltip(
      message: audio.isPlaying ? 'Pause' : 'Play',
      child: Material(
        color: hasTrack
            ? colors.textPrimary
            : colors.textPrimary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          mouseCursor:
              hasTrack ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onTap: hasTrack ? audio.togglePlayPause : null,
          child: SizedBox(
            width: 48,
            height: 40,
            child: Center(
              child: AnimatedSwitcher(
                duration: Motion.fast,
                transitionBuilder: Motion.fadeScale,
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
