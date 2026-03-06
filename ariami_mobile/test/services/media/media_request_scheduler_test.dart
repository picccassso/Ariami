import 'dart:async';

import 'package:ariami_mobile/services/media/media_request_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaRequestScheduler', () {
    final scheduler = MediaRequestScheduler();

    test('limits visible-now artwork concurrency to 3', () async {
      var running = 0;
      var maxRunning = 0;
      final gate = Completer<void>();

      final requests = List.generate(
        8,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            running += 1;
            if (running > maxRunning) {
              maxRunning = running;
            }
            await gate.future;
            running -= 1;
            return 1;
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(maxRunning, lessThanOrEqualTo(3));

      gate.complete();
      final results = await Future.wait(requests);
      expect(results.whereType<int>().length, 8);
    });

    test('limits background artwork concurrency to 1', () async {
      var running = 0;
      var maxRunning = 0;
      final gate = Completer<void>();

      final requests = List.generate(
        6,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.background,
          task: () async {
            running += 1;
            if (running > maxRunning) {
              maxRunning = running;
            }
            await gate.future;
            running -= 1;
            return 1;
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(maxRunning, lessThanOrEqualTo(1));

      gate.complete();
      final results = await Future.wait(requests);
      expect(results.whereType<int>().length, 6);
    });

    test('returns null for cancelled queued artwork requests', () async {
      final gate = Completer<void>();
      final occupying = List.generate(
        3,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            await gate.future;
            return 1;
          },
        ),
      );

      var taskStarted = false;
      final cancellationToken = MediaRequestCancellationToken();
      final cancelledRequest = scheduler.enqueueArtwork<int>(
        priority: MediaRequestPriority.visibleNow,
        cancellationToken: cancellationToken,
        task: () async {
          taskStarted = true;
          return 1;
        },
      );

      cancellationToken.cancel();
      gate.complete();

      final cancelledResult = await cancelledRequest;
      await Future.wait(occupying);

      expect(taskStarted, isFalse);
      expect(cancelledResult, isNull);
    });
  });
}
