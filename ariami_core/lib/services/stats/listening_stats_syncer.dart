import 'dart:async';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_event_outbox.dart';

/// Drains a [ListeningEventOutbox] to the server.
///
/// Upload batches are only removed from the outbox after [upload] reports the
/// server accepted them; the server dedupes by eventId, so retrying after an
/// ambiguous failure (timeout, dropped connection) is always safe.
class ListeningStatsSyncer {
  ListeningStatsSyncer({
    required this.outbox,
    required Future<bool> Function(List<ListeningEvent> events) upload,
    Future<bool> Function()? canSync,
    this.interval = const Duration(seconds: 45),
    this.batchSize = 200,
    void Function()? onSynced,
  })  : _upload = upload,
        _canSync = canSync,
        _onSynced = onSynced;

  final ListeningEventOutbox outbox;
  final Future<bool> Function(List<ListeningEvent> events) _upload;

  /// Gate (e.g. "connected and authenticated"). When it returns false the
  /// syncer stays quiet and events keep queueing locally.
  final Future<bool> Function()? _canSync;

  /// Invoked after at least one batch was accepted, so the owner can refresh
  /// its account-wide summary.
  final void Function()? _onSynced;

  final Duration interval;
  final int batchSize;

  Timer? _timer;
  Timer? _nudgeTimer;
  bool _syncing = false;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    // Kick off promptly so a reconnect drains the backlog without waiting a
    // full interval.
    nudge();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
  }

  /// Requests a sync soon (debounced), e.g. after new events were queued.
  void nudge({Duration delay = const Duration(seconds: 5)}) {
    if (!_running) return;
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(delay, () {
      _nudgeTimer = null;
      unawaited(syncNow());
    });
  }

  /// Drains the outbox in batches until empty or an upload fails.
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    var anyAccepted = false;
    try {
      while (outbox.isNotEmpty) {
        final gate = _canSync;
        if (gate != null && !await gate()) return;
        final batch = outbox.peek(batchSize);
        if (batch.isEmpty) return;
        final ok = await _upload(batch);
        if (!ok) return; // stay queued; a later sync retries safely
        await outbox.removeByIds(batch.map((event) => event.eventId));
        anyAccepted = true;
      }
    } catch (_) {
      // Network errors leave events queued; nothing to do.
    } finally {
      _syncing = false;
      if (anyAccepted) _onSynced?.call();
    }
  }

  void dispose() {
    stop();
  }
}
