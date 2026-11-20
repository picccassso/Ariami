import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/services/library/library_artist_index.dart';
import 'package:ariami_core/services/library/library_genre_index.dart';
import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:ariami_core/services/search/search.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:ariami_core/models/library_curation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import '../widgets/artwork_image_provider.dart';
import 'player_api_client.dart';
import 'player_host.dart';
import 'search_settings_service.dart';

export 'package:ariami_core/services/library/library_genre_index.dart'
    show LibraryGenreIndex;

part 'library_controller/library_controller_artists.dart';
part 'library_controller/library_controller_browsing.dart';
part 'library_controller/library_controller_genres.dart';
part 'library_controller/library_controller_hidden.dart';
part 'library_controller/library_controller_loading.dart';
part 'library_controller/library_controller_persistence.dart';
part 'library_controller/library_controller_playlists.dart';

/// Schema version of the on-disk library snapshot.
///
/// Bump this whenever the JSON shape written by [Track], [Album] or
/// [PlaylistSummary] changes. A snapshot from another version is still shown,
/// but its sync token is discarded so the catalog is refetched in full:
/// a client that does not understand a new field still applies the change
/// events and advances the token, which would otherwise hide that field
/// forever.
const int desktopLibrarySnapshotVersion = 2;

class LibraryController extends ChangeNotifier {
  LibraryController({
    SearchSettingsService? searchSettings,
    LibrarySnapshotStore? snapshotStore,
  })  : _searchSettings = searchSettings ?? SearchSettingsService(),
        _snapshotStore = snapshotStore {
    _searchSettings.addListener(_onSearchSettingsChanged);
  }

  final SearchSettingsService _searchSettings;
  final LibrarySnapshotStore? _snapshotStore;
  SearchSettingsService get searchSettings => _searchSettings;

  PlayerApiClient? _client;
  PlayerApiClient? get client => _client;
  String? _accountKey;

  static const _preferencesPrefix = 'desktop_library_preferences_v1_';

  /// True while the library content came from the offline snapshot rather
  /// than a live server.
  bool _isOfflineSnapshot = false;
  bool get isOfflineSnapshot => _isOfflineSnapshot;

  final Map<String, PlaylistEdit> _playlistEdits = <String, PlaylistEdit>{};
  final Map<String, PlaylistEdit> _pendingPlaylistEdits =
      <String, PlaylistEdit>{};
  bool _isSyncingPendingPlaylistEdits = false;
  String? _activeSnapshotScope;

  /// Synced custom cover images (playlist id -> image version) from the
  /// server's manifest. The version cache-busts replaced images.
  final Map<String, int> _playlistImageVersions = <String, int>{};

  int? playlistImageVersion(String playlistId) =>
      _playlistImageVersions[playlistId];

  /// Synced custom artist photos (normalized artist key -> image version) from
  /// the server's manifest. The version cache-busts replaced images.
  final Map<String, int> _artistImageVersions = <String, int>{};

  int? artistImageVersion(String artistName) =>
      _artistImageVersions[normalizeArtistKey(artistName)];

  Future<void> refreshArtistImages() => _refreshArtistImages();
  Future<void> setArtistImage(
    String artistName, {
    required Uint8List bytes,
    required String contentType,
  }) =>
      _setArtistImage(artistName, bytes: bytes, contentType: contentType);
  Future<void> removeArtistImage(String artistName) =>
      _removeArtistImage(artistName);
  final Map<String, String> _pendingLegacyPlaylistNames = <String, String>{};
  final Map<String, List<String>> _pendingLegacyPlaylistSongs =
      <String, List<String>>{};
  final Set<String> _hiddenPlaylistIds = <String>{};
  final Set<String> _pinnedItemIds = <String>{};
  List<PinnedMediaItem> _pins = const <PinnedMediaItem>[];
  List<PinnedMediaItem> get pins {
    _ensureFilteredCatalog();
    return _filteredPins;
  }

  List<PinnedMediaItem> get rawPins => _pins;

