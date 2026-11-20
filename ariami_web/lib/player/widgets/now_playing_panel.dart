import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/lyrics_controller.dart';
import '../services/player_navigator.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'lyrics_view.dart';
import 'now_playing_full_view.dart';
import 'playing_indicator.dart';
import 'progress_fill.dart';
import 'queue_list.dart';
import 'shell_column_header.dart';

/// The shell's right-hand column: what plays next, or the lyrics. The current
/// song itself lives on the transport bar and the home page, so this column
/// is only the list.
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final lyricsController = context.read<LyricsController?>();
    final (hasLyrics, showLyrics) =
        context.select<LyricsController?, (bool, bool)>(
            (c) => (c?.hasLyrics ?? false, c?.isLyricsActive ?? false));
    final track = audio.currentTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShellColumnHeader(
          padding: const EdgeInsets.only(left: 20, right: 8),
          children: [
            ShellTab(
              label: 'Up next',
              selected: !showLyrics,
              onTap: () => lyricsController?.setLyricsPreferred(false),
            ),
            if (hasLyrics) ...[
              const SizedBox(width: 20),
              ShellTab(
                label: 'Lyrics',
                selected: showLyrics,
                onTap: () => lyricsController?.setLyricsPreferred(true),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Hide panel',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () =>
                  context.read<PlayerNavigator>().toggleRightPanel(),
            ),
          ],
        ),
        Expanded(
          child: track == null
              ? const _PanelNote('Nothing playing. Pick an album or song.')
              : AnimatedSwitcher(
                  duration: Motion.medium,
                  transitionBuilder: Motion.fadeThrough,
                  child: showLyrics
                      ? const LyricsView(key: ValueKey('lyrics'), compact: true)
                      : const _QueueSection(key: ValueKey('queue')),
                ),
        ),
      ],
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final upcoming = audio.upcoming;
    final source = audio.currentTrack?.albumTitle;
    final small = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: context.colors.textSecondary,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: queueSelectionHint,
                  child: Text(
                    source != null
                        ? 'From $source'
                        : '${upcoming.length + 1} songs',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              if (upcoming.length > 1)
                TextButton(
                  style: small,
                  onPressed: () => audio.reshuffleUpcoming(),
                  child: const Text('Reshuffle'),
                ),
              if (upcoming.isNotEmpty)
                TextButton(
                  style: small,
                  onPressed: () => audio.clearUpcoming(),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        _CurrentRow(audio: audio),
        if (upcoming.isEmpty)
          const _PanelNote('Nothing queued after this song.')
        else
          const QueueList(
            keyPrefix: 'main-queue',
            maxRows: 50,
            nested: true,
          ),
      ],
    );
  }
}

/// The playing song, heading the queue it belongs to: laid out like the
/// numbered rows beneath it, with playing bars in place of a number and the
/// sleeve-tone fill sweeping across it as it plays.
class _CurrentRow extends StatelessWidget {
  const _CurrentRow({required this.audio});

  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final track = audio.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final colors = context.colors;
    final client = context.read<ConnectionController>().client;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showFullNowPlaying(context),
      onSecondaryTapDown: (details) =>
          showTrackContextMenu(context, details.globalPosition, track),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          children: [
            Positioned.fill(
              child: ProgressFill(
                audio: audio,
                fill: colors.fill,
                ink: colors.textPrimary,
                edge: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 9, 8, 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PlayingBars(
                        playing: audio.isPlaying,
                        color: colors.textPrimary,
                        size: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Artwork(
                    client: client,
                    albumId: track.albumId,
                    songId: track.albumId == null ? track.id : null,
                    size: QueueListStyle.panel.artworkSize,
                    iconScale: 0.42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: QueueListStyle.panel.titleSize,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: QueueListStyle.panel.subtitleSize,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13.5),
        ),
      );
}
