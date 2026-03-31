part of 'http_server.dart';

enum _FairAcquireResult {
  acquired,
  userQuotaExceeded,
  queueFull,
}

class _SimpleLimiter {
  _SimpleLimiter({
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

class _WeightedFairDownloadLimiter {
  _WeightedFairDownloadLimiter({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });

  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

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

  Future<_FairAcquireResult> acquire(String userId) async {
    final state =
        _states.putIfAbsent(userId, () => _PerUserDownloadQueueState());

    final canAcquireImmediately = _queued == 0 &&
        _active < maxConcurrent &&
        state.active < maxConcurrentPerUser;
    if (canAcquireImmediately) {
      _active += 1;
      state.active += 1;
      return _FairAcquireResult.acquired;
    }

    if (state.queued >= maxQueuePerUser) {
      return _FairAcquireResult.userQuotaExceeded;
    }

    if (_queued >= maxQueue) {
      return _FairAcquireResult.queueFull;
    }

    final completer = Completer<void>();
    state.waiters.add(completer);
    state.queued += 1;
    _queued += 1;

    if (!state.inRotation) {
      state.inRotation = true;
      _rotation.addLast(userId);
    }

    await completer.future;
    return _FairAcquireResult.acquired;
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
