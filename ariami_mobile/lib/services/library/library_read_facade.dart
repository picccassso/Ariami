import '../../models/api_models.dart';
import '../api/api_client.dart';
import 'library_repository.dart';

enum LibraryReadSource {
  v1Snapshot,
  v2LocalStore,
}

class LibraryReadDecision {
  const LibraryReadDecision({
    required this.source,
    required this.reason,
  });

  final LibraryReadSource source;
  final String reason;
}

class LibraryReadBundle {
  const LibraryReadBundle({
    required this.albums,
    required this.songs,
    required this.serverPlaylists,
    required this.durationsReady,
    required this.source,
    required this.sourceReason,
  });

  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<ServerPlaylist> serverPlaylists;
  final bool durationsReady;
  final LibraryReadSource source;
  final String sourceReason;
}

/// Unified read facade for library data source resolution.
///
/// Source decision:
/// - v2 local store only when v2 rollout is enabled and bootstrap is complete.
/// - otherwise fallback to v1 compatibility snapshot endpoint.
class LibraryReadFacade {
  LibraryReadFacade({
    required ApiClient? Function() apiClientProvider,
    LibraryRepository? libraryRepository,
    bool? useV2SyncStoreOverride,
  })  : _apiClientProvider = apiClientProvider,
        _libraryRepository = libraryRepository ?? LibraryRepository(),
        _useV2SyncStoreOverride = useV2SyncStoreOverride;

  static const bool _useV2SyncStoreByDefault = bool.fromEnvironment(
    'ARIAMI_USE_V2_SYNC_STORE',
    defaultValue: false,
  );

  final ApiClient? Function() _apiClientProvider;
  final LibraryRepository _libraryRepository;
  final bool? _useV2SyncStoreOverride;

  bool get _useV2SyncStore =>
      _useV2SyncStoreOverride ?? _useV2SyncStoreByDefault;

  Future<LibraryReadDecision> resolveSource() async {
    if (!_useV2SyncStore) {
      return const LibraryReadDecision(
        source: LibraryReadSource.v1Snapshot,
        reason: 'v2 rollout disabled by ARIAMI_USE_V2_SYNC_STORE=false',
      );
    }

    final bootstrapComplete = await _libraryRepository.hasCompletedBootstrap();
    if (!bootstrapComplete) {
      return const LibraryReadDecision(
        source: LibraryReadSource.v1Snapshot,
        reason: 'v2 rollout enabled but local sync bootstrap is incomplete',
      );
    }

    return const LibraryReadDecision(
      source: LibraryReadSource.v2LocalStore,
      reason: 'v2 rollout enabled and local sync bootstrap is complete',
    );
  }

  Future<List<AlbumModel>> getAlbums() async {
    final decision = await resolveSource();
    _logDecision('getAlbums', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      return _libraryRepository.getAlbums();
    }

    final library = await _getV1LibrarySnapshot(decision);
    return library.albums;
  }

  Future<List<SongModel>> getSongs() async {
    final decision = await resolveSource();
    _logDecision('getSongs', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      return _libraryRepository.getSongs();
    }

    final library = await _getV1LibrarySnapshot(decision);
    return library.songs;
  }

  Future<List<ServerPlaylist>> getServerPlaylists() async {
    final decision = await resolveSource();
    _logDecision('getServerPlaylists', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      return _libraryRepository.getServerPlaylists();
    }

    final library = await _getV1LibrarySnapshot(decision);
    return library.serverPlaylists;
  }

  Future<int?> getActiveLastAppliedToken() async {
    final decision = await resolveSource();
    if (decision.source != LibraryReadSource.v2LocalStore) {
      return null;
    }
    final syncState = await _libraryRepository.getSyncState();
    return syncState.lastAppliedToken;
  }

  Future<LibraryReadBundle> getLibraryBundle() async {
    final decision = await resolveSource();
    _logDecision('getLibraryBundle', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      final localBundle = await _libraryRepository.getLibraryBundle();
      return LibraryReadBundle(
        albums: localBundle.albums,
        songs: localBundle.songs,
        serverPlaylists: localBundle.serverPlaylists,
        durationsReady: true,
        source: decision.source,
        sourceReason: decision.reason,
      );
    }

    final library = await _getV1LibrarySnapshot(decision);
    return LibraryReadBundle(
      albums: library.albums,
      songs: library.songs,
      serverPlaylists: library.serverPlaylists,
      durationsReady: library.durationsReady,
      source: decision.source,
      sourceReason: decision.reason,
    );
  }

  Future<LibraryResponse> _getV1LibrarySnapshot(
    LibraryReadDecision decision,
  ) async {
    final apiClient = _apiClientProvider();
    if (apiClient == null) {
      throw StateError(
        'Cannot read v1 library snapshot: API client unavailable '
        '(source fallback reason: ${decision.reason})',
      );
    }
    return apiClient.getLibrary();
  }

  void _logDecision(String operation, LibraryReadDecision decision) {
    final source = decision.source == LibraryReadSource.v2LocalStore
        ? 'v2_local_store'
        : 'v1_snapshot';
    print(
        '[LibraryReadFacade][$operation] source=$source reason=${decision.reason}');
  }
}
