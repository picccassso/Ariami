import 'dart:async';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_event_outbox.dart';
import 'package:ariami_core/services/stats/listening_stats_syncer.dart';
import 'package:test/test.dart';

ListeningEvent _event(String id, {int listenedMs = 1000}) => ListeningEvent(
      eventId: id,
      songId: 'song-1',
      listenedMs: listenedMs,
      plays: 0,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      tzOffsetMinutes: 0,
    );

void main() {
  test('outbox persists and reloads pending events', () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await outbox.load();
    outbox.add(_event('e1'));
    outbox.add(_event('e2'));
    outbox.add(_event('e1')); // duplicate id ignored
    await outbox.persistNow();

    final reloaded = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await reloaded.load();
    expect(reloaded.length, 2);
    expect(reloaded.peek(10).map((e) => e.eventId), ['e1', 'e2']);
  });

  test('source context survives the outbox persistence round-trip', () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await outbox.load();
    outbox.add(ListeningEvent(
      eventId: 'ctx-1',
      songId: 'song-1',
      listenedMs: 15000,
      plays: 0,
      occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      tzOffsetMinutes: 0,
      sourceKind: 'playlist',
      playlistId: 'pl-1',
      clientKind: 'desktop',
    ));
    await outbox.persistNow();

    final reloaded = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await reloaded.load();
    final event = reloaded.peek(1).single;
    expect(event.sourceKind, 'playlist');
    expect(event.playlistId, 'pl-1');
    expect(event.clientKind, 'desktop');
  });

  test('outbox drops oldest events beyond the cap', () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
      maxEvents: 3,
    );
    await outbox.load();
    for (var i = 0; i < 5; i++) {
      outbox.add(_event('e$i'));
    }
    expect(outbox.peek(10).map((e) => e.eventId), ['e2', 'e3', 'e4']);
  });

  test('concurrent persists cannot let an older snapshot win', () async {
    String? storage;
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();
    var writeCount = 0;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async {
        writeCount++;
        if (writeCount == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        storage = contents;
      },
    );
    await outbox.load();

    outbox.add(_event('e1'));
    final firstPersist = outbox.persistNow();
    await firstWriteStarted.future;

    outbox.add(_event('e2'));
    final secondPersist = outbox.persistNow();
    releaseFirstWrite.complete();
    await Future.wait([firstPersist, secondPersist]);

    final reloaded = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await reloaded.load();
    expect(reloaded.peek(10).map((e) => e.eventId), ['e1', 'e2']);
  });

  test('outbox notifies listeners on add, remove, and clear', () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await outbox.load();

    var notifications = 0;
    void listener() => notifications++;
    outbox.addListener(listener);

    outbox.add(_event('e1'));
    expect(notifications, 1);

    outbox.add(_event('e1')); // duplicate ignored, no notify
    expect(notifications, 1);

    outbox.add(_event('e2'));
    expect(notifications, 2);

    await outbox.removeByIds(['e1']);
    expect(notifications, 3);
    expect(outbox.length, 1);

    await outbox.clear();
    expect(notifications, 4);
    expect(outbox.isEmpty, isTrue);

    outbox.removeListener(listener);
    outbox.add(_event('e3'));
    expect(notifications, 4);
  });

  test('syncer keeps events queued across failures and drains on success',
      () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await outbox.load();
    for (var i = 0; i < 5; i++) {
      outbox.add(_event('e$i'));
    }

    var uploadsSucceed = false;
    final uploaded = <String>[];
    final syncer = ListeningStatsSyncer(
      outbox: outbox,
      batchSize: 2,
      upload: (events) async {
        if (!uploadsSucceed) return false;
        uploaded.addAll(events.map((e) => e.eventId));
        return true;
      },
    );

    // Server unreachable: nothing is lost, nothing is acked.
    await syncer.syncNow();
    expect(outbox.length, 5);
    expect(uploaded, isEmpty);

    // Server reachable: drains in order, in batches, exactly once each.
    uploadsSucceed = true;
    await syncer.syncNow();
    expect(outbox.length, 0);
    expect(uploaded, ['e0', 'e1', 'e2', 'e3', 'e4']);

    syncer.dispose();
  });

  test('onBatchAccepted fires with batch ids before remove; not on failure',
      () async {
    String? storage;
    final outbox = ListeningEventOutbox(
      read: () async => storage,
      write: (contents) async => storage = contents,
    );
    await outbox.load();
    for (var i = 0; i < 5; i++) {
      outbox.add(_event('e$i'));
    }

    var uploadsSucceed = false;
    final acceptedBatches = <List<String>>[];
    final outboxLengthWhenAccepted = <int>[];
    // Whether every id in the accepted batch was still resident in the outbox
    // at the moment the callback ran — the identity-level proof that the
    // callback precedes removeByIds (a length match alone could coincide).
    final batchStillResidentWhenAccepted = <bool>[];
    final syncer = ListeningStatsSyncer(
      outbox: outbox,
      batchSize: 2,
      upload: (events) async => uploadsSucceed,
      onBatchAccepted: (ids) {
        acceptedBatches.add(List<String>.of(ids));
        outboxLengthWhenAccepted.add(outbox.length);
        final residentIds =
            outbox.peek(outbox.length).map((e) => e.eventId).toSet();
        batchStillResidentWhenAccepted.add(ids.every(residentIds.contains));
      },
    );

    await syncer.syncNow();
    expect(acceptedBatches, isEmpty);
    expect(outbox.length, 5);

    uploadsSucceed = true;
    await syncer.syncNow();
    expect(acceptedBatches, [
      ['e0', 'e1'],
      ['e2', 'e3'],
      ['e4'],
    ]);
    // Callback runs before removeByIds, so events are still in the outbox:
    // both the count is undiminished and the exact batch ids are still present.
    expect(outboxLengthWhenAccepted, [5, 3, 1]);
    expect(batchStillResidentWhenAccepted, [true, true, true]);
    expect(outbox.length, 0);

    syncer.dispose();
  });
}