  /// Account-synced hidden items, keyed `type:targetId`. Distinct from
  /// [_hiddenPlaylistIds], which is this device's record of server playlists
  /// deleted from the desktop library.
  final Set<String> _hiddenKeys = <String>{};
  List<HiddenMediaItem> _hiddenItems = const <HiddenMediaItem>[];

  /// Everything the account has hidden, oldest first — the Settings list that
  /// is the only way back.
  List<HiddenMediaItem> get hiddenItems => _hiddenItems;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<Album> _albums = const <Album>[];
  List<Album> get albums {
    _ensureFilteredCatalog();
    return _filteredAlbums;
  }

  List<Album> get rawAlbums => _albums;

  List<Track> _songs = const <Track>[];
  List<Track> get songs {
    _ensureFilteredCatalog();
    return _filteredSongs;
  }

  List<Track> get rawSongs => _songs;

  List<PlaylistSummary> _basePlaylists = const <PlaylistSummary>[];
  List<PlaylistSummary> _playlists = const <PlaylistSummary>[];
  List<PlaylistSummary> get playlists {
    _ensureFilteredCatalog();
    return _filteredPlaylists;
  }

  List<PlaylistSummary> get rawServerPlaylists => _basePlaylists;
  List<PlaylistSummary> get rawPlaylists => _playlists;

  UserLibraryCuration _curation = UserLibraryCuration.defaultForUser(
    '',
    onboardingCompleted: true,
  );
  UserLibraryCuration get curation => _curation;
  LibraryCurationFilter _curationFilter = LibraryCurationFilter.unrestricted;
  LibraryCurationFilter get curationFilter => _curationFilter;
  int _curationVersion = 0;
  bool _curationLoaded = false;
  bool get curationLoaded => _curationLoaded;
  bool get needsCurationOnboarding =>
      _curationLoaded && !_curation.onboardingCompleted && hasContent;

  List<Album>? _filteredAlbumsRef;
  List<Track>? _filteredSongsRef;
  List<PlaylistSummary>? _filteredPlaylistsRef;
  List<PinnedMediaItem>? _filteredPinsRef;
  int _filteredCurationVersion = -1;
  List<Album> _filteredAlbums = const <Album>[];
  List<Track> _filteredSongs = const <Track>[];
  List<PlaylistSummary> _filteredPlaylists = const <PlaylistSummary>[];
  List<PinnedMediaItem> _filteredPins = const <PinnedMediaItem>[];

  void _ensureFilteredCatalog() {
    if (identical(_filteredAlbumsRef, _albums) &&
        identical(_filteredSongsRef, _songs) &&
        identical(_filteredPlaylistsRef, _playlists) &&
        identical(_filteredPinsRef, _pins) &&
        _filteredCurationVersion == _curationVersion) {
      return;
    }
    _filteredAlbumsRef = _albums;
    _filteredSongsRef = _songs;
    _filteredPlaylistsRef = _playlists;
    _filteredPinsRef = _pins;
    _filteredCurationVersion = _curationVersion;

    if (_curationFilter.isPassThrough) {
      _filteredAlbums = _albums;
      _filteredSongs = _songs;
      _filteredPlaylists = _playlists;
      _filteredPins = _pins;
      return;
    }

    final albumArtistById = <String, String>{
      for (final album in _albums) album.id: album.artist,
    };
    _filteredAlbums = _curationFilter.filterAlbums(
      _albums,
      idOf: (a) => a.id,
      artistOf: (a) => a.artist,
    );
    _filteredSongs = _curationFilter.filterSongs(
      _songs,
      idOf: (s) => s.id,
      artistOf: (s) => s.artist,
      albumIdOf: (s) => s.albumId,
      albumArtistOf: (s) =>
          s.albumId != null ? albumArtistById[s.albumId!] : null,
    );
    _filteredPlaylists = _curationFilter.filterPlaylists(
      _playlists,
      idOf: (p) => p.id,
    );
    _filteredPins = _pins.where((pin) {
      if (pin.type == 'playlist') {
        return _curationFilter.isServerPlaylistIncluded(pin.targetId);
      }
      if (pin.type == 'album') {
        return _curationFilter.isAlbumIncluded(
          albumId: pin.targetId,
          artist: albumArtistById[pin.targetId],
        );
      }
      return true;
    }).toList(growable: false);
  }

