import 'dart:async';

import '../../database/library_sync_database.dart';
import '../../models/api_models.dart';
import '../api/api_client.dart';
import '../library/library_repository.dart';

/// Sync engine for v2 bootstrap + delta synchronization.
class LibrarySyncEngine {
  LibrarySyncEngine({
    required ApiClient Function() apiClientProvider,
    LibraryRepository? libraryRepository,
    this.onBootstrapCompleted,
    this.bootstrapPageLimit = 200,
    this.changesPageLimit = 500,
    this.pollInterval = const Duration(seconds: 30),
  })  : _apiClientProvider = apiClientProvider,
        _libraryRepository = libraryRepository ?? LibraryRepository(),
        _ownsRepository = libraryRepository == null;

  final ApiClient Function() _apiClientProvider;
  final LibraryRepository _libraryRepository;
  final bool _ownsRepository;
  final Future<void> Function(int latestToken)? onBootstrapCompleted;

  final int bootstrapPageLimit;
  final int changesPageLimit;
  final Duration pollInterval;

  Timer? _pollTimer;
  bool _running = false;
  bool _disposed = false;
  Future<void> _syncQueue = Future<void>.value();

  bool get isRunning => _running;

  Future<LibrarySyncState> getSyncState() {
    return _libraryRepository.getSyncState();
  }

  void start() {
    if (_running || _disposed) return;
    _running = true;
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  void stop() {
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stop();
    if (_ownsRepository) {
      await _libraryRepository.close();
    }
  }

  Future<void> syncNow() {
    return _enqueueSync(() async {
      final bootstrapComplete =
          await _libraryRepository.hasCompletedBootstrap();
      if (!bootstrapComplete) {
        await _runBootstrapSync();
        return;
      }
      await _applyDeltaChanges();
    });
  }

  Future<void> syncUntil(int targetToken) {
    return _enqueueSync(() async {
      final bootstrapComplete =
          await _libraryRepository.hasCompletedBootstrap();
      if (!bootstrapComplete) {
        await _runBootstrapSync();
      }
      await _applyDeltaChanges(targetToken: targetToken);
    });
  }

  Future<void> _runBootstrapSync() async {
    await _libraryRepository.resetForBootstrap();

    try {
      String? cursor;
      int latestToken = 0;
      var pagesProcessed = 0;

      while (true) {
        final page = await _apiClientProvider()
            .getV2BootstrapPage(cursor, bootstrapPageLimit);

        await _libraryRepository.applyBootstrapPage(page);

        latestToken = page.syncToken;
        pagesProcessed += 1;

        final nextCursor = page.pageInfo.nextCursor;
        final hasMore = page.pageInfo.hasMore;

        if (!hasMore || nextCursor == null || nextCursor.isEmpty) {
          break;
        }
        if (nextCursor == cursor) {
          break;
        }

        cursor = nextCursor;

        // Safety guard against malformed pagination loops.
        if (pagesProcessed > 10000) {
          break;
        }
      }

      await _libraryRepository.completeBootstrap(lastAppliedToken: latestToken);
      if (onBootstrapCompleted != null) {
        await onBootstrapCompleted!(latestToken);
      }
    } catch (_) {
      await _libraryRepository.abortBootstrap();
      rethrow;
    }
  }

  Future<void> _applyDeltaChanges({int? targetToken}) async {
    var pagesProcessed = 0;

    while (true) {
      final state = await _libraryRepository.getSyncState();
      final since = state.lastAppliedToken;
      if (targetToken != null && since >= targetToken) {
        return;
      }

      final response =
          await _apiClientProvider().getV2Changes(since, changesPageLimit);

      if (_requiresBootstrapRefresh(response)) {
        await _runBootstrapSync();
        return;
      }

      if (response.events.isNotEmpty) {
        await _libraryRepository.applyChangesResponse(response);
      } else {
        final nextToken = response.toToken > since ? response.toToken : since;
        await _libraryRepository.updateSyncState(
          lastAppliedToken: nextToken,
          bootstrapComplete: state.bootstrapComplete,
        );
      }

      final nextState = await _libraryRepository.getSyncState();
      final progressed = nextState.lastAppliedToken > since;

      if (!response.hasMore &&
          (targetToken == null || nextState.lastAppliedToken >= targetToken)) {
        return;
      }

      if (!progressed) {
        return;
      }

      pagesProcessed += 1;
      if (pagesProcessed > 10000) {
        return;
      }
    }
  }

  bool _requiresBootstrapRefresh(V2ChangesResponse response) {
    for (final event in response.events) {
      if (event.op == V2ChangeOp.upsert && event.payload == null) {
        return true;
      }
    }
    return false;
  }

  Future<void> _enqueueSync(Future<void> Function() action) {
    final next = _syncQueue.then((_) async {
      if (_disposed) return;
      await action();
    });
    _syncQueue = (() async {
      try {
        await next;
      } catch (_) {}
    }());
    return next;
  }
}
