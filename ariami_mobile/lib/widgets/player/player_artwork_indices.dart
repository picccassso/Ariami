import '../../models/repeat_mode.dart';

/// Whether the artwork carousel should show wrap-around sentinel pages.
bool playerArtworkWrapEnabled({
  required RepeatMode repeatMode,
  required int queueLength,
}) {
  return repeatMode == RepeatMode.all && queueLength > 1;
}

/// Number of pages in the artwork [PageView].
int playerArtworkPageCount({
  required bool wrapEnabled,
  required int queueLength,
}) {
  if (queueLength <= 0) {
    return 0;
  }
  return wrapEnabled ? queueLength + 2 : queueLength;
}

/// Maps a queue index to the corresponding carousel page index.
int playerArtworkQueueIndexToPageIndex({
  required int queueIndex,
  required bool wrapEnabled,
  required int queueLength,
}) {
  if (queueLength <= 0) {
    return 0;
  }
  final clampedIndex = queueIndex.clamp(0, queueLength - 1);
  return wrapEnabled ? clampedIndex + 1 : clampedIndex;
}

/// Maps a carousel page index to the corresponding queue index.
int playerArtworkPageIndexToQueueIndex({
  required int pageIndex,
  required bool wrapEnabled,
  required int queueLength,
}) {
  if (queueLength <= 0) {
    return 0;
  }

  if (!wrapEnabled) {
    return pageIndex.clamp(0, queueLength - 1);
  }

  if (pageIndex == 0) {
    return queueLength - 1;
  }
  if (pageIndex == queueLength + 1) {
    return 0;
  }
  return (pageIndex - 1).clamp(0, queueLength - 1);
}

/// Chooses the carousel page to animate to when moving from [fromQueueIndex]
/// to [toQueueIndex], using sentinel pages for repeat-all wrap jumps.
int playerArtworkAnimateTargetPageIndex({
  required int fromQueueIndex,
  required int toQueueIndex,
  required bool wrapEnabled,
  required int queueLength,
}) {
  if (!wrapEnabled || queueLength <= 1) {
    return playerArtworkQueueIndexToPageIndex(
      queueIndex: toQueueIndex,
      wrapEnabled: false,
      queueLength: queueLength,
    );
  }

  final isWrapNext =
      fromQueueIndex == queueLength - 1 && toQueueIndex == 0;
  if (isWrapNext) {
    return queueLength + 1;
  }

  final isWrapPrevious = fromQueueIndex == 0 && toQueueIndex == queueLength - 1;
  if (isWrapPrevious) {
    return 0;
  }

  return playerArtworkQueueIndexToPageIndex(
    queueIndex: toQueueIndex,
    wrapEnabled: true,
    queueLength: queueLength,
  );
}

/// Whether [pageIndex] is a sentinel page used only for wrap-around peeks.
bool playerArtworkIsSentinelPageIndex({
  required int pageIndex,
  required bool wrapEnabled,
  required int queueLength,
}) {
  return wrapEnabled &&
      queueLength > 1 &&
      (pageIndex == 0 || pageIndex == queueLength + 1);
}