  /// Song id → names of the playlists holding it, rebuilt lazily whenever
  /// [_playlists] is replaced (every playlist edit swaps in a new list).
  Map<String, Set<String>> _playlistNamesBySong = const {};
  List<PlaylistSummary>? _indexedPlaylists;

  /// Names of the playlists holding [songId]. O(1) per call, so every
  /// visible track row can ask on each build.
  Iterable<String> playlistNamesContaining(String songId) {
    final visiblePlaylists = playlists;
    if (!identical(_indexedPlaylists, visiblePlaylists)) {
      _indexedPlaylists = visiblePlaylists;
      _playlistNamesBySong = <String, Set<String>>{};
      for (final playlist in visiblePlaylists) {
        for (final id in playlist.songIds) {
          (_playlistNamesBySong[id] ??= <String>{}).add(playlist.name);
        }
      }
    }
    return _playlistNamesBySong[songId] ?? const <String>{};
  }

  List<Track> _recentSearches = const <Track>[];
  List<Track> get recentSearches => _recentSearches;
  int get recentSearchesLimit => _searchSettings.recentSearchesLimit;

  bool isAlbumPinned(String albumId) =>
      _pinnedItemIds.contains('album:$albumId');
  bool isPlaylistPinned(String playlistId) =>
      _pinnedItemIds.contains('playlist:$playlistId');

  bool isAlbumHidden(String albumId) =>
      _hiddenKeys.contains('${HiddenMediaItem.albumType}:$albumId');
  bool isPlaylistHidden(String playlistId) =>
      _hiddenKeys.contains('${HiddenMediaItem.playlistType}:$playlistId');

  /// Artists have no catalog id, so the display name is the key — the same
  /// string the sidebar renders and the Hide action sends.
  bool isArtistHidden(String name) =>
      _hiddenKeys.contains('${HiddenMediaItem.artistType}:$name');

  /// Whether [playlistId] refers to a playlist created on this client rather
  /// than a folder playlist from the server.
  bool isCreatedPlaylist(String playlistId) => _isCreatedPlaylistId(playlistId);

  final Map<String, AlbumDetail> _albumDetailCache = <String, AlbumDetail>{};

  /// Last catalog change token applied to the in-memory library (0 = none).
  /// Persisted with the snapshot so a relaunch can resume from `/v2/changes`
  /// instead of refetching the whole catalog.
  int _syncToken = 0;
  @visibleForTesting
  int get syncToken => _syncToken;

  Timer? _syncTokenDebounce;
  bool _deltaSyncInFlight = false;
  int _pendingSyncTarget = 0;

  /// Debounce for `sync_token_advanced` bursts during library scans.
  @visibleForTesting
  Duration syncTokenDebounceDuration = const Duration(seconds: 2);

  bool get hasContent =>
      _albums.isNotEmpty || _songs.isNotEmpty || _playlists.isNotEmpty;

  bool get hasVisibleContent =>
      albums.isNotEmpty || songs.isNotEmpty || playlists.isNotEmpty;

