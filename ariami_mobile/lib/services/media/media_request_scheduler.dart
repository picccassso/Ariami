import 'dart:async';

enum MediaRequestPriority {
  visibleNow,
  nearby,
  background,
}

class MediaRequestCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _cancelListeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    final listeners = List<void Function()>.from(_cancelListeners);
    _cancelListeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void onCancel(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _cancelListeners.add(listener);
  }
}

class MediaRequestScheduler {
  static final MediaRequestScheduler _instance =
      MediaRequestScheduler._internal();
  factory MediaRequestScheduler() => _instance;
  MediaRequestScheduler._internal();

  static const int _maxForegroundArtworkRequests = 3;
  static const int _maxBackgroundArtworkRequests = 1;
  static const int _maxArtworkQueueLength = 200;
  static const Duration _staleLowPriorityAge = Duration(seconds: 20);

  final List<_QueuedArtworkRequest<dynamic>> _artworkQueue = [];
  int _activeForegroundArtworkRequests = 0;
  int _activeBackgroundArtworkRequests = 0;

  Future<T?> enqueueArtwork<T>({
    required MediaRequestPriority priority,
    required Future<T?> Function() task,
    MediaRequestCancellationToken? cancellationToken,
  }) {
    final token = cancellationToken ?? MediaRequestCancellationToken();
    if (token.isCancelled) {
      return Future<T?>.value(null);
    }

    final completer = Completer<T?>();
    _artworkQueue.add(
      _QueuedArtworkRequest<T>(
        priority: priority,
        token: token,
        enqueuedAt: DateTime.now(),
        task: task,
        completer: completer,
      ),
    );

    _enforceArtworkQueueLimit();
    _pumpArtworkQueue();
    return completer.future;
  }

  void _enforceArtworkQueueLimit() {
    _dropCancelledOrStaleLowPriorityRequests();

    while (_artworkQueue.length > _maxArtworkQueueLength) {
      final backgroundIndex = _artworkQueue.indexWhere(
        (request) => request.priority == MediaRequestPriority.background,
      );

      if (backgroundIndex != -1) {
        final dropped = _artworkQueue.removeAt(backgroundIndex);
        dropped.completeWithNull();
        continue;
      }

      final nearbyIndex = _artworkQueue.indexWhere(
        (request) => request.priority == MediaRequestPriority.nearby,
      );

      if (nearbyIndex != -1) {
        final dropped = _artworkQueue.removeAt(nearbyIndex);
        dropped.completeWithNull();
        continue;
      }

      final dropped = _artworkQueue.removeAt(0);
      dropped.completeWithNull();
    }
  }

  void _dropCancelledOrStaleLowPriorityRequests() {
    final now = DateTime.now();

    for (var index = _artworkQueue.length - 1; index >= 0; index--) {
      final request = _artworkQueue[index];
      final isLowPriority = request.priority != MediaRequestPriority.visibleNow;
      final isStale = now.difference(request.enqueuedAt) > _staleLowPriorityAge;

      if (!isLowPriority) continue;
      if (!request.token.isCancelled && !isStale) continue;

      _artworkQueue.removeAt(index);
      request.completeWithNull();
    }
  }

  _QueuedArtworkRequest<dynamic>? _nextForegroundArtworkRequest() {
    final visibleIndex = _artworkQueue.indexWhere(
      (request) => request.priority == MediaRequestPriority.visibleNow,
    );
    if (visibleIndex != -1) {
      return _artworkQueue.removeAt(visibleIndex);
    }

    final nearbyIndex = _artworkQueue.indexWhere(
      (request) => request.priority == MediaRequestPriority.nearby,
    );
    if (nearbyIndex != -1) {
      return _artworkQueue.removeAt(nearbyIndex);
    }

    return null;
  }

  _QueuedArtworkRequest<dynamic>? _nextBackgroundArtworkRequest() {
    final index = _artworkQueue.indexWhere(
      (request) => request.priority == MediaRequestPriority.background,
    );
    if (index == -1) return null;
    return _artworkQueue.removeAt(index);
  }

  void _pumpArtworkQueue() {
    _dropCancelledOrStaleLowPriorityRequests();

    while (_activeForegroundArtworkRequests < _maxForegroundArtworkRequests) {
      final request = _nextForegroundArtworkRequest();
      if (request == null) break;
      _runArtworkRequest(request, isBackground: false);
    }

    while (_activeBackgroundArtworkRequests < _maxBackgroundArtworkRequests) {
      final request = _nextBackgroundArtworkRequest();
      if (request == null) break;
      _runArtworkRequest(request, isBackground: true);
    }
  }

  void _runArtworkRequest(
    _QueuedArtworkRequest<dynamic> request, {
    required bool isBackground,
  }) {
    if (request.token.isCancelled) {
      request.completeWithNull();
      return;
    }

    if (isBackground) {
      _activeBackgroundArtworkRequests++;
    } else {
      _activeForegroundArtworkRequests++;
    }

    Future<void>(() async {
      if (request.token.isCancelled) {
        request.completeWithNull();
        return;
      }

      final value = await request.task();
      request.complete(value);
    }).catchError((Object error, StackTrace stackTrace) {
      request.completeError(error, stackTrace);
    }).whenComplete(() {
      if (isBackground) {
        _activeBackgroundArtworkRequests--;
      } else {
        _activeForegroundArtworkRequests--;
      }
      _pumpArtworkQueue();
    });
  }
}

class _QueuedArtworkRequest<T> {
  _QueuedArtworkRequest({
    required this.priority,
    required this.token,
    required this.enqueuedAt,
    required this.task,
    required this.completer,
  });

  final MediaRequestPriority priority;
  final MediaRequestCancellationToken token;
  final DateTime enqueuedAt;
  final Future<T?> Function() task;
  final Completer<T?> completer;

  void complete(T? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void completeWithNull() {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}
