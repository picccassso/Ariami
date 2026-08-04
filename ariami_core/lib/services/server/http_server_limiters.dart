/// Concurrency limiters guarding the server's download and artwork work.
///
/// Split out of `http_server.dart` so the fairness and queue bookkeeping
/// can be unit tested directly — it is the kind of counting that drifts
/// silently when it is only ever exercised through a live HTTP server.
library;

import 'dart:async';
import 'dart:collection';

enum FairAcquireResult {
  acquired,
  userQuotaExceeded,
  queueFull,
}

class SimpleLimiter {
  SimpleLimiter({
    required this.maxConcurrent,
    required this.maxQueue,
  });

  final int maxConcurrent;
  final int maxQueue;
  int _active = 0;
  final Queue<Completer<void>> _queue = Queue<Completer<void>>();

  int get activeCount => _active;
  int get queueLength => _queue.length;
  bool get isIdle => _active == 0 && _queue.isEmpty;

  Future<bool> acquire() async {
    if (_active < maxConcurrent) {
      _active += 1;
      return true;
    }

    if (_queue.length >= maxQueue) {
      return false;
    }

    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
    return true;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      if (!next.isCompleted) {
        next.complete();
      }
      return;
    }

    if (_active > 0) {
      _active -= 1;
    }
  }
}

class WeightedFairDownloadLimiter {
  WeightedFairDownloadLimiter({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
    this.maxQueueWait = const Duration(seconds: 30),
  });

  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  /// How long a request may wait for a slot before it is turned away with a
  /// retryable 503 instead of parking indefinitely.
  ///
  /// A queued request holds an open connection the client cannot see progress
  /// on, so an unbounded wait turns a busy moment into a client that appears
  /// hung. Giving up and saying "retry shortly" lets the client back off and
  /// come back, which is both visible and self-correcting.
  final Duration maxQueueWait;

  int _active = 0;
  int _queued = 0;
  final Map<String, _PerUserDownloadQueueState> _states =
      <String, _PerUserDownloadQueueState>{};
  final Queue<String> _rotation = Queue<String>();
  final Map<String, int> _roundCredits = <String, int>{};

  int get activeCount => _active;
  int get queueLength => _queued;
  Map<String, int> get queueDepthByUser {
    final snapshot = <String, int>{};
    _states.forEach((userId, state) {
      if (state.queued > 0) {
        snapshot[userId] = state.queued;
      }
    });
    return snapshot;
  }

  Map<String, DownloadLimiterUserSnapshot> get userLoadByUser {
    final snapshot = <String, DownloadLimiterUserSnapshot>{};
    _states.forEach((userId, state) {
      if (state.active > 0 || state.queued > 0) {
        snapshot[userId] = DownloadLimiterUserSnapshot(
          active: state.active,
          queued: state.queued,
        );
      }
    });
    return snapshot;
  }

  Future<FairAcquireResult> acquire(String userId) async {
    final state =
        _states.putIfAbsent(userId, () => _PerUserDownloadQueueState());

    final canAcquireImmediately = _queued == 0 &&
        _active < maxConcurrent &&
        state.active < maxConcurrentPerUser;
    if (canAcquireImmediately) {
      _active += 1;
      state.active += 1;
      return FairAcquireResult.acquired;
    }

    if (state.queued >= maxQueuePerUser) {
      return FairAcquireResult.userQuotaExceeded;
    }

    if (_queued >= maxQueue) {
      return FairAcquireResult.queueFull;
    }

    final completer = Completer<void>();
    state.waiters.add(completer);
    state.queued += 1;
    _queued += 1;

    if (!state.inRotation) {
      state.inRotation = true;
      _rotation.addLast(userId);
    }

    try {
      await completer.future.timeout(maxQueueWait);
    } on TimeoutException {
      // The grant can land in the same turn the timeout fires. A completed
      // completer means the slot is already ours and has been counted as
      // active — take it, or it would be leaked with nothing to release it.
      if (completer.isCompleted) {
        return FairAcquireResult.acquired;
      }
      _abandonWaiter(userId, completer);
      return FairAcquireResult.queueFull;
    }
    return FairAcquireResult.acquired;
  }

  /// Drop a waiter that gave up, so it stops counting against the queue depth
  /// its user is allowed.
  void _abandonWaiter(String userId, Completer<void> completer) {
    final state = _states[userId];
    if (state == null) return;
    if (!state.waiters.remove(completer)) return;
    state.queued -= 1;
    _queued -= 1;
    // The rotation entry is left alone: _grantNextQueuedRequest already drops
    // users it finds with no waiters left.
    _cleanupUserState(userId);
  }

  void release(String userId) {
    final state = _states[userId];
    if (state != null && state.active > 0) {
      state.active -= 1;
    }

    if (_active > 0) {
      _active -= 1;
    }

    _grantNextQueuedRequest();
    _cleanupUserState(userId);
  }

  void _grantNextQueuedRequest() {
    if (_active >= maxConcurrent || _rotation.isEmpty) {
      return;
    }

    final usersToCheck = _rotation.length;
    var checked = 0;

    while (checked < usersToCheck && _active < maxConcurrent) {
      final userId = _rotation.removeFirst();
      checked += 1;

      final state = _states[userId];
      if (state == null || state.waiters.isEmpty) {
        if (state != null) {
          state.inRotation = false;
          _cleanupUserState(userId);
        }
        _roundCredits.remove(userId);
        continue;
      }

      if (state.active >= maxConcurrentPerUser) {
        _rotation.addLast(userId);
        continue;
      }

      final weight = 1;
      final availableCredits = _roundCredits[userId] ?? weight;
      final next = state.waiters.removeFirst();
      state.queued -= 1;
      _queued -= 1;
      _active += 1;
      state.active += 1;

      if (!next.isCompleted) {
        next.complete();
      }

      final remainingCredits = availableCredits - 1;
      if (state.waiters.isNotEmpty) {
        if (remainingCredits > 0) {
          _roundCredits[userId] = remainingCredits;
          _rotation.addFirst(userId);
        } else {
          _roundCredits[userId] = weight;
          _rotation.addLast(userId);
        }
      } else {
        state.inRotation = false;
        _roundCredits.remove(userId);
        _cleanupUserState(userId);
      }

      return;
    }
  }

  void _cleanupUserState(String userId) {
    final state = _states[userId];
    if (state == null) return;
    if (state.active == 0 && state.queued == 0 && state.waiters.isEmpty) {
      _states.remove(userId);
      _roundCredits.remove(userId);
    }
  }
}

class _PerUserDownloadQueueState {
  int active = 0;
  int queued = 0;
  bool inRotation = false;
  final Queue<Completer<void>> waiters = Queue<Completer<void>>();
}

class DownloadLimiterUserSnapshot {
  const DownloadLimiterUserSnapshot({
    required this.active,
    required this.queued,
  });

  final int active;
  final int queued;
}
