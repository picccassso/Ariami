import 'package:flutter/foundation.dart';

import '../../models/api_models.dart';
import 'library_repository.dart';

enum LibraryReadSource {
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

/// Unified v2-only facade for locally synced library reads.
class LibraryReadFacade {
  LibraryReadFacade({
    required Object? Function() apiClientProvider,
    LibraryRepository? libraryRepository,
    Duration bootstrapWaitTimeout = const Duration(seconds: 2),
    Duration bootstrapPollInterval = const Duration(milliseconds: 100),
  })  : _apiClientProvider = apiClientProvider,
        _libraryRepository = libraryRepository ?? LibraryRepository(),
        _bootstrapWaitTimeout = bootstrapWaitTimeout,
        _bootstrapPollInterval = bootstrapPollInterval;

  final Object? Function() _apiClientProvider;
  final LibraryRepository _libraryRepository;
  final Duration _bootstrapWaitTimeout;
  final Duration _bootstrapPollInterval;

  Future<LibraryReadDecision> resolveSource({
    bool waitForBootstrap = false,
  }) async {
    final bootstrapComplete = waitForBootstrap
        ? await _waitForBootstrapCompletion()
        : await _libraryRepository.hasCompletedBootstrap();

    if (bootstrapComplete) {
      return const LibraryReadDecision(
        source: LibraryReadSource.v2LocalStore,
        reason: 'v2 local sync bootstrap is complete',
      );
    }

    return const LibraryReadDecision(
      source: LibraryReadSource.v2LocalStore,
      reason: 'v2 local sync bootstrap is still in progress; serving the '
          'current local catalog snapshot',
    );
  }

  Future<List<AlbumModel>> getAlbums() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getAlbums', decision);
    return _libraryRepository.getAlbums();
  }

  Future<List<SongModel>> getSongs() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getSongs', decision);
    return _libraryRepository.getSongs();
  }

  Future<AlbumModel?> getAlbumById(String albumId) async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getAlbumById', decision);
    return _libraryRepository.getAlbumById(albumId);
  }

  Future<List<SongModel>> getSongsByAlbumId(String albumId) async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getSongsByAlbumId', decision);
    return _libraryRepository.getSongsByAlbumId(albumId);
  }

  Future<AlbumDetailResponse?> getAlbumDetail(String albumId) async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getAlbumDetail', decision);

    final album = await _libraryRepository.getAlbumById(albumId);
    if (album == null) {
      return null;
    }

    final songs = await _libraryRepository.getSongsByAlbumId(albumId);
    return AlbumDetailResponse(
      id: album.id,
      title: album.title,
      artist: album.artist,
      coverArt: album.coverArt,
      year: null,
      songs: songs,
    );
  }

  Future<List<ServerPlaylist>> getServerPlaylists() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getServerPlaylists', decision);
    return _libraryRepository.getServerPlaylists();
  }

  Future<int?> getActiveLastAppliedToken() async {
    if (!await _libraryRepository.hasCompletedBootstrap()) {
      return null;
    }
    final syncState = await _libraryRepository.getSyncState();
    return syncState.lastAppliedToken;
  }

  Future<LibraryReadBundle> getLibraryBundle() async {
    final decision = await resolveSource(waitForBootstrap: true);
    _logDecision('getLibraryBundle', decision);

    final localBundle = await _libraryRepository.getLibraryBundle();
    return LibraryReadBundle(
      albums: localBundle.albums,
      songs: localBundle.songs,
      serverPlaylists: localBundle.serverPlaylists,
      durationsReady: _durationsReady(localBundle.songs),
      source: decision.source,
      sourceReason: decision.reason,
    );
  }

  Future<bool> _waitForBootstrapCompletion() async {
    if (await _libraryRepository.hasCompletedBootstrap()) {
      return true;
    }

    if (_bootstrapWaitTimeout <= Duration.zero ||
        _apiClientProvider() == null) {
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

  void _logDecision(String operation, LibraryReadDecision decision) {
    debugPrint(
      '[LibraryReadFacade][$operation] source=v2_local_store '
      'reason=${decision.reason}',
    );
  }

  bool _durationsReady(List<SongModel> songs) {
    if (songs.isEmpty) {
      return true;
    }
    return songs.every((song) => song.duration > 0);
  }
}
