import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import 'queue_intent.dart';

const _transportSeekStep = Duration(seconds: 10);
const _transportVolumeStep = 0.05;

/// Shared transport shortcuts: space toggles play/pause, ←/→ seek ±10s and
/// ↑/↓ nudge the volume. Used by the shell and the fullscreen player (a
/// root-navigator route that takes focus away from the shell's handler, so
/// it must bind these itself). Callers apply their own guards (text-editing
/// focus, modifier shortcuts) before delegating.
KeyEventResult handleTransportKey(AudioController audio, KeyEvent event) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;

  if (key == LogicalKeyboardKey.space) {
    // Held space must not machine-gun play/pause.
    if (event is! KeyRepeatEvent) audio.togglePlayPause();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowLeft) {
    if (audio.currentTrack == null) return KeyEventResult.ignored;
    final back = key == LogicalKeyboardKey.arrowLeft;
    var target = back
        ? audio.position - _transportSeekStep
        : audio.position + _transportSeekStep;
    if (target < Duration.zero) target = Duration.zero;
    final duration = audio.duration;
    if (duration != null && target > duration) target = duration;
    audio.seek(target);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    final delta = key == LogicalKeyboardKey.arrowUp
        ? _transportVolumeStep
        : -_transportVolumeStep;
    audio.setVolume(audio.volume + delta);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Loads an album's tracks and starts playback — or, when a queue modifier is
/// held, appends them to the queue instead (see [readQueueIntent]).
Future<void> playAlbum(
  BuildContext context,
  String albumId, {
  int startIndex = 0,
}) async {
  // Captured before the detail request: the keys are long released by the
  // time it comes back.
  final intent = readQueueIntent();
  final library = context.read<LibraryController>();
  final audio = context.read<AudioController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final detail = await library.albumDetail(albumId);
    if (detail.tracks.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('This album has no playable tracks.')),
      );
      return;
    }
    if (!context.mounted) return;
    if (applyQueueIntent(context, intent, detail.tracks)) return;
    await audio.playAll(
      detail.tracks,
      startIndex: startIndex,
      sourceId: AudioController.albumSource(albumId),
    );
  } catch (e) {
    messenger
        ?.showSnackBar(SnackBar(content: Text('Could not play album: $e')));
  }
}

/// Starts the whole library — or queues it when a queue modifier is held (see
/// [readQueueIntent]). Unlike [playAlbum] and [playPlaylist] there is no
/// async gap: the songs are already in memory.
Future<void> playAllSongs(BuildContext context) async {
  final intent = readQueueIntent();
  final library = context.read<LibraryController>();
  final audio = context.read<AudioController>();
  final tracks = library.songs;
  if (tracks.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Nothing to play yet.')),
    );
    return;
  }
  if (applyQueueIntent(context, intent, tracks)) return;
  await audio.playAll(tracks, sourceId: AudioController.allSongsSource);
}

/// Starts an artist's songs — or queues them when a queue modifier is held
/// (see [readQueueIntent]). Like [playAllSongs] there is no async gap: the
/// songs are already in memory.
Future<void> playArtist(BuildContext context, String name) async {
  final intent = readQueueIntent();
  final library = context.read<LibraryController>();
  final audio = context.read<AudioController>();
  final tracks = library.artistTracks(name);
  if (tracks.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('This artist has no playable tracks.')),
    );
    return;
  }
  if (applyQueueIntent(context, intent, tracks)) return;
  await audio.playAll(tracks, sourceId: AudioController.artistSource(name));
}

/// Resolves a playlist's tracks and starts playback — or queues them when a
/// modifier is held (see [readQueueIntent]).
Future<void> playPlaylist(
  BuildContext context,
  PlaylistSummary playlist, {
  int startIndex = 0,
}) async {
  final intent = readQueueIntent();
  final library = context.read<LibraryController>();
  final audio = context.read<AudioController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final tracks = library.playlistTracks(playlist);
    if (tracks.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('This playlist has no playable tracks.')),
      );
      return;
    }
    if (applyQueueIntent(context, intent, tracks)) return;
    await audio.playAll(
      tracks,
      startIndex: startIndex,
      sourceId: AudioController.playlistSource(playlist.id),
    );
  } catch (e) {
    messenger
        ?.showSnackBar(SnackBar(content: Text('Could not play playlist: $e')));
  }
}

Future<void> enqueueTrackDownloads(
  BuildContext context,
  List<Track> tracks,
) async {
  final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
      maybeReadProvider<PlayerDownloadsBridge>(context);
  if (downloads == null) return;
  if (!downloads.hasClient) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Downloading needs a server connection.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }
  final library = context.read<LibraryController>();
  final albumArtists = <String, String>{
    for (final album in library.albums) album.id: album.artist,
  };
  final added = downloads.enqueueTracks(tracks, albumArtists: albumArtists);
  if (!context.mounted) return;
  final message = added == 0
      ? (tracks.length == 1
          ? 'Already downloaded'
          : 'Already downloaded or queued')
      : 'Added $added ${added == 1 ? 'song' : 'songs'} to downloads';
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
