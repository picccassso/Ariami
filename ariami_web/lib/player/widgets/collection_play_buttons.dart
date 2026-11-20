import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../theme/player_theme.dart';
import 'queue_intent.dart';

// The Play and Shuffle buttons at the top of a collection (album, playlist,
// All Songs).
//
// By default they always (re)start the collection. With
// AudioController.playButtonsFollowPlayback on they instead mirror the queue
// they started, Spotify-style: while this collection is what's playing, Play
// becomes Pause and Shuffle toggles the live queue's shuffle rather than
// reshuffling from scratch. Only the playing collection's buttons change —
// every other one keeps offering plain Play/Shuffle.
//
// Both widgets watch AudioController themselves, so a page can keep reading it
// (rather than watching) and avoid rebuilding its whole track list on every
// position tick.

/// True when these buttons should mirror the running queue instead of starting
/// a new one.
bool _mirrorsQueue(AudioController audio, String sourceId) =>
    audio.playButtonsFollowPlayback &&
    audio.sourceId == sourceId &&
    audio.currentTrack != null;

/// Loading counts as playing so a slow first stream doesn't flip the button
/// back to Play for a second after the user pressed it.
bool _sounding(AudioController audio) => audio.isPlaying || audio.isLoading;

/// Marks the dot that appears under a lit shuffle icon.
@visibleForTesting
const shuffleOnDotKey = Key('collection-shuffle-on-dot');

/// The shuffle glyph, with Spotify's dot underneath while shuffle is on.
///
/// The dot — not just the accent colour — is what carries the state: in the
/// neutral themes the accent *is* the primary text colour, so colour alone
/// would say nothing.
Widget _shuffleGlyph({
  required bool on,
  required Color color,
  required double size,
}) {
  final icon = Icon(Icons.shuffle_rounded, size: size);
  if (!on) return icon;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      icon,
      const SizedBox(height: 2),
      Container(
        key: shuffleOnDotKey,
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ],
  );
}

class CollectionPlayButton extends StatelessWidget {
  const CollectionPlayButton({
    super.key,
    required this.tracks,
    required this.sourceId,
    required this.noun,
  });

  /// The tracks to start when this is not already the playing collection.
  final List<Track> tracks;

  /// Namespaced key of this collection (see [AudioController.albumSource]).
  final String sourceId;

  final String noun;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final mirroring = _mirrorsQueue(audio, sourceId);
    final playing = mirroring && _sounding(audio);
    final enabled = mirroring || tracks.isNotEmpty;
    // A held modifier queues the collection rather than starting it, so the
    // button covers "play", "play after this" and "play next" on its own.
    final onPressed = !enabled
        ? null
        : () {
            if (applyQueueModifiers(context, tracks)) return;
            if (mirroring) {
              audio.togglePlayPause();
            } else {
              audio.playAll(tracks, sourceId: sourceId);
            }
          };
    final tooltip = (playing
            ? 'Pause'
            : mirroring
                ? 'Resume'
                : 'Play $noun') +
        (tracks.isEmpty ? '' : queueModifierHint);
    final icon = playing ? Icons.pause_rounded : Icons.play_arrow_rounded;

    return Tooltip(
      message: tooltip,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(playing ? 'Pause' : 'Play'),
      ),
    );
  }
}

class CollectionShuffleButton extends StatelessWidget {
  const CollectionShuffleButton({
    super.key,
    required this.tracks,
    required this.sourceId,
    required this.noun,
  });

  final List<Track> tracks;
  final String sourceId;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final mirroring = _mirrorsQueue(audio, sourceId);
    final isCurrent = audio.sourceId == sourceId && audio.currentTrack != null;
    // Lit while this collection is playing shuffled — the same accent-means-on
    // idiom the pin and repeat buttons use.
    final on = mirroring && audio.shuffle;
    final enabled = isCurrent || mirroring || tracks.isNotEmpty;
    final onPressed = !enabled
        ? null
        : mirroring
            ? audio.toggleShuffle
            : () => audio.playShuffled(tracks, sourceId: sourceId);
    final onSecondaryTap = !enabled
        ? null
        : () {
            if (isCurrent) {
              audio.reshuffleUpcoming();
            } else {
              audio.playShuffled(tracks, sourceId: sourceId);
            }
          };
    final tooltip = mirroring
        ? (on ? 'Turn shuffle off' : 'Turn shuffle on')
        : 'Shuffle $noun';
    final accent = Theme.of(context).colorScheme.secondary;

    final foreground = on ? accent : context.colors.textPrimary;
    final button = Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: foreground),
        icon: _shuffleGlyph(on: on, color: foreground, size: 18),
        label: const Text('Shuffle'),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTap: onSecondaryTap,
      child: button,
    );
  }
}
