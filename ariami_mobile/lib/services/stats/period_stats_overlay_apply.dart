import 'package:ariami_core/ariami_core.dart'
    show ListeningEvent, ListeningPeriodStats, overlayPeriodStatsWithPending;

/// Applies the pending-outbox overlay on top of an untouched server/cache base.
///
/// Display-only: never mutates [base] or the outbox. With a null [base] and
/// in-range pending events, still returns usable period stats for offline UI.
ListeningPeriodStats applyPeriodStatsOverlay({
  required ListeningPeriodStats? base,
  required List<ListeningEvent> pending,
  required String fromDay,
  required String toDay,
  Set<String> excludeEventIds = const {},
}) {
  return overlayPeriodStatsWithPending(
    base: base,
    pending: pending,
    fromDay: fromDay,
    toDay: toDay,
    excludeEventIds: excludeEventIds,
  );
}

/// Production exclude set: server-acked ids that are still in the local outbox.
///
/// Used during the upload-accept → outbox-drain window so a freshly fetched
/// period base is not double-counted with the same events still pending.
Set<String> excludeAckedPendingEventIds({
  required Set<String> ackedInFlightEventIds,
  required Iterable<ListeningEvent> pending,
}) {
  if (ackedInFlightEventIds.isEmpty) return const {};
  final pendingIds = pending.map((e) => e.eventId).toSet();
  return ackedInFlightEventIds.intersection(pendingIds);
}

/// Production composition path for period screens: base + pending, excluding
/// acked-in-flight ids still sitting in the outbox.
ListeningPeriodStats buildDisplayedPeriodStats({
  required ListeningPeriodStats? base,
  required List<ListeningEvent> pending,
  required String fromDay,
  required String toDay,
  required Set<String> ackedInFlightEventIds,
}) {
  return applyPeriodStatsOverlay(
    base: base,
    pending: pending,
    fromDay: fromDay,
    toDay: toDay,
    excludeEventIds: excludeAckedPendingEventIds(
      ackedInFlightEventIds: ackedInFlightEventIds,
      pending: pending,
    ),
  );
}

/// Whether [stats] has anything worth showing instead of the offline fallback.
bool periodStatsHasContent(ListeningPeriodStats? stats) {
  if (stats == null) return false;
  return stats.totalPlays > 0 ||
      stats.totalListenedMs > 0 ||
      stats.songs.isNotEmpty ||
      stats.artists.isNotEmpty ||
      stats.albums.isNotEmpty;
}
