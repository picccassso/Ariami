import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:ariami_mobile/services/sync/library_sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibrarySyncEngine', () {
    test('bootstraps fully across paginated bootstrap pages', () async {
      final repository = _FakeLibraryRepository();
      final apiClient = _FakeApiClient(
        bootstrapResponses: <V2BootstrapResponse>[
          _bootstrapPage(
            syncToken: 3,
            hasMore: true,
            cursor: null,
            nextCursor: 'cursor-1',
          ),
          _bootstrapPage(
            syncToken: 4,
            hasMore: false,
            cursor: 'cursor-1',
            nextCursor: null,
          ),
        ],
      );

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
      );

      await engine.syncNow();

      final state = await repository.getSyncState();
      expect(state.bootstrapComplete, isTrue);
      expect(state.lastAppliedToken, 4);
      expect(repository.resetCount, 1);
      expect(repository.bootstrapPagesApplied, 2);
      expect(apiClient.bootstrapCallCount, 2);
      expect(apiClient.changesCallCount, 0);
    });

    test('emits bootstrap completion callback after local bootstrap', () async {
      final repository = _FakeLibraryRepository();
      final apiClient = _FakeApiClient(
        bootstrapResponses: <V2BootstrapResponse>[
          _bootstrapPage(
            syncToken: 6,
            hasMore: false,
            cursor: null,
            nextCursor: null,
          ),
        ],
      );
      int? completedToken;

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
        onBootstrapCompleted: (latestToken) async {
          completedToken = latestToken;
        },
      );

      await engine.syncNow();

      expect(completedToken, equals(6));
    });

    test('suppresses bootstrap completion callback when readiness is pending',
        () async {
      final repository = _AlwaysBackfillPendingLibraryRepository();
      final apiClient = _FakeApiClient(
        bootstrapResponses: <V2BootstrapResponse>[
          _bootstrapPage(
            syncToken: 10,
            hasMore: false,
            cursor: null,
            nextCursor: null,
          ),
        ],
      );
      int callbackCount = 0;

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
        onBootstrapCompleted: (_) async {
          callbackCount += 1;
        },
      );

      await engine.syncNow();
      await engine.syncNow();

      expect(callbackCount, equals(0));
      expect(apiClient.bootstrapCallCount, equals(1));
      expect(repository.resetCount, equals(1));
    });

    test('falls back to bootstrap when change upsert payload is null',
        () async {
      final repository = _FakeLibraryRepository(
        initialState: const LibrarySyncState(
          lastAppliedToken: 5,
          bootstrapComplete: true,
          lastSyncEpochMs: 0,
        ),
      );
      final apiClient = _FakeApiClient(
        bootstrapResponses: <V2BootstrapResponse>[
          _bootstrapPage(
            syncToken: 9,
            hasMore: false,
            cursor: null,
            nextCursor: null,
          ),
        ],
        changesResponses: <V2ChangesResponse>[
          V2ChangesResponse(
            fromToken: 5,
            toToken: 6,
            events: <V2ChangeEvent>[
              const V2ChangeEvent(
                token: 6,
                op: V2ChangeOp.upsert,
                entityType: V2EntityType.song,
                entityId: 'song-1',
                payload: null,
                occurredAt: '2026-02-07T20:00:00Z',
              ),
            ],
            hasMore: false,
            syncToken: 9,
          ),
        ],
      );

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
      );

      await engine.syncUntil(9);

      final state = await repository.getSyncState();
      expect(state.bootstrapComplete, isTrue);
      expect(state.lastAppliedToken, 9);
      expect(repository.resetCount, 1);
      expect(repository.bootstrapPagesApplied, 1);
      expect(apiClient.changesCallCount, 1);
      expect(apiClient.bootstrapCallCount, 1);
    });

    test('syncUntil is idempotent when target token already applied', () async {
      final repository = _FakeLibraryRepository(
        initialState: const LibrarySyncState(
          lastAppliedToken: 10,
          bootstrapComplete: true,
          lastSyncEpochMs: 0,
        ),
      );
      final apiClient = _FakeApiClient(
        changesResponses: <V2ChangesResponse>[
          V2ChangesResponse(
            fromToken: 10,
            toToken: 12,
            events: <V2ChangeEvent>[
              const V2ChangeEvent(
                token: 12,
                op: V2ChangeOp.upsert,
                entityType: V2EntityType.song,
                entityId: 'song-12',
                payload: <String, dynamic>{
                  'id': 'song-12',
                  'title': 'Song 12',
                  'artist': 'Artist',
                  'albumId': null,
                  'duration': 123,
                },
                occurredAt: '2026-02-07T21:00:00Z',
              ),
            ],
            hasMore: false,
            syncToken: 12,
          ),
        ],
      );

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
      );

      await engine.syncUntil(12);
      await engine.syncUntil(12);

      final state = await repository.getSyncState();
      expect(state.lastAppliedToken, 12);
      expect(state.bootstrapComplete, isTrue);

      // The second call should short-circuit (since >= target token),
      // avoiding duplicate delta re-application.
      expect(apiClient.changesCallCount, 1);
      expect(apiClient.bootstrapCallCount, 0);
    });

    test('bootstrap failure preserves last known good local sync state',
        () async {
      final repository = _FakeLibraryRepository(
        initialState: const LibrarySyncState(
          lastAppliedToken: 8,
          bootstrapComplete: true,
          lastSyncEpochMs: 0,
        ),
      );
      final apiClient = _FakeApiClient(
        bootstrapResponses: const <V2BootstrapResponse>[],
        changesResponses: <V2ChangesResponse>[
          V2ChangesResponse(
            fromToken: 8,
            toToken: 9,
            events: <V2ChangeEvent>[
              const V2ChangeEvent(
                token: 9,
                op: V2ChangeOp.upsert,
                entityType: V2EntityType.song,
                entityId: 'song-9',
                payload: null,
                occurredAt: '2026-02-07T23:00:00Z',
              ),
            ],
            hasMore: false,
            syncToken: 9,
          ),
        ],
      );

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
      );

      await expectLater(engine.syncNow(), throwsA(isA<StateError>()));

      final state = await repository.getSyncState();
      expect(state.lastAppliedToken, 8);
      expect(state.bootstrapComplete, isTrue);
      expect(repository.resetCount, 1);
      expect(repository.abortCount, 1);
    });

    test(
        're-runs bootstrap when synced state is marked complete but backfill is pending',
        () async {
      final repository = _BackfillPendingLibraryRepository(
        initialState: const LibrarySyncState(
          lastAppliedToken: 8,
          bootstrapComplete: true,
          lastSyncEpochMs: 0,
        ),
      );
      final apiClient = _FakeApiClient(
        bootstrapResponses: <V2BootstrapResponse>[
          _bootstrapPage(
            syncToken: 11,
            hasMore: false,
            cursor: null,
            nextCursor: null,
          ),
        ],
      );

      final engine = LibrarySyncEngine(
        apiClientProvider: () => apiClient,
        libraryRepository: repository,
      );

      await engine.syncNow();

      final state = await repository.getSyncState();
      expect(state.bootstrapComplete, isTrue);
      expect(state.lastAppliedToken, 11);
      expect(repository.resetCount, 1);
      expect(repository.bootstrapPagesApplied, 1);
      expect(apiClient.bootstrapCallCount, 1);
      expect(apiClient.changesCallCount, 0);
    });
  });
}