  /// Binds the active API client. Clears cached data when the client changes.
  void attach(PlayerApiClient? client, {String? accountKey}) {
    final nextAccountKey = client == null
        ? null
        : (accountKey?.trim().isNotEmpty ?? false)
            ? accountKey!.trim()
            : client.baseUrl;
    if (identical(_client, client) && _accountKey == nextAccountKey) return;
    _client = client;
    _accountKey = nextAccountKey;
    _activeSnapshotScope = _preferencesKey;
    _albums = const <Album>[];
    _songs = const <Track>[];
    _basePlaylists = const <PlaylistSummary>[];
    _playlists = const <PlaylistSummary>[];
    _albumDetailCache.clear();
    _playlistEdits.clear();
    _pendingPlaylistEdits.clear();
    _playlistImageVersions.clear();
    _artistImageVersions.clear();
    _pendingLegacyPlaylistNames.clear();
    _pendingLegacyPlaylistSongs.clear();
    _hiddenPlaylistIds.clear();
    _pinnedItemIds.clear();
    _pins = const <PinnedMediaItem>[];
    _hiddenKeys.clear();
    _hiddenItems = const <HiddenMediaItem>[];
    _curation = UserLibraryCuration.defaultForUser(
      '',
      onboardingCompleted: true,
    );
    _curationFilter = LibraryCurationFilter.unrestricted;
    _curationVersion++;
    _curationLoaded = false;
    _recentSearches = const <Track>[];
    _genreFilter = null;
    _isOfflineSnapshot = false;
    _syncToken = 0;
    _syncTokenDebounce?.cancel();
    _pendingSyncTarget = 0;
    _clearBootstrapResume();
    _bootstrapResumeClient = null;
    _curatedSearchSlot.dispose();
    _fullSearchSlot.dispose();
    _error = null;
    notifyListeners();
  }

  /// Resumable bootstrap state. Survives a failed [load] so the next attempt
  /// (typically a reconnect after a poor-connection drop) continues from the
  /// last completed page instead of refetching the catalog from page one.
  /// In-memory only: a process restart starts the bootstrap over.
  PlayerApiClient? _bootstrapResumeClient;
  String? _bootstrapCursor;
  int _bootstrapMinToken = 0;
  final Map<String, Album> _bootstrapAlbums = <String, Album>{};
  final Map<String, Track> _bootstrapSongs = <String, Track>{};
  final Map<String, PlaylistSummary> _bootstrapPlaylists =
      <String, PlaylistSummary>{};

  /// Song-lookup map, rebuilt only when the underlying [_songs] list changes.
  /// Rebuilding this O(all-songs) map on every [playlistTracks] call was a
  /// real cost for large libraries, since callers rebuild many times a second.
  List<Track>? _songsByIdRef;
  Map<String, Track> _songsByIdCache = const <String, Track>{};
  Map<String, Track> get _songsById {
    if (!identical(_songsByIdRef, _songs)) {
      _songsByIdRef = _songs;
      _songsByIdCache = {for (final s in _songs) s.id: s};
    }
    return _songsByIdCache;
  }

  List<Album>? _albumsByIdRef;
  Map<String, Album> _albumsByIdCache = const <String, Album>{};
  int _backgroundWarmGeneration = 0;

  Map<String, Album> get _albumsById {
    if (!identical(_albumsByIdRef, _albums)) {
      _albumsByIdRef = _albums;
      _albumsByIdCache = {for (final a in _albums) a.id: a};
    }
    return _albumsByIdCache;
  }

  List<PlaylistSummary>? _playlistsByIdRef;
  Map<String, PlaylistSummary> _playlistsByIdCache =
      const <String, PlaylistSummary>{};
  Map<String, PlaylistSummary> get _playlistsById {
    if (!identical(_playlistsByIdRef, _playlists)) {
      _playlistsByIdRef = _playlists;
      _playlistsByIdCache = {for (final p in _playlists) p.id: p};
    }
    return _playlistsByIdCache;
  }

  final _SearchWorkerSlot _curatedSearchSlot = _SearchWorkerSlot();
  final _SearchWorkerSlot _fullSearchSlot = _SearchWorkerSlot();
  bool _disposed = false;

  /// Genre index, rebuilt only when the underlying [_songs] list changes.
  List<Track>? _genreIndexRef;
  LibraryGenreIndex _genreIndexCache = LibraryGenreIndex.empty;

  /// Artist index, rebuilt only when the underlying catalog lists change.
  List<Track>? _artistIndexSongsRef;
  List<Album>? _artistIndexAlbumsRef;
  List<PlaylistSummary>? _artistIndexPlaylistsRef;
  LibraryArtistIndex _artistIndexCache = LibraryArtistIndex.empty;

