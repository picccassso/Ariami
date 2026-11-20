/// Persistent background-isolate search worker backed by [LibrarySearchEngine].
/// Pre-normalizes catalog metadata and lyrics off the UI thread so keystroke
/// queries execute without allocations or frame drops on the main isolate.
library;

import 'dart:async';
import 'dart:isolate';

import 'library_search_engine.dart';

class SearchableSongEntry {
  const SearchableSongEntry({
    required this.id,
    required this.title,
    required this.artist,
    this.albumId,
    this.albumTitle,
    this.albumArtist,
    this.lyrics,
  });

  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumTitle;
  final String? albumArtist;
  final String? lyrics;
}

class SearchableAlbumEntry {
  const SearchableAlbumEntry({
    required this.id,
    required this.title,
    required this.artist,
  });

  final String id;
  final String title;
  final String artist;
}

class SearchablePlaylistEntry {
  const SearchablePlaylistEntry({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class SearchWorkerResults {
  const SearchWorkerResults({
    required this.songIds,
    required this.albumIds,
    required this.playlistIds,
    this.lyricSnippets = const <String, String>{},
  });

  final List<String> songIds;
  final List<String> albumIds;
  final List<String> playlistIds;
  final Map<String, String> lyricSnippets;

  bool get isEmpty =>
      songIds.isEmpty && albumIds.isEmpty && playlistIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  static const empty = SearchWorkerResults(
    songIds: <String>[],
    albumIds: <String>[],
    playlistIds: <String>[],
  );
}

class LibrarySearchWorker {
  static const bool _inProcess =
      bool.fromEnvironment('dart.library.js_interop');
  _SearchIndex? _local;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<SendPort>? _startCompleter;
  Future<SendPort>? _starting;
  int _nextId = 0;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  bool _disposed = false;

  Future<SendPort> _ensureStarted() {
    if (_sendPort != null) return Future<SendPort>.value(_sendPort!);
    if (_starting != null) return _starting!;

    final completer = Completer<SendPort>();
    _startCompleter = completer;
    final port = ReceivePort();
    _receivePort = port;
    port.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!completer.isCompleted) completer.complete(message);
        return;
      }
      if (message is _WorkerResponse) {
        _pending.remove(message.id)?.complete(message.payload);
      }
    });

    _starting = Isolate.spawn(_workerMain, port.sendPort).then((isolate) {
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        port.close();
        if (!completer.isCompleted) {
          completer.completeError(StateError('LibrarySearchWorker disposed'));
        }
        return completer.future;
      }
      _isolate = isolate;
      return completer.future;
    });
    return _starting!;
  }

  Future<Object?> _sendRequest(_WorkerRequest Function(int id) build) async {
    if (_disposed) return null;
    // Browsers have no isolates, so web searches the index in place.
    if (_inProcess) return (_local ??= _SearchIndex()).handle(build(_nextId++));
    final SendPort port;
    try {
      port = await _ensureStarted();
    } catch (_) {
      return null;
    }
    if (_disposed) return null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(build(id));
    return completer.future;
  }

  Future<void> setCatalog({
    required List<SearchableSongEntry> songs,
    required List<SearchableAlbumEntry> albums,
    required List<SearchablePlaylistEntry> playlists,
  }) async {
    await _sendRequest(
      (id) => _SetCatalogRequest(id, songs, albums, playlists),
    );
  }

  Future<SearchWorkerResults> search(
    String query, {
    int? songLimit,
    int? albumLimit,
    int? playlistLimit,
    bool includeSongs = true,
  }) async {
    if (_disposed || query.trim().isEmpty) return SearchWorkerResults.empty;
    final result = await _sendRequest(
      (id) => _SearchRequest(
        id,
        query,
        songLimit: songLimit,
        albumLimit: albumLimit,
        playlistLimit: playlistLimit,
        includeSongs: includeSongs,
      ),
    );
    return result as SearchWorkerResults? ?? SearchWorkerResults.empty;
  }

  Future<SearchWorkerResults> searchCollections(
    String query, {
    int? albumLimit,
    int? playlistLimit,
  }) =>
      search(
        query,
        albumLimit: albumLimit,
        playlistLimit: playlistLimit,
        includeSongs: false,
      );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_startCompleter != null && !_startCompleter!.isCompleted) {
      _startCompleter!
          .completeError(StateError('LibrarySearchWorker disposed'));
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    _sendPort?.send(const _DisposeRequest());
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
    _startCompleter = null;
    _starting = null;
  }
}

sealed class _WorkerRequest {
  const _WorkerRequest();
}

final class _SetCatalogRequest extends _WorkerRequest {
  const _SetCatalogRequest(this.id, this.songs, this.albums, this.playlists);
  final int id;
  final List<SearchableSongEntry> songs;
  final List<SearchableAlbumEntry> albums;
  final List<SearchablePlaylistEntry> playlists;
}

final class _SearchRequest extends _WorkerRequest {
  const _SearchRequest(
    this.id,
    this.query, {
    this.songLimit,
    this.albumLimit,
    this.playlistLimit,
    required this.includeSongs,
  });