V2BootstrapResponse _bootstrapPage({
  required int syncToken,
  required bool hasMore,
  required String? cursor,
  required String? nextCursor,
}) {
  return V2BootstrapResponse(
    syncToken: syncToken,
    albums: const <AlbumModel>[],
    songs: const <SongModel>[],
    playlists: const <V2PlaylistModel>[],
    pageInfo: V2PageInfo(
      cursor: cursor,
      nextCursor: nextCursor,
      hasMore: hasMore,
      limit: 200,
    ),
  );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    List<V2BootstrapResponse>? bootstrapResponses,
    List<V2ChangesResponse>? changesResponses,
  })  : _bootstrapResponses = List<V2BootstrapResponse>.from(
          bootstrapResponses ?? const <V2BootstrapResponse>[],
        ),
        _changesResponses = List<V2ChangesResponse>.from(
          changesResponses ?? const <V2ChangesResponse>[],
        ),
        super(
          serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: 8080,
            name: 'test',
            version: 'test',
          ),
        );

  final List<V2BootstrapResponse> _bootstrapResponses;
  final List<V2ChangesResponse> _changesResponses;

  int bootstrapCallCount = 0;
  int changesCallCount = 0;

  @override
  Future<V2BootstrapResponse> getV2BootstrapPage(
    String? cursor,
    int limit,
  ) async {
    bootstrapCallCount += 1;
    if (_bootstrapResponses.isEmpty) {
      throw StateError('No bootstrap response queued');
    }
    return _bootstrapResponses.removeAt(0);
  }

  @override
  Future<V2ChangesResponse> getV2Changes(int since, int limit) async {
    changesCallCount += 1;
    if (_changesResponses.isEmpty) {
      return V2ChangesResponse(
        fromToken: since,
        toToken: since,
        events: const <V2ChangeEvent>[],
        hasMore: false,
        syncToken: since,
      );
    }
    return _changesResponses.removeAt(0);
  }
}

