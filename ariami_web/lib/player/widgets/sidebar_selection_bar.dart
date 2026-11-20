import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';
import 'hidden_actions.dart';
import 'playback_helpers.dart';
import 'queue_intent.dart';
import 'track_selection_bar.dart';

/// Floating action bar for a sidebar multi-selection: the verbs a single
/// collection's right-click menu offers, applied to every selected album,
/// playlist and artist at once.
///
/// Like the track bar, every action ends by dismissing the selection — the
/// batch is done, and leaving it up invites a second accidental Download over
/// the same collections.
class SidebarSelectionBar extends StatelessWidget {
  const SidebarSelectionBar({
    super.key,
    required this.selectedKeys,
    required this.onSelectAll,
    required this.onDone,
  });

  /// Selected entries as `type:targetId`, in the order the sidebar lists them.
  final List<String> selectedKeys;
  final VoidCallback onSelectAll;
  final VoidCallback onDone;

  List<HideTarget> get _targets => [
        for (final key in selectedKeys)
          if (parseHideTarget(key) case final target?) target,
      ];

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final count = targets.length;
    final enabled = count > 0;
    // Downloads only exist when playing from a remote server — when this
    // computer hosts the library the files are already on its disk. The same
    // rule the collection menu and the track bar follow.
    final canDownload =
        !context.select<ConnectionController, bool>((c) => c.isLocalServer) &&
            (maybeReadProvider<PlayerDownloadsBridge?>(context) ??
                    maybeReadProvider<PlayerDownloadsBridge>(context)) !=
                null;
    // Artists aren't a pinnable type server-side, so Pin only appears when the
    // selection actually contains something that can be pinned.
    final pinnable = targets
        .where((target) => target.type != HiddenMediaItem.artistType)
        .toList(growable: false);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: context.colors.popover,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 0 ? 'Select from your library' : '$count selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                SelectionBarAction(
                  icon: Icons.select_all_rounded,
                  label: 'Select all',
                  onPressed: onSelectAll,
                ),
                const SelectionBarDivider(),
                SelectionBarAction(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play now',
                  onPressed: enabled
                      ? () => _withTracks(context, targets, (audio, tracks) {
                            // No sourceId: an ad-hoc selection is not a
                            // collection, so nothing should light up as
                            // "now playing from".
                            audio.playAll(tracks);
                            return -1;
                          })
                      : null,
                ),
                SelectionBarAction(
                  icon: Icons.playlist_play_rounded,
                  label: 'Play next',
                  onPressed: enabled
                      ? () => _withTracks(context, targets,
                            (audio, tracks) => audio.playNext(tracks),
                          toast: 'Playing next')
                      : null,
                ),
                SelectionBarAction(
                  icon: Icons.queue_music_rounded,
                  label: 'Add to end of queue',
                  onPressed: enabled
                      ? () => _withTracks(context, targets,
                            (audio, tracks) => audio.addToQueue(tracks),
                          toast: 'Added to end of queue')
                      : null,
                ),
                if (canDownload)
                  SelectionBarAction(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    onPressed: enabled
                        ? () async {
                            final tracks =
                                await resolveSelectionTracks(context, targets);
                            if (!context.mounted || tracks == null) return;
                            await enqueueTrackDownloads(context, tracks);
                            onDone();
                          }
                        : null,
                  ),
                if (pinnable.isNotEmpty)
                  SelectionBarAction(
                    icon: Icons.push_pin_rounded,
                    label: 'Pin',
                    onPressed: () async {
                      final library = context.read<LibraryController>();
                      for (final target in pinnable) {
                        final alreadyPinned =
                            target.type == HiddenMediaItem.albumType
                                ? library.isAlbumPinned(target.targetId)
                                : library.isPlaylistPinned(target.targetId);
                        // Pin, never unpin: across a mixed selection a toggle
                        // would unpin whatever was already pinned.
                        if (alreadyPinned) continue;
                        if (target.type == HiddenMediaItem.albumType) {
                          await library.toggleAlbumPin(target.targetId);
                        } else {
                          await library.togglePlaylistPin(target.targetId);
                        }
                      }
                      onDone();
                    },
                  ),
                const SelectionBarDivider(),
                SelectionBarAction(
                  icon: Icons.visibility_off_rounded,
                  label: 'Remove from my library',
                  onPressed: enabled
                      ? () async {
                          await hideCollections(context, targets);
                          onDone();
                        }
                      : null,
                ),
                const SelectionBarDivider(),
                SelectionBarAction(
                  icon: Icons.done_rounded,
                  label: 'Done',
                  onPressed: onDone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _withTracks(
    BuildContext context,
    List<HideTarget> targets,
    int Function(AudioController audio, List<Track> tracks) apply, {
    String? toast,
  }) async {
    final audio = context.read<AudioController>();
    final tracks = await resolveSelectionTracks(context, targets);
    if (!context.mounted || tracks == null || tracks.isEmpty) return;
    final firstPosition = apply(audio, tracks);
    if (toast != null) {
      showQueueAdditionToast(
        context,
        message: toast,
        firstPosition: firstPosition,
        count: tracks.length,
      );
    }
    onDone();
  }
}

/// Splits a `type:targetId` key. Artist names can contain colons, so only the
/// first one separates.
HideTarget? parseHideTarget(String key) {
  final separator = key.indexOf(':');
  if (separator <= 0 || separator >= key.length - 1) return null;
  return (
    type: key.substring(0, separator),
    targetId: key.substring(separator + 1),
  );
}

/// Resolves every selected collection to its tracks, in selection order and
/// deduplicated — the same song can sit in two selected collections, and
/// queueing it twice is never what was meant.
///
/// Returns null when a collection could not be loaded, having already said so.
Future<List<Track>?> resolveSelectionTracks(
  BuildContext context,
  List<HideTarget> targets,
) async {
  final library = context.read<LibraryController>();
  final playlistsById = {
    for (final playlist in library.playlists) playlist.id: playlist,
  };
  final tracks = <Track>[];
  final seen = <String>{};
  try {
    for (final target in targets) {
      final List<Track> resolved;
      switch (target.type) {
        case HiddenMediaItem.albumType:
          resolved = (await library.albumDetail(target.targetId)).tracks;
        case HiddenMediaItem.playlistType:
          final playlist = playlistsById[target.targetId];
          resolved = playlist == null
              ? const <Track>[]
              : library.playlistTracks(playlist);
        default:
          resolved = library.artistTracks(target.targetId);
      }
      for (final track in resolved) {
        if (seen.add(track.id)) tracks.add(track);
      }
    }
  } catch (e) {
    if (!context.mounted) return null;
    showQueueToast(context, 'Could not load tracks: $e');
    return null;
  }
  return tracks;
}
