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
    this.bootstrapPageLimit = 500,
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
  String? _bootstrapCursor;
  int _bootstrapLatestToken = 0;
  int _bootstrapPagesProcessed = 0;
  String? _bootstrapScope;

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
    final apiClient = _apiClientProvider();
    final scope =
        '${apiClient.serverInfo.baseUrl}|${apiClient.sessionToken ?? ''}';
    if (_bootstrapScope != scope) {
      await _discardBootstrapResume();
      _bootstrapScope = scope;
    }
    if (_bootstrapCursor == null) {
      await _libraryRepository.resetForBootstrap();
      _bootstrapLatestToken = 0;
      _bootstrapPagesProcessed = 0;
    }

    try {
      var cursor = _bootstrapCursor;
      var latestToken = _bootstrapLatestToken;
      var pagesProcessed = _bootstrapPagesProcessed;

      while (true) {
        final page =
            await apiClient.getV2BootstrapPage(cursor, bootstrapPageLimit);
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
        _bootstrapCursor = cursor;
        _bootstrapLatestToken = latestToken;
        _bootstrapPagesProcessed = pagesProcessed;

        // Safety guard against malformed pagination loops.
        if (pagesProcessed > 10000) {
          break;
        }
      }

      await _libraryRepository.completeBootstrap(lastAppliedToken: latestToken);
      _clearBootstrapResume();
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
      // If at least one page committed, retain the staging rows and cursor so a
      // transient mobile drop resumes rather than downloading the catalog from
      // page one again. A first-page failure has nothing useful to retain.
      if (_bootstrapCursor == null) {
        await _libraryRepository.abortBootstrap();
      }
      rethrow;
    }
  }

  Future<void> _discardBootstrapResume() async {
    if (_bootstrapScope != null || _bootstrapCursor != null) {
      await _libraryRepository.abortBootstrap();
    }
    _clearBootstrapResume();
  }

  void _clearBootstrapResume() {
    _bootstrapCursor = null;
    _bootstrapLatestToken = 0;
    _bootstrapPagesProcessed = 0;
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

      if (_requiresBootstrapRefresh(response)) {
        debugPrint(
          '[LibrarySyncEngine][_applyDeltaChanges] bootstrap refresh required '
          'because at least one upsert payload was null',
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