  /// Active genre facet in the albums view, or null for "All". Deliberately
  /// transient: a filter left on across a relaunch reads as a missing library.
  String? _genreFilter;

  ({String genre, List<Album> albums, List<Album> result})?
      _filteredAlbumsCache;

  /// Memoized [playlistTracks] results, keyed by playlist id. Invalidated when
  /// either the playlist's [songIds] list or the [_songs] list is replaced
  /// (both get a fresh instance on edit / reload), so identity checks suffice.
  final Map<String, ({List<String> ids, List<Track> songs, List<Track> result})>
      _playlistTracksCache = {};

  // Public API ---------------------------------------------------------------
  //
  // Keep the controller's public methods as real instance members. The
  // responsibility-based part files contain only private implementations, so
  // callers retain the same imports, dispatch, and subclass-visible surface.

  Future<void> load() => _load();

  void onSyncTokenAdvanced(int latestToken) =>
      _onSyncTokenAdvanced(latestToken);

  /// Returns album detail, falling back to locally synthesized data offline.
  Future<AlbumDetail> albumDetail(String albumId) => _albumDetail(albumId);

  /// An album's genres, most-tagged first. Empty when its files carry no
  /// usable genre tag.
  List<String> albumGenres(String albumId) => _albumGenres(albumId);

  /// Every genre in the library, widest first. Empty for an untagged library,
  /// which is the signal to hide the genre filter entirely.
  List<String> get genreFacets => _genres.genres;

  /// How many albums carry [genre].
  int genreAlbumCount(String genre) =>
      _genres.genreAlbums[genre]?.length ?? 0;

  String? get genreFilter => _genreFilter;

  void setGenreFilter(String? genre) => _setGenreFilter(genre);

  List<Album> get filteredAlbums => _albumsInGenre(_genreFilter);

  /// Albums by [name]: every album whose artist string, or a credited artist
  /// within it, normalizes to [name] — so case, whitespace and
  /// collaboration-credit differences resolve to the same page.
  List<Album> artistAlbums(String name) => _artistAlbums(name);

  /// Songs credited to [name]. Multi-artist credits ("A, B") count for every
  /// artist in the credit, mirroring the listening-stats derivation.
  List<Track> artistTracks(String name) => _artistTracks(name);

  /// Albums where [name] is credited on at least one track but is not the
  /// album artist — compilations, soundtracks and features. Sorted by title.
  List<Album> artistAppearsOn(String name) => _artistAppearsOn(name);

  /// Playlists containing at least one song credited to [name], in library
  /// order.
  List<PlaylistSummary> playlistsWithArtist(String name) =>
      _playlistsWithArtist(name);

  /// Every distinct artist in the library, sorted case-insensitively.
  /// Combined credits ("A, B") contribute A and B individually, mirroring
  /// the artist-page lookups.
  List<LibraryArtistSummary> get artists => _artistIndex.artists;

  /// Searches the derived artist list with the same matching and ranking
  /// rules as the rest of the library.
  List<LibraryArtistSummary> searchArtists(String query) =>
      _searchArtists(query);

  List<Track> playlistTracks(PlaylistSummary playlist) =>
      _playlistTracks(playlist);

  /// The library song with [id], or null when it is not in the library.
  Track? songById(String id) => _songsById[id];

  Future<void> toggleAlbumPin(String albumId) => _toggleAlbumPin(albumId);

  Future<void> togglePlaylistPin(String playlistId) =>
      _togglePlaylistPin(playlistId);

  Future<void> refreshPins() => _refreshPins();

  /// Hides a batch of targets (`album` / `playlist` / `artist`) in one request
  /// — the multi-select path. A single Hide passes one target.
  Future<void> hideItems(Iterable<({String type, String targetId})> targets) =>
      _hideItems(targets);

  Future<void> unhideItem(String type, String targetId) =>
      _unhideItem(type, targetId);

  Future<void> refreshHidden() => _refreshHidden();

