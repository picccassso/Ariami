import 'dart:async';
import 'dart:convert';
import 'package:ariami_core/services/search/search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';
import 'settings/search_settings_service.dart';

/// Search service backed by the shared engine in ariami_core (tokenized,
/// tiered ranking with transliteration and keyboard-layout correction, so
/// the same query behaves identically on desktop and TV). This class keeps
/// the mobile-specific parts: result deduplication and recent songs.
class SearchService {
  static const String recentSongsKey = SearchSettingsService.recentSongsKey;
  static const String _recentSongsKey = recentSongsKey;

  final SearchSettingsService _settingsService;
  LibrarySearchWorker? _worker;
  Future<void>? _setCatalogInFlight;
  bool _disposed = false;
  Map<String, SongModel> _songsById = const <String, SongModel>{};
  Map<String, AlbumModel> _albumsById = const <String, AlbumModel>{};
  Map<String, PlaylistModel> _playlistsById = const <String, PlaylistModel>{};

  SearchService({SearchSettingsService? settingsService})
      : _settingsService = settingsService ?? SearchSettingsService();

  /// Current maximum recent searches limit (configured by user in settings).
  int get maxRecentSongs {
    _settingsService.initialize();
    return _settingsService.recentSearchesLimit;
  }

  Future<void> setCatalog({
    required List<SongModel> songs,
    required List<AlbumModel> albums,
    List<PlaylistModel> playlists = const <PlaylistModel>[],
    bool deduplicated = false,
  }) async {
    if (_disposed) return;

    final uniqueSongs = deduplicated ? songs : deduplicateSongs(songs);
    final uniqueAlbums = deduplicated ? albums : deduplicateAlbums(albums);
    final albumsById = <String, AlbumModel>{
      for (final album in uniqueAlbums) album.id: album,
    };
    _songsById = <String, SongModel>{
      for (final song in uniqueSongs) song.id: song,
    };
    _albumsById = albumsById;
    _playlistsById = <String, PlaylistModel>{
      for (final playlist in playlists) playlist.id: playlist,
    };

    if (uniqueSongs.isEmpty &&
        uniqueAlbums.isEmpty &&
        playlists.isEmpty &&
        _worker == null) {
      return;
    }

    final worker = _worker ??= LibrarySearchWorker();
    final future = worker.setCatalog(
      songs: [
        for (final song in uniqueSongs)
          SearchableSongEntry(
            id: song.id,
            title: song.title,
            artist: song.artist,
            albumId: song.albumId,
            albumTitle:
                song.albumId == null ? null : albumsById[song.albumId!]?.title,
            albumArtist:
                song.albumId == null ? null : albumsById[song.albumId!]?.artist,
            lyrics: song.lyrics,
          ),
      ],
      albums: [
        for (final album in uniqueAlbums)
          SearchableAlbumEntry(
            id: album.id,
            title: album.title,
            artist: album.artist,
          ),
      ],
      playlists: [
        for (final playlist in playlists)
          SearchablePlaylistEntry(
            id: playlist.id,
            name: playlist.name,
          ),
      ],
    );
    _setCatalogInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_setCatalogInFlight, future)) {
        _setCatalogInFlight = null;
      }
    }
  }

  Future<SearchResults> searchAsync(
    String query, {
    int? songLimit,
    int? albumLimit,
    int? playlistLimit,
  }) async {
    final worker = _worker;
    if (_disposed || worker == null || query.trim().isEmpty) {
      return SearchResults(songs: [], albums: []);
    }

    final songsById = _songsById;
    final albumsById = _albumsById;
    final playlistsById = _playlistsById;
    final workerResults = await worker.search(
      query,
      songLimit: songLimit,
      albumLimit: albumLimit,
      playlistLimit: playlistLimit,
    );
    if (workerResults.isEmpty) {
      return SearchResults(songs: [], albums: []);
    }

    final songs = <SongModel>[
      for (final id in workerResults.songIds)
        if (songsById[id] case final song?) song,
    ];
    final lyricSnippets = Map<String, String>.of(workerResults.lyricSnippets);
    final displaySongs = _deduplicateDisplaySongs(
      songs,
      lyricSnippets: lyricSnippets,
    );
    final albums = <AlbumModel>[
      for (final id in workerResults.albumIds)
        if (albumsById[id] case final album?) album,
    ];
    final playlists = <PlaylistModel>[
      for (final id in workerResults.playlistIds)
        if (playlistsById[id] case final playlist?) playlist,
    ];

    return SearchResults(
      songs: displaySongs,
      albums: albums,
      playlists: playlists,
      lyricSnippets: lyricSnippets,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    final inFlight = _setCatalogInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      await worker.dispose();
    }
  }

  SearchResults search(
    String query,
    List<SongModel> songs,
    List<AlbumModel> albums, {
    List<PlaylistModel> playlists = const <PlaylistModel>[],
    bool deduplicated = false,
  }) {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) {
      return SearchResults(songs: [], albums: []);
    }

    final uniqueSongs = deduplicated ? songs : deduplicateSongs(songs);
    final uniqueAlbums = deduplicated ? albums : deduplicateAlbums(albums);
    final albumById = {for (final album in uniqueAlbums) album.id: album};

    final rankedSongs = LibrarySearchEngine.rankWithLyrics(
      parsed,
      uniqueSongs,
      idOf: (song) => song.id,
      fieldsOf: (song) => _songSearchFields(song, albumById),
      lyricsOf: (song) => song.lyrics,
    );
    final lyricSnippets = Map<String, String>.of(rankedSongs.lyricSnippets);
    final displayUniqueRankedSongs = _deduplicateDisplaySongs(
      rankedSongs.items,
      lyricSnippets: lyricSnippets,
    );

    final rankedAlbums = LibrarySearchEngine.rank(
      parsed,
      uniqueAlbums,
      _albumSearchFields,
    );

    final rankedPlaylists = LibrarySearchEngine.rank(
      parsed,
      playlists,
      (playlist) => [SearchField(playlist.name, isPrimary: true)],
    );

    return SearchResults(
      songs: displayUniqueRankedSongs,
      albums: rankedAlbums,
      playlists: rankedPlaylists,
      lyricSnippets: lyricSnippets,
    );
  }

  List<SearchField> _songSearchFields(
    SongModel song,
    Map<String, AlbumModel> albumById,
  ) {
    final album = albumById[song.albumId ?? ''];
    return [
      SearchField(song.title, isPrimary: true),
      SearchField(song.artist),
      if (album != null) SearchField(album.title),
      if (album != null) SearchField(album.artist),
    ];
  }

  List<SearchField> _albumSearchFields(AlbumModel album) => [
        SearchField(album.title, isPrimary: true),
        SearchField(album.artist),
      ];

  /// Remove duplicate songs while preserving stable ordering.
  ///
  /// Deduping is done in two stages:
  /// 1) by song ID
  /// 2) by canonical metadata fingerprint (title/artist/album/duration/track)
  List<SongModel> deduplicateSongs(List<SongModel> songs) {
    if (songs.length < 2) return songs;

    final byId = <String, SongModel>{};
    final orderedIds = <String>[];
    for (final song in songs) {
      final existing = byId[song.id];
      if (existing == null) {
        byId[song.id] = song;
        orderedIds.add(song.id);
      } else {
        byId[song.id] = _pickPreferredSong(existing, song);
      }
    }

    final byFingerprint = <String, SongModel>{};
    final orderedFingerprints = <String>[];
    for (final id in orderedIds) {
      final song = byId[id]!;
      final fingerprint = _songFingerprint(song);
      final existing = byFingerprint[fingerprint];
      if (existing == null) {
        byFingerprint[fingerprint] = song;
        orderedFingerprints.add(fingerprint);
      } else {
        byFingerprint[fingerprint] = _pickPreferredSong(existing, song);
      }
    }

    return orderedFingerprints.map((key) => byFingerprint[key]!).toList();
  }

  /// Remove duplicate albums while preserving stable ordering.
  ///
  /// Deduping is done in two stages:
  /// 1) by album ID
  /// 2) by canonical metadata fingerprint (title/artist)
  List<AlbumModel> deduplicateAlbums(List<AlbumModel> albums) {
    if (albums.length < 2) return albums;

    final byId = <String, AlbumModel>{};
    final orderedIds = <String>[];
    for (final album in albums) {
      final existing = byId[album.id];
      if (existing == null) {
        byId[album.id] = album;
        orderedIds.add(album.id);
      } else {
        byId[album.id] = _pickPreferredAlbum(existing, album);
      }
    }

    final byFingerprint = <String, AlbumModel>{};
    final orderedFingerprints = <String>[];
    for (final id in orderedIds) {
      final album = byId[id]!;
      final fingerprint = _albumFingerprint(album);
      final existing = byFingerprint[fingerprint];
      if (existing == null) {
        byFingerprint[fingerprint] = album;
        orderedFingerprints.add(fingerprint);
      } else {
        byFingerprint[fingerprint] = _pickPreferredAlbum(existing, album);
      }
    }

    return orderedFingerprints.map((key) => byFingerprint[key]!).toList();
  }

  /// Final display-level dedupe for ranked song results.
  ///
  /// This intentionally ignores album/track IDs so the same audible track
  /// doesn't appear multiple times if ingested through multiple sources.
  List<SongModel> _deduplicateDisplaySongs(
    List<SongModel> songs, {
    Map<String, String>? lyricSnippets,
  }) {
    if (songs.length < 2) return songs;

    final unique = <String, SongModel>{};
    final orderedKeys = <String>[];
    for (final song in songs) {
      final key = _displaySongFingerprint(song);
      if (!unique.containsKey(key)) {
        unique[key] = song;
        orderedKeys.add(key);
      } else {
        final existing = unique[key]!;
        final preferred = _pickPreferredSong(existing, song);
        if (lyricSnippets != null) {
          final snippet = lyricSnippets[preferred.id] ??
              lyricSnippets[existing.id] ??
              lyricSnippets[song.id];
          if (snippet != null) {
            lyricSnippets[preferred.id] = snippet;
          }
        }
        unique[key] = preferred;
      }
    }

    return orderedKeys.map((key) => unique[key]!).toList();
  }

  String _songFingerprint(SongModel song) {
    return [
      _normalize(song.title),
      _normalize(song.artist),
      _normalize(song.albumId ?? ''),
      song.duration.toString(),
      song.trackNumber?.toString() ?? '',
    ].join('|');
  }

  String _displaySongFingerprint(SongModel song) {
    final durationBucket = (song.duration / 2).round();
    return [
      _normalize(song.title),
      _normalize(song.artist),
      durationBucket.toString(),
    ].join('|');
  }

  String _albumFingerprint(AlbumModel album) {
    return [
      _normalize(album.title),
      _normalize(album.artist),
    ].join('|');
  }

  String _normalize(String value) => value.trim().toLowerCase();

  SongModel _pickPreferredSong(SongModel a, SongModel b) {
    final scoreA = _songMetadataScore(a);
    final scoreB = _songMetadataScore(b);
    return scoreB > scoreA ? b : a;
  }

  int _songMetadataScore(SongModel song) {
    var score = 0;
    if (song.albumId != null && song.albumId!.trim().isNotEmpty) score += 2;
    if (song.duration > 0) score += 1;
    if (song.trackNumber != null) score += 1;
    if (song.lyrics != null && song.lyrics!.trim().isNotEmpty) score += 1;
    return score;
  }

  AlbumModel _pickPreferredAlbum(AlbumModel a, AlbumModel b) {
    final scoreA = _albumMetadataScore(a);
    final scoreB = _albumMetadataScore(b);
    return scoreB > scoreA ? b : a;
  }

  int _albumMetadataScore(AlbumModel album) {
    var score = 0;
    if (album.coverArt != null && album.coverArt!.trim().isNotEmpty) score += 2;
    if (album.songCount > 0) score += 1;
    if (album.duration > 0) score += 1;
    return score;
  }

  Future<List<SongModel>> getRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];
    final limit = maxRecentSongs;

    final List<String> listToParse;
    if (jsonList.length > limit) {
      listToParse = jsonList.sublist(0, limit);
      await prefs.setStringList(_recentSongsKey, listToParse);
    } else {
      listToParse = jsonList;
    }

    final songs = <SongModel>[];
    for (final jsonStr in listToParse) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        songs.add(SongModel.fromJson(json));
      } catch (_) {}
    }
    return songs;
  }

  Future<void> addRecentSong(SongModel song) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    final recentSongs = <SongModel>[];
    for (final jsonStr in jsonList) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        recentSongs.add(SongModel.fromJson(json));
      } catch (_) {}
    }

    recentSongs.removeWhere((s) => s.id == song.id);

    recentSongs.insert(0, song);

    final limit = maxRecentSongs;
    if (recentSongs.length > limit) {
      recentSongs.removeRange(limit, recentSongs.length);
    }

    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }

  Future<void> clearRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSongsKey);
  }

  /// Replace recent songs wholesale (used to undo clearing them)
  Future<void> restoreRecentSongs(List<SongModel> songs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentSongsKey,
      songs.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<void> removeRecentSong(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    final recentSongs = <SongModel>[];
    for (final jsonStr in jsonList) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        recentSongs.add(SongModel.fromJson(json));
      } catch (_) {}
    }

    recentSongs.removeWhere((s) => s.id == songId);

    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }

  Future<void> insertRecentSongAt(SongModel song, int index) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];

    final recentSongs = <SongModel>[];
    for (final jsonStr in jsonList) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        recentSongs.add(SongModel.fromJson(json));
      } catch (_) {}
    }

    recentSongs.removeWhere((s) => s.id == song.id);

    final insertIndex = index.clamp(0, recentSongs.length).toInt();
    recentSongs.insert(insertIndex, song);

    final limit = maxRecentSongs;
    if (recentSongs.length > limit) {
      recentSongs.removeRange(limit, recentSongs.length);
    }

    final updatedJsonList =
        recentSongs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_recentSongsKey, updatedJsonList);
  }

  /// Trims stored recent songs to [limit] (or current [maxRecentSongs]).
  /// If the number of stored recent songs exceeds the limit, trims them in
  /// SharedPreferences and returns the trimmed list.
  Future<List<SongModel>> trimRecentSongs([int? limit]) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_recentSongsKey) ?? [];
    final maxLimit = (limit ?? maxRecentSongs).clamp(0, jsonList.length);

    final List<String> listToParse;
    if (jsonList.length > maxLimit) {
      listToParse = jsonList.sublist(0, maxLimit);
      await prefs.setStringList(_recentSongsKey, listToParse);
    } else {
      listToParse = jsonList;
    }

    final songs = <SongModel>[];
    for (final jsonStr in listToParse) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        songs.add(SongModel.fromJson(json));
      } catch (_) {}
    }

    return songs;
  }
}

class SearchResults {
  final List<SongModel> songs;
  final List<AlbumModel> albums;
  final List<PlaylistModel> playlists;
  final Map<String, String> lyricSnippets;

  SearchResults({
    required this.songs,
    required this.albums,
    this.playlists = const <PlaylistModel>[],
    this.lyricSnippets = const <String, String>{},
  });

  bool get isEmpty => songs.isEmpty && albums.isEmpty && playlists.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

class DebouncedSearch {
  final Duration delay;
  Timer? _timer;

  DebouncedSearch({this.delay = const Duration(milliseconds: 300)});

  void run(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  void cancel() {
    _timer?.cancel();
  }
}
