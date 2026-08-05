import 'package:flutter/material.dart';

import '../services/audio/play_buttons_follow_playback_service.dart';
import '../services/playback_manager.dart';

// The Play and Shuffle buttons at the top of an album or playlist.
//
// By default they always (re)start the collection, which is what the callbacks
// passed in do. With PlayButtonsFollowPlaybackService enabled they instead
// mirror the queue they started: while this collection is what's playing, Play
// becomes Pause and Shuffle toggles the live queue's shuffle. Only the playing
// collection's buttons change; every other one keeps plain Play/Shuffle.
//
// Because sourceId is published over Ariami Connect, this also reflects the
// collection playing on another device.

/// Marks the dot shown under a lit shuffle icon.
@visibleForTesting
const shuffleOnDotKey = Key('collection-shuffle-on-dot');

/// True when these buttons should mirror the running queue instead of
/// starting a new one.
bool _mirrorsQueue(PlaybackManager playback, String sourceId) =>
    PlayButtonsFollowPlaybackService().isEnabled &&
    playback.sourceId == sourceId &&
    playback.currentSong != null;

/// Rebuilds on both playback changes and preference changes.
Widget _listening(Widget Function(BuildContext, PlaybackManager) build) {
  final playback = PlaybackManager();
  return ListenableBuilder(
    listenable: Listenable.merge(
      [playback, PlayButtonsFollowPlaybackService()],
    ),
    builder: (context, _) => build(context, playback),
  );
}

/// The large round play button.
class CollectionPlayButton extends StatelessWidget {
  const CollectionPlayButton({
    super.key,
    required this.sourceId,
    required this.onPlay,
  });

  /// Namespaced key of this collection (see [PlaybackManager.albumSource]).
  final String sourceId;

  /// Starts the collection. Null when there is nothing to play.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => _listening((context, playback) {
        final scheme = Theme.of(context).colorScheme;
        final mirroring = _mirrorsQueue(playback, sourceId);
        // Loading counts as playing so a slow first stream doesn't flip the
        // button back to Play for a moment after it was pressed.
        final playing = mirroring && (playback.isPlaying || playback.isLoading);
        final enabled = mirroring || onPlay != null;
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
          ),
          child: IconButton(
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            color: scheme.onPrimary,
            iconSize: 36,
            tooltip: playing
                ? 'Pause'
                : mirroring
                    ? 'Resume'
                    : null,
            onPressed: !enabled
                ? null
                : mirroring
                    ? playback.togglePlayPause
                    : onPlay,
          ),
        );
      });
}

/// The shuffle button beside it.
class CollectionShuffleButton extends StatelessWidget {
  const CollectionShuffleButton({
    super.key,
    required this.sourceId,
    required this.onShuffle,
  });

  final String sourceId;

  /// Starts the collection shuffled. Null when there is nothing to play.
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) => _listening((context, playback) {
        final scheme = Theme.of(context).colorScheme;
        final mirroring = _mirrorsQueue(playback, sourceId);
        final on = mirroring && playback.isShuffleEnabled;
        final enabled = mirroring || onShuffle != null;
        final icon = const Icon(Icons.shuffle_rounded);
        return IconButton(
          // The icon is already accent-coloured when shuffle is off, so a dot
          // underneath — not the colour — is what marks it as on.
          icon: !on
              ? icon
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 2),
                    Container(
                      key: shuffleOnDotKey,
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
          iconSize: 28,
          color: scheme.primary,
          tooltip: mirroring ? (on ? 'Shuffle off' : 'Shuffle on') : null,
          onPressed: !enabled
              ? null
              : mirroring
                  ? playback.toggleShuffle
                  : onShuffle,
        );
      });
}