  Future<void> refreshCuration() => _refreshCuration();

  Future<void> saveCuration({
    required LibraryCurationMode mode,
    required List<CurationRuleEntry> rules,
    bool onboardingCompleted = true,
  }) =>
      _saveCuration(
        mode: mode,
        rules: rules,
        onboardingCompleted: onboardingCompleted,
      );

  Future<void> completeCurationOnboardingFull() =>
      _saveCuration(
        mode: LibraryCurationMode.full,
        rules: _curation.rules,
        onboardingCompleted: true,
      );

  Future<void> addTargetsToLibrary({
    List<String> artists = const <String>[],
    List<String> albumIds = const <String>[],
    List<String> songIds = const <String>[],
    List<String> playlistIds = const <String>[],
  }) =>
      _addTargetsToLibrary(
        artists: artists,
        albumIds: albumIds,
        songIds: songIds,
        playlistIds: playlistIds,
      );

  List<Track> albumTracks(String albumId) =>
      _songs.where((s) => s.albumId == albumId).toList()
        ..sort((a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));

  Future<void> refreshPlaylistEdits() => _refreshPlaylistEdits();

  Future<void> setPlaylistImage(
    String playlistId, {
    required Uint8List bytes,
    required String contentType,
  }) =>
      _setPlaylistImage(
        playlistId,
        bytes: bytes,
        contentType: contentType,
      );

  Future<void> removePlaylistImage(String playlistId) =>
      _removePlaylistImage(playlistId);

  Future<String?> createPlaylist(
    String name, {
    List<String> initialSongIds = const <String>[],
  }) =>
      _createPlaylist(name, initialSongIds: initialSongIds);

  Future<void> renamePlaylist(String playlistId, String name) =>
      _renamePlaylist(playlistId, name);

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String songId,
  ) =>
      _removeTrackFromPlaylist(playlistId, songId);

  Future<void> addTrackToPlaylist(String playlistId, String songId) =>
      _addTrackToPlaylist(playlistId, songId);

  Future<void> addTracksToPlaylist(String playlistId, List<String> songIds) =>
      _addTracksToPlaylist(playlistId, songIds);

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> songIds,
  ) =>
      _removeTracksFromPlaylist(playlistId, songIds);

  /// A playlist's song ids, including an emptied Liked Songs; null if unknown.
  List<String>? playlistSongIds(String playlistId) =>
      _playlistSongIds(playlistId);

  /// Puts a playlist's songs back to ids captured with [playlistSongIds],
  /// e.g. to undo a removal.
  Future<void> restorePlaylistSongs(String playlistId, List<String> songIds) =>
      _updatePlaylistSongs(playlistId, (_) => List<String>.of(songIds));

  bool isLikedSong(String songId) => _isLikedSong(songId);

  Future<void> toggleLikedSong(Track track) => _toggleLikedSong(track);

  Future<void> syncPendingPlaylistEdits() => _syncPendingPlaylistEdits();

  Future<void> movePlaylistTrack(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) =>
      _movePlaylistTrack(playlistId, oldIndex, newIndex);

  Future<void> applyPlaylistPickOrder(
    String playlistId,
    List<String> pickedIds, {
    int startIndex = 0,
  }) =>
      _applyPlaylistPickOrder(
        playlistId,
        pickedIds,
        startIndex: startIndex,
      );

  Future<void> deletePlaylist(String playlistId) => _deletePlaylist(playlistId);

  List<Track> playlistCoverTracks(
    PlaylistSummary playlist, {
    int max = 4,
  }) =>
      _playlistCoverTracks(playlist, max: max);

  LibrarySearchResults search(String query, {bool includeFullCatalog = false}) =>
      _search(query, includeFullCatalog: includeFullCatalog);

  Future<LibrarySearchResults> searchAsync(
    String query, {
    bool includeFullCatalog = false,
  }) =>
      _searchAsync(query, includeFullCatalog: includeFullCatalog);

  LibrarySearchResults searchCollections(String query) =>
      _searchCollections(query);

  Future<void> addRecentSearch(Track track) => _addRecentSearch(track);

  Future<void> removeRecentSearch(String trackId) =>
      _removeRecentSearch(trackId);

  Future<void> clearRecentSearches() => _clearRecentSearches();

  /// Replaces recent searches wholesale (used to undo clearing them).
  Future<void> restoreRecentSearches(List<Track> tracks) =>
      _restoreRecentSearches(tracks);

  Future<List<Track>> trimRecentSearches([int? limit]) =>
      _trimRecentSearches(limit);

  void _onSearchSettingsChanged() {
    final limit = _searchSettings.recentSearchesLimit;
    if (_recentSearches.length > limit) {
      _recentSearches = _recentSearches.take(limit).toList();
      notifyListeners();
      unawaited(_savePreferences());
    }
  }

  /// Computes thumbnail URLs for priority playlists and albums (visible on home).
  @visibleForTesting
  Set<String> priorityArtworkUrls(PlayerApiClient client) =>
      _priorityArtworkUrls(client);

  Future<bool> loadOfflineSnapshot() => _loadOfflineSnapshot();

  void _notifyListeners() {
    _warmSearchWorkers();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _curatedSearchSlot.dispose();
    _fullSearchSlot.dispose();
    _searchSettings.removeListener(_onSearchSettingsChanged);
    _syncTokenDebounce?.cancel();
    super.dispose();
  }
}

