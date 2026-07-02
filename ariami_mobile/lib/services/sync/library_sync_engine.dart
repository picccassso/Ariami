import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../database/library_sync_database.dart';
import '../../models/api_models.dart';
import '../api/api_client.dart';
import '../library/library_repository.dart';

/// Queryable sync health for UI layers.
class LibrarySyncHealth {
  const LibrarySyncHealth({
    this.lastError,
    this.lastSuccessfulSyncAt,
    this.isPartialBootstrap = false,
    this.bootstrapMismatchReason,
  });

  final String? lastError;
  final DateTime? lastSuccessfulSyncAt;
  final bool isPartialBootstrap;
  final String? bootstrapMismatchReason;

  bool get hasSyncFailure => lastError != null && lastError!.isNotEmpty;

  bool get isPartialRead => isPartialBootstrap;
}

/// Sync engine for v2 bootstrap + delta synchronization.
class LibrarySyncEngine {
  LibrarySyncEngine({
    required ApiClient Function() apiClientProvider,
    LibraryRepository? libraryRepository,
    this.onBootstrapCompleted,
    this.bootstrapPageLimit = 200,
    this.changesPageLimit = 500,
    this.maxDeltaTokenGapBeforeBootstrap = 5000,
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
  final int maxDeltaTokenGapBeforeBootstrap;
  final Duration pollInterval;
  static const List<int> _bootstrapRetryScheduleSeconds = <int>[
    30,
    60,
    120,
    240,
    300,
  ];

  Timer? _pollTimer;
  bool _running = false;
  bool _disposed = false;
  Future<void> _syncQueue = Future<void>.value();
  DateTime? _nextBootstrapRetryAt;
  int _bootstrapRetryAttempts = 0;
  String? _lastError;
  DateTime? _lastSuccessfulSyncAt;

  bool get isRunning => _running;

  Future<LibrarySyncState> getSyncState() {
    return _libraryRepository.getSyncState();
  }

  Future<LibrarySyncHealth> getSyncHealth() async {
    final bootstrapComplete = await _libraryRepository.hasCompletedBootstrap();
    final mismatchReason = bootstrapComplete
        ? null
        : await _libraryRepository.getBootstrapPendingReason();
    return LibrarySyncHealth(
      lastError: _lastError,
      lastSuccessfulSyncAt: _lastSuccessfulSyncAt,
      isPartialBootstrap: !bootstrapComplete,
      bootstrapMismatchReason: mismatchReason,
    );
  }

  void start() {
    if (_running || _disposed) return;
    _running = true;
    _clearBootstrapRetryBackoff();
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
    return _enqueueSync(() => _syncInternal());
  }

  Future<void> syncUntil(int targetToken) {
    return _enqueueSync(() => _syncInternal(targetToken: targetToken));
  }

  /// Replaces the local catalog with a fresh authoritative server snapshot.
  ///
  /// This is intentionally reserved for explicit user refresh/recovery. The
  /// normal background path continues to use efficient delta synchronization.
  Future<void> rebuildFromServer() {
    return _enqueueSync(() async {
      _clearBootstrapRetryBackoff();
      final bootstrapReady = await _runBootstrapSync();
      if (bootstrapReady) {
        _clearBootstrapRetryBackoff();
      } else {
        _scheduleBootstrapRetryBackoff();
      }
    });
  }

  Future<void> _syncInternal({int? targetToken}) async {
    final bootstrapReady = await _libraryRepository.hasCompletedBootstrap();
    debugPrint(
      '[LibrarySyncEngine][syncInternal] bootstrapReady=$bootstrapReady '
      'targetToken=${targetToken ?? '<none>'}',
    );

    if (!bootstrapReady) {
      if (_isBootstrapRetryDeferred()) {
        final until = _nextBootstrapRetryAt!.difference(DateTime.now());
        debugPrint(
          '[LibrarySyncEngine][syncInternal] skipping bootstrap due to backoff '
          'retryIn=${until.inSeconds}s',
        );
        return;
      }

      final readyAfterBootstrap = await _runBootstrapSync();
      if (!readyAfterBootstrap) {
        _scheduleBootstrapRetryBackoff();
        return;
      }
      _clearBootstrapRetryBackoff();
      if (targetToken == null) {
        return;
      }
    } else {
      _clearBootstrapRetryBackoff();
    }

    await _applyDeltaChanges(targetToken: targetToken);
  }

  Future<bool> _runBootstrapSync() async {
    debugPrint('[LibrarySyncEngine][_runBootstrapSync] starting bootstrap');
    await _libraryRepository.resetForBootstrap();

    try {
      String? cursor;
      int latestToken = 0;
      var pagesProcessed = 0;

      while (true) {
        final page = await _apiClientProvider()
            .getV2BootstrapPage(cursor, bootstrapPageLimit);
        debugPrint(
          '[LibrarySyncEngine][_runBootstrapSync] page=${pagesProcessed + 1} '
          'cursor=${cursor ?? '<initial>'} '
          'albums=${page.albums.length} songs=${page.songs.length} '
          'playlists=${page.playlists.length} '
          'hasMore=${page.pageInfo.hasMore} '
          'nextCursor=${page.pageInfo.nextCursor ?? '<null>'} '
          'syncToken=${page.syncToken}',
        );

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
      final bootstrapReady = await _libraryRepository.hasCompletedBootstrap();
      debugPrint(
        '[LibrarySyncEngine][_runBootstrapSync] finished '
        'pagesProcessed=$pagesProcessed latestToken=$latestToken '
        'bootstrapReady=$bootstrapReady',
      );
      if (bootstrapReady && onBootstrapCompleted != null) {
        await onBootstrapCompleted!(latestToken);
      } else if (!bootstrapReady) {
        debugPrint(
          '[LibrarySyncEngine][_runBootstrapSync] suppressed bootstrap-complete '
          'notification because readiness gate is still pending',
        );
      }
      return bootstrapReady;
    } catch (error, stackTrace) {
      debugPrint(
        '[LibrarySyncEngine][_runBootstrapSync] failed error=$error\n$stackTrace',
      );
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
        debugPrint(
          '[LibrarySyncEngine][_applyDeltaChanges] target already satisfied '
          'since=$since targetToken=$targetToken',
        );
        return;
      }

      final response =
          await _apiClientProvider().getV2Changes(since, changesPageLimit);
      debugPrint(
        '[LibrarySyncEngine][_applyDeltaChanges] since=$since '
        'toToken=${response.toToken} syncToken=${response.syncToken} '
        'events=${response.events.length} hasMore=${response.hasMore}',
      );

      if (_requiresBootstrapRefresh(response) ||
          _deltaBacklogRequiresBootstrap(response, since)) {
        debugPrint(
          '[LibrarySyncEngine][_applyDeltaChanges] bootstrap refresh required '
          'since=$since syncToken=${response.syncToken}',
        );
        final readyAfterBootstrap = await _runBootstrapSync();
        if (!readyAfterBootstrap) {
          _scheduleBootstrapRetryBackoff();
        } else {
          _clearBootstrapRetryBackoff();
        }
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
      debugPrint(
        '[LibrarySyncEngine][_applyDeltaChanges] nextSince='
        '${nextState.lastAppliedToken} progressed=$progressed '
        'bootstrapComplete=${nextState.bootstrapComplete}',
      );

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

  bool _deltaBacklogRequiresBootstrap(
    V2ChangesResponse response,
    int since,
  ) {
    if (maxDeltaTokenGapBeforeBootstrap <= 0) return false;
    final latestToken = response.syncToken > response.toToken
        ? response.syncToken
        : response.toToken;
    return latestToken - since > maxDeltaTokenGapBeforeBootstrap;
  }

  bool _isBootstrapRetryDeferred() {
    final retryAt = _nextBootstrapRetryAt;
    if (retryAt == null) return false;
    return DateTime.now().isBefore(retryAt);
  }

  void _scheduleBootstrapRetryBackoff() {
    _bootstrapRetryAttempts += 1;
    final index = _bootstrapRetryAttempts - 1;
    final boundedIndex = index < 0
        ? 0
        : (index >= _bootstrapRetryScheduleSeconds.length
            ? _bootstrapRetryScheduleSeconds.length - 1
            : index);
    final delay =
        Duration(seconds: _bootstrapRetryScheduleSeconds[boundedIndex]);
    _nextBootstrapRetryAt = DateTime.now().add(delay);

    debugPrint(
      '[LibrarySyncEngine][bootstrapBackoff] scheduled '
      'attempt=$_bootstrapRetryAttempts retryIn=${delay.inSeconds}s',
    );
  }

  void _clearBootstrapRetryBackoff() {
    if (_bootstrapRetryAttempts == 0 && _nextBootstrapRetryAt == null) {
      return;
    }
    _bootstrapRetryAttempts = 0;
    _nextBootstrapRetryAt = null;
  }

  Future<void> _enqueueSync(Future<void> Function() action) {
    final next = _syncQueue.then((_) async {
      if (_disposed) return;
      await action();
      _lastError = null;
      _lastSuccessfulSyncAt = DateTime.now();
    });
    _syncQueue = (() async {
      try {
        await next;
      } catch (error, stackTrace) {
        _lastError = error.toString();
        debugPrint(
          '[LibrarySyncEngine][_enqueueSync] swallowed sync error='
          '$error\n$stackTrace',
        );
      }
    }());
    return next;
  }
}
