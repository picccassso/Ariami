import 'package:ariami_core/services/server/http_server_limiters.dart';
import 'package:test/test.dart';

void main() {
  group('WeightedFairDownloadLimiter queue waits', () {
    WeightedFairDownloadLimiter build({
      int maxConcurrent = 1,
      int maxQueue = 10,
      int maxConcurrentPerUser = 1,
      int maxQueuePerUser = 10,
      Duration maxQueueWait = const Duration(milliseconds: 50),
    }) {
      return WeightedFairDownloadLimiter(
        maxConcurrent: maxConcurrent,
        maxQueue: maxQueue,
        maxConcurrentPerUser: maxConcurrentPerUser,
        maxQueuePerUser: maxQueuePerUser,
        maxQueueWait: maxQueueWait,
      );
    }

    test('a request that waits too long is turned away, not parked forever',
        () async {
      final limiter = build();
      expect(await limiter.acquire('alex'), FairAcquireResult.acquired);

      // Nothing releases the held slot, so this one has to give up on its own.
      expect(await limiter.acquire('alex'), FairAcquireResult.queueFull);

      expect(limiter.activeCount, 1);
      expect(limiter.queueLength, 0,
          reason: 'an abandoned waiter must stop counting as queued');
      expect(limiter.queueDepthByUser, isEmpty);
    });

    test('abandoned waiters do not consume the per-user queue quota forever',
        () async {
      // The quota is the resource that leaked: without releasing the queue
      // slot on give-up, a user who timed out twice could never queue again
      // and every later download 429'd until the server restarted.
      final limiter = build(maxQueuePerUser: 2);
      expect(await limiter.acquire('alex'), FairAcquireResult.acquired);

      for (var attempt = 1; attempt <= 3; attempt++) {
        expect(await limiter.acquire('alex'), FairAcquireResult.queueFull,
            reason: 'attempt $attempt should time out, not hit the quota');
      }
      expect(limiter.queueLength, 0);
    });

    test('a slot freed after a waiter gave up is genuinely reusable', () async {
      final limiter = build();
      expect(await limiter.acquire('alex'), FairAcquireResult.acquired);
      expect(await limiter.acquire('bea'), FairAcquireResult.queueFull);

      // Bea is gone but her rotation entry is still there; releasing must not
      // hand the freed slot to that ghost.
      limiter.release('alex');
      expect(limiter.activeCount, 0,
          reason: 'a stale rotation entry must not hold a slot');
      expect(limiter.queueLength, 0);

      expect(await limiter.acquire('cai'), FairAcquireResult.acquired);
      expect(limiter.activeCount, 1);
    });

    test('a waiter served before the deadline still gets its slot', () async {
      final limiter = build(maxQueueWait: const Duration(seconds: 10));
      expect(await limiter.acquire('alex'), FairAcquireResult.acquired);

      final queued = limiter.acquire('bea');
      limiter.release('alex');

      expect(await queued, FairAcquireResult.acquired);
      expect(limiter.activeCount, 1);
      expect(limiter.queueLength, 0);
      expect(limiter.userLoadByUser['bea']?.active, 1);
    });
  });
}