/// Joins normalized song rows to the album catalog once at the library
/// boundary. Every downstream consumer (playback, stats, downloads, offline
/// snapshots) then receives the same denormalized display metadata.
List<Track> hydrateTrackAlbumMetadata(
  Iterable<Track> tracks,
  Iterable<Album> albums,
) {
  final albumsById = <String, Album>{
    for (final album in albums) album.id: album
  };
  return [
    for (final track in tracks)
      if (track.albumId == null || albumsById[track.albumId] == null)
        track
      else
        track.copyWith(
          albumTitle: track.albumTitle?.trim().isNotEmpty == true
              ? track.albumTitle
              : albumsById[track.albumId]!.title,
          albumArtist: track.albumArtist?.trim().isNotEmpty == true
              ? track.albumArtist
              : albumsById[track.albumId]!.artist,
        ),
  ];
}

class LibrarySearchResults {
  final List<Album> albums;
  final List<Track> songs;
  final List<PlaylistSummary> playlists;
  final Map<String, String> lyricSnippets;

  const LibrarySearchResults({
    required this.albums,
    required this.songs,
    required this.playlists,
    this.lyricSnippets = const <String, String>{},
  });

  static const empty = LibrarySearchResults(
    albums: <Album>[],
    songs: <Track>[],
    playlists: <PlaylistSummary>[],
  );

  bool get isEmpty => albums.isEmpty && songs.isEmpty && playlists.isEmpty;
}

class _SearchWorkerSlot {
  LibrarySearchWorker? worker;
  List<Album>? albumsRef;
  List<Track>? songsRef;
  List<PlaylistSummary>? playlistsRef;
  Future<void> pendingSync = Future<void>.value();

  void dispose() {
    albumsRef = null;
    songsRef = null;
    playlistsRef = null;
    pendingSync = Future<void>.value();
    final w = worker;
    worker = null;
    if (w != null) unawaited(w.dispose());
  }
}

/// Merges a "reorder via search" pick list into a playlist order at
/// [startIndex]. Earlier entries stay fixed; picks come next in pick order and
/// everything else keeps its relative order after them. Picked ids not in the
/// editable suffix are ignored; duplicate entries are consumed one per pick.
List<String> mergePickOrder(
  List<String> current,
  List<String> pickedIds, {
  int startIndex = 0,
}) {
  final split = startIndex.clamp(0, current.length);
  final prefix = current.take(split).toList();
  final remaining = current.skip(split).toList();
  final picked = <String>[
    for (final id in pickedIds)
      if (remaining.remove(id)) id,
  ];
  return [...prefix, ...picked, ...remaining];
}
