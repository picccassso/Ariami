import '../../models/api_models.dart';
import 'package:flutter/foundation.dart';
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
    Duration bootstrapWaitTimeout = const Duration(seconds: 2),
    Duration bootstrapPollInterval = const Duration(milliseconds: 100),
  })  : _apiClientProvider = apiClientProvider,
        _libraryRepository = libraryRepository ?? LibraryRepository(),
        _useV2SyncStoreOverride = useV2SyncStoreOverride,
        _bootstrapWaitTimeout = bootstrapWaitTimeout,
        _bootstrapPollInterval = bootstrapPollInterval;

  static const bool _useV2SyncStoreByDefault = bool.fromEnvironment(
    'ARIAMI_USE_V2_SYNC_STORE',
    defaultValue: true,
  );

  final ApiClient? Function() _apiClientProvider;
  final LibraryRepository _libraryRepository;
  final bool? _useV2SyncStoreOverride;
  final Duration _bootstrapWaitTimeout;
  final Duration _bootstrapPollInterval;

  bool get _useV2SyncStore =>
      _useV2SyncStoreOverride ?? _useV2SyncStoreByDefault;

  Future<LibraryReadDecision> resolveSource({
    bool waitForBootstrap = false,
  }) async {
    if (!_useV2SyncStore) {
      return const LibraryReadDecision(
        source: LibraryReadSource.v1Snapshot,
        reason: 'v2 rollout disabled by ARIAMI_USE_V2_SYNC_STORE=false',
      );
    }

    var bootstrapComplete = await _libraryRepository.hasCompletedBootstrap();
    if (!bootstrapComplete && waitForBootstrap) {
      bootstrapComplete = await _waitForBootstrapCompletion();
      if (bootstrapComplete) {
        return LibraryReadDecision(
          source: LibraryReadSource.v2LocalStore,
          reason: 'v2 rollout enabled and local sync bootstrap completed '
              'during startup grace wait',
        );
      }
    }

    if (!bootstrapComplete) {
      return LibraryReadDecision(
        source: LibraryReadSource.v1Snapshot,
        reason: waitForBootstrap
            ? 'v2 rollout enabled but local sync bootstrap remained incomplete '
                'after startup grace wait'
            : 'v2 rollout enabled but local sync bootstrap is incomplete',
      );
    }

    return const LibraryReadDecision(
      source: LibraryReadSource.v2LocalStore,
      reason: 'v2 rollout enabled and local sync bootstrap is complete',
    );
  }

  Future<List<AlbumModel>> getAlbums() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getAlbums', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      return _libraryRepository.getAlbums();
    }

    final library = await _getV1LibrarySnapshot(decision);
    return library.albums;
  }

  Future<List<SongModel>> getSongs() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getSongs', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      return _libraryRepository.getSongs();
    }

    final library = await _getV1LibrarySnapshot(decision);
    return library.songs;
  }

  Future<List<ServerPlaylist>> getServerPlaylists() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getServerPlaylists', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      final localPlaylists = await _libraryRepository.getServerPlaylists();
      if (_needsServerPlaylistHydration(localPlaylists)) {
        final library = await _getV1LibrarySnapshot(
          LibraryReadDecision(
            source: LibraryReadSource.v1Snapshot,
            reason: 'v2 local store playlists are missing songIds after '
                'bootstrap; hydrating server playlists from v1 snapshot',
          ),
        );
        return library.serverPlaylists;
      }
      return localPlaylists;
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
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getLibraryBundle', decision);

    if (decision.source == LibraryReadSource.v2LocalStore) {
      final localBundle = await _libraryRepository.getLibraryBundle();
      var sourceReason = decision.reason;
      var serverPlaylists = localBundle.serverPlaylists;

      if (_needsServerPlaylistHydration(serverPlaylists)) {
        final library = await _getV1LibrarySnapshot(
          LibraryReadDecision(
            source: LibraryReadSource.v1Snapshot,
            reason: 'v2 local store playlists are missing songIds after '
                'bootstrap; hydrating server playlists from v1 snapshot',
          ),
        );
        serverPlaylists = library.serverPlaylists;
        sourceReason =
            '${decision.reason}; server playlists hydrated from v1 snapshot '
            'because local playlist song membership is incomplete';
      }

      return LibraryReadBundle(
        albums: localBundle.albums,
        songs: localBundle.songs,
        serverPlaylists: serverPlaylists,
        durationsReady: true,
        source: decision.source,
        sourceReason: sourceReason,
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

  Future<bool> _waitForBootstrapCompletion() async {
    if (_bootstrapWaitTimeout <= Duration.zero) {
      return false;
    }

    final deadline = DateTime.now().add(_bootstrapWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_bootstrapPollInterval);
      if (await _libraryRepository.hasCompletedBootstrap()) {
        return true;
      }
    }
    return false;
  }

  bool _needsServerPlaylistHydration(List<ServerPlaylist> playlists) {
    return playlists.any(
      (playlist) => playlist.songCount > 0 && playlist.songIds.isEmpty,
    );
  }

  void _logDecision(String operation, LibraryReadDecision decision) {
    final source = decision.source == LibraryReadSource.v2LocalStore
        ? 'v2_local_store'
        : 'v1_snapshot';
    debugPrint(
        '[LibraryReadFacade][$operation] source=$source reason=${decision.reason}');
  }
}
