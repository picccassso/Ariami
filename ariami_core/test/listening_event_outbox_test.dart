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
}
