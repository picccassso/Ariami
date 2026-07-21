import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/listening_stats_models.dart';

/// Durable client-side queue of listening events awaiting upload.
///
/// Events survive app restarts and offline periods; they are only removed
/// after the server acknowledges them, and the server deduplicates by eventId,
/// so crash-replays and retries are harmless.
///
/// Storage is abstracted behind [read]/[write] callbacks so each client can
/// persist wherever fits (a file on desktop/mobile, SharedPreferences on TV).
class ListeningEventOutbox {
  ListeningEventOutbox({
    required Future<String?> Function() read,
    required Future<void> Function(String contents) write,
    this.maxEvents = 5000,
  })  : _read = read,
        _write = write;

  final Future<String?> Function() _read;
  final Future<void> Function(String contents) _write;

  /// Oldest events are dropped beyond this cap so a device that can't reach
  /// the server for months degrades gracefully instead of growing forever.
  final int maxEvents;

  final List<ListeningEvent> _pending = <ListeningEvent>[];
  final Set<String> _pendingIds = <String>{};
  final List<void Function()> _listeners = <void Function()>[];
  Timer? _persistTimer;
  Future<void> _persistChain = Future<void>.value();
  bool _loaded = false;

  static const Duration _persistDebounce = Duration(seconds: 3);

  int get length => _pending.length;
  bool get isEmpty => _pending.isEmpty;
  bool get isNotEmpty => _pending.isNotEmpty;

  /// Register for queue mutations (add / remove / clear). Used by display-only
  /// overlays that need to refresh when pending events change.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    // Copy so a listener can remove itself during notification.
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  /// Loads persisted events. Call once before use; safe to call again.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _read();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final event = ListeningEvent.tryFromJson(item);
        if (event == null || _pendingIds.contains(event.eventId)) continue;
        _pending.add(event);
        _pendingIds.add(event.eventId);
      }
    } catch (_) {
      // A corrupt outbox is not worth crashing playback over; start fresh.
      _pending.clear();
      _pendingIds.clear();
    }
  }

  /// Queues an event for upload. Duplicate eventIds are ignored.
  void add(ListeningEvent event) {
    if (_pendingIds.contains(event.eventId)) return;
    _pending.add(event);
    _pendingIds.add(event.eventId);
    while (_pending.length > maxEvents) {
      final dropped = _pending.removeAt(0);
      _pendingIds.remove(dropped.eventId);
    }
    _schedulePersist();
    _notifyListeners();
  }

  /// The oldest [limit] events, for the next upload batch.
  List<ListeningEvent> peek(int limit) {
    if (_pending.length <= limit) return List.unmodifiable(_pending);
    return List.unmodifiable(_pending.sublist(0, limit));
  }

  /// Removes acknowledged events and persists.
  Future<void> removeByIds(Iterable<String> eventIds) async {
    final ids = eventIds.toSet();
    if (ids.isEmpty) return;
    final before = _pending.length;
    _pending.removeWhere((event) => ids.contains(event.eventId));
    _pendingIds.removeAll(ids);
    if (_pending.length == before) return;
    await persistNow();
    _notifyListeners();
  }

  /// Drops everything (stats reset / logout of the account).
  Future<void> clear() async {
    if (_pending.isEmpty && _pendingIds.isEmpty) return;
    _pending.clear();
    _pendingIds.clear();
    await persistNow();
    _notifyListeners();
  }

  void _schedulePersist() {
    _persistTimer ??= Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(persistNow());
    });
  }

  /// Writes the queue to storage immediately (also used on app suspend).
  Future<void> persistNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    // Serialize writes. A lifecycle flush can race a debounce or an upload
    // acknowledgement; without ordering, an older slow write could finish
    // last and overwrite a newer queue snapshot on disk.
    _persistChain = _persistChain.then((_) async {
      try {
        await _write(
          jsonEncode(_pending.map((event) => event.toJson()).toList()),
        );
      } catch (_) {
        // Best-effort: events stay in memory and the next persist retries.
      }
    });
    await _persistChain;
  }

  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _listeners.clear();
  }
}
