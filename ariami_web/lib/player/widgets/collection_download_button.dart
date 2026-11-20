import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';
import 'playback_helpers.dart';

/// Album/playlist header download button, mirroring mobile's states:
///
///  * not downloaded — download icon, click queues the collection;
///  * downloading — progress ring around a stop square, click cancels the
///    download and removes what it already fetched;
///  * downloaded — green check, click removes the downloads (with confirm).
class CollectionDownloadButton extends StatelessWidget {
  const CollectionDownloadButton({
    super.key,
    required this.tracks,
    required this.collectionLabel,
    required this.collectionName,
  });

  final List<Track> tracks;

  /// 'album' or 'playlist' — used in tooltips and dialogs.
  final String collectionLabel;

  final String collectionName;

  @override
  Widget build(BuildContext context) {
    // When this computer hosts the server the files are already on its disk —
    // there is nothing to download.
    final isLocalServer =
        context.select<ConnectionController, bool>((c) => c.isLocalServer);
    final downloads = maybeWatchProvider<PlayerDownloadsBridge?>(context) ??
        maybeWatchProvider<PlayerDownloadsBridge>(context);
    if (isLocalServer || downloads == null) return const SizedBox.shrink();

    final counts = downloads.collectionCounts(tracks.map((t) => t.id));
    final total = tracks.length;

    if (total > 0 && counts.inFlight > 0) {
      return IconButton(
        tooltip: 'Cancel download — '
            '${counts.completed} of $total done',
        onPressed: () => _cancelAndRemove(context),
        icon: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track circle so the ring reads as a ring even at 0%.
              CircularProgressIndicator(
                strokeWidth: 2.5,
                value: (counts.progress / total).clamp(0.0, 1.0),
                backgroundColor:
                    context.colors.textSecondary.withValues(alpha: 0.3),
              ),
              Icon(
                Icons.stop_rounded,
                size: 14,
                color: context.colors.textPrimary,
              ),
            ],
          ),
        ),
      );
    }

    if (total > 0 && counts.completed >= total) {
      return IconButton(
        tooltip: 'Downloaded — click to remove',
        onPressed: () => _confirmRemove(context),
        icon: const Icon(
          Icons.download_done_rounded,
          size: 27,
          color: Colors.green,
        ),
      );
    }

    return IconButton(
      tooltip: 'Download $collectionLabel',
      icon: const Icon(Icons.download_for_offline_outlined, size: 27),
      color: context.colors.textSecondary,
      onPressed:
          total == 0 ? null : () => enqueueTrackDownloads(context, tracks),
    );
  }

  /// Cancels the in-flight batch and removes whatever it already fetched —
  /// an immediate undo, so no confirmation dialog.
  Future<void> _cancelAndRemove(BuildContext context) async {
    final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
        maybeReadProvider<PlayerDownloadsBridge>(context);
    if (downloads == null) return;
    await downloads.removeCollectionDownloads(tracks.map((t) => t.id));
    if (!context.mounted) return;
    _toast(context, 'Download cancelled and removed');
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
        maybeReadProvider<PlayerDownloadsBridge>(context);
    if (downloads == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove downloads for "$collectionName"?'),
        content: Text(
          'This deletes the downloaded files for this $collectionLabel '
          'from your disk. You can download it again anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await downloads.removeCollectionDownloads(tracks.map((t) => t.id));
    if (!context.mounted) return;
    _toast(context, 'Downloads removed');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