  final int id;
  final String query;
  final int? songLimit;
  final int? albumLimit;
  final int? playlistLimit;
  final bool includeSongs;
}

final class _DisposeRequest extends _WorkerRequest {
  const _DisposeRequest();
}

final class _WorkerResponse {
  const _WorkerResponse(this.id, this.payload);
  final int id;
  final Object? payload;
}

class _IndexedItem {
  const _IndexedItem(this.id, this.fields);
  final String id;
  final List<SearchField> fields;
}

class _IndexedSong {
  const _IndexedSong(this.id, this.fields, this.lyrics, this.preparedLyrics);
  final String id;
  final List<SearchField> fields;
  final String? lyrics;
  final PreparedLyrics? preparedLyrics;
}

/// The catalog index and ranking, shared by the isolate and the web fallback.
class _SearchIndex {
  var _songs = const <_IndexedSong>[];
  var _albums = const <_IndexedItem>[];
  var _playlists = const <_IndexedItem>[];

  /// Completes when the latest catalog build has been swapped in.
  Future<void> _ready = Future<void>.value();

  // Built in slices with event-loop yields between them: on web the index
  // shares the UI thread, where one pass over 2k songs blocks for ~340 ms.
  Future<void> setCatalog(_SetCatalogRequest message) async {
    // Re-syncs (playlist edits, curation, delta syncs) keep each song's
    // prepared lyrics when the text is unchanged.
    final previousSongs = <String, _IndexedSong>{
      for (final song in _songs)
        if (song.preparedLyrics != null) song.id: song,
    };
    final albumById = <String, SearchableAlbumEntry>{
      for (final album in message.albums) album.id: album,
    };
    final albums = [
      for (final album in message.albums)
        _IndexedItem(album.id, [
          SearchField(album.title, isPrimary: true),
          SearchField(album.artist),
        ]),
    ];
    final playlists = [
      for (final playlist in message.playlists)
        _IndexedItem(playlist.id, [
          SearchField(playlist.name, isPrimary: true),
        ]),
    ];
    final songs = <_IndexedSong>[];
    for (final song in message.songs) {
      if (songs.length % 100 == 99) await Future<void>.delayed(Duration.zero);
      final album = song.albumId == null ? null : albumById[song.albumId!];
      final albumTitle = song.albumTitle ?? album?.title;
      final albumArtist = song.albumArtist ?? album?.artist;
      final previous = previousSongs[song.id];
      songs.add(_IndexedSong(
        song.id,
        [
          SearchField(song.title, isPrimary: true),
          SearchField(song.artist),
          if (albumTitle != null) SearchField(albumTitle),
          if (albumArtist != null) SearchField(albumArtist),
        ],
        song.lyrics,
        previous != null && previous.lyrics == song.lyrics
            ? previous.preparedLyrics
            : LibrarySearchEngine.prepareLyrics(song.lyrics),
      ));
    }
    _albums = albums;
    _playlists = playlists;
    _songs = songs;
  }

  SearchWorkerResults search(_SearchRequest message) {
    final parsed = SearchQuery.parse(message.query);
    if (parsed.isEmpty) return SearchWorkerResults.empty;

    final rankedSongs = message.includeSongs
        ? LibrarySearchEngine.rankWithLyrics(
            parsed,
            _songs,
            idOf: (s) => s.id,
            fieldsOf: (s) => s.fields,
            lyricsOf: (_) => null,
            preparedLyricsOf: (s) => s.preparedLyrics,
            limit: message.songLimit,
          )
        : (
            items: const <_IndexedSong>[],
            lyricSnippets: const <String, String>{}
          );
    final rankedAlbums = LibrarySearchEngine.rank(
      parsed,
      _albums,
      (a) => a.fields,
      limit: message.albumLimit,
    );
    final rankedPlaylists = LibrarySearchEngine.rank(
      parsed,
      _playlists,
      (p) => p.fields,
      limit: message.playlistLimit,
    );
    return SearchWorkerResults(
      songIds: [for (final s in rankedSongs.items) s.id],
      albumIds: [for (final a in rankedAlbums) a.id],
      playlistIds: [for (final p in rankedPlaylists) p.id],
      lyricSnippets: rankedSongs.lyricSnippets,
    );
  }

  /// Builds run one after another; searches wait for the latest one.
  Future<Object?> handle(_WorkerRequest request) async {
    if (request is _SetCatalogRequest) {
      await (_ready =
          _ready.catchError((_) {}).then((_) => setCatalog(request)));
      return null;
    }
    await _ready.catchError((_) {});
    return request is _SearchRequest ? search(request) : null;
  }
}

void _workerMain(SendPort replyTo) {
  final inbox = ReceivePort();
  replyTo.send(inbox.sendPort);
  final index = _SearchIndex();
  inbox.listen((message) {
    if (message is _DisposeRequest) {
      inbox.close();
    } else if (message
        case _SetCatalogRequest(:final id) || _SearchRequest(:final id)) {
      index
          .handle(message as _WorkerRequest)
          .then((result) => replyTo.send(_WorkerResponse(id, result)));
    }
  });
}