class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository({
    LibrarySyncState initialState = const LibrarySyncState(
      lastAppliedToken: 0,
      bootstrapComplete: false,
      lastSyncEpochMs: 0,
    ),
  })  : _state = initialState,
        super(database: _FakeLibrarySyncDatabase());

  LibrarySyncState _state;
  int resetCount = 0;
  int bootstrapPagesApplied = 0;
  int abortCount = 0;

  @override
  Future<LibrarySyncState> getSyncState() async => _state;

  @override
  Future<bool> hasCompletedBootstrap() async => _state.bootstrapComplete;

  @override
  Future<void> resetForBootstrap() async {
    resetCount += 1;
  }

  @override
  Future<void> applyBootstrapPage(V2BootstrapResponse page) async {
    bootstrapPagesApplied += 1;
    _state = LibrarySyncState(
      lastAppliedToken: page.syncToken,
      bootstrapComplete: false,
      lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> completeBootstrap({required int lastAppliedToken}) async {
    _state = LibrarySyncState(
      lastAppliedToken: lastAppliedToken,
      bootstrapComplete: true,
      lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> abortBootstrap() async {
    abortCount += 1;
  }

  @override
  Future<void> applyChangesResponse(V2ChangesResponse response) async {
    final effectiveToken =
        response.toToken > 0 ? response.toToken : response.syncToken;
    _state = LibrarySyncState(
      lastAppliedToken: effectiveToken,
      bootstrapComplete: true,
      lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> updateSyncState({
    required int lastAppliedToken,
    required bool bootstrapComplete,
  }) async {
    _state = LibrarySyncState(
      lastAppliedToken: lastAppliedToken,
      bootstrapComplete: bootstrapComplete,
      lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class _FakeLibrarySyncDatabase extends LibrarySyncDatabase {}

class _BackfillPendingLibraryRepository extends _FakeLibraryRepository {
  _BackfillPendingLibraryRepository({
    required super.initialState,
  });

  bool _backfillPending = true;

  @override
  Future<bool> hasCompletedBootstrap() async {
    return !_backfillPending && await super.hasCompletedBootstrap();
  }

  @override
  Future<void> completeBootstrap({required int lastAppliedToken}) async {
    await super.completeBootstrap(lastAppliedToken: lastAppliedToken);
    _backfillPending = false;
  }
}

class _AlwaysBackfillPendingLibraryRepository extends _FakeLibraryRepository {
  @override
  Future<bool> hasCompletedBootstrap() async => false;
}
