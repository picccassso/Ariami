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
      _startCompleter!.completeError(StateError('LibrarySearchWorker disposed'));
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
  const _IndexedSong(this.id, this.fields, this.preparedLyrics);
  final String id;
  final List<SearchField> fields;
  final PreparedLyrics? preparedLyrics;
}

void _workerMain(SendPort replyTo) {
  final inbox = ReceivePort();
  replyTo.send(inbox.sendPort);

  var indexedSongs = const <_IndexedSong>[];
  var indexedAlbums = const <_IndexedItem>[];
  var indexedPlaylists = const <_IndexedItem>[];

  inbox.listen((message) {
    if (message is _DisposeRequest) {
      inbox.close();
      return;
    }

    if (message is _SetCatalogRequest) {
      final albumById = <String, SearchableAlbumEntry>{
        for (final album in message.albums) album.id: album,
      };
      indexedAlbums = [
        for (final album in message.albums)
          _IndexedItem(album.id, [
            SearchField(album.title, isPrimary: true),
            SearchField(album.artist),
          ]),
      ];
      indexedPlaylists = [
        for (final playlist in message.playlists)
          _IndexedItem(playlist.id, [
            SearchField(playlist.name, isPrimary: true),
          ]),
      ];
      indexedSongs = [
        for (final song in message.songs)
          () {
            final album =
                song.albumId == null ? null : albumById[song.albumId!];
            final albumTitle = song.albumTitle ?? album?.title;
            final albumArtist = song.albumArtist ?? album?.artist;
            return _IndexedSong(
              song.id,
              [
                SearchField(song.title, isPrimary: true),
                SearchField(song.artist),
                if (albumTitle != null) SearchField(albumTitle),
                if (albumArtist != null) SearchField(albumArtist),
              ],
              LibrarySearchEngine.prepareLyrics(song.lyrics),
            );
          }(),
      ];
      replyTo.send(_WorkerResponse(message.id, null));
      return;
    }

    if (message is _SearchRequest) {
      final parsed = SearchQuery.parse(message.query);
      if (parsed.isEmpty) {
        replyTo.send(_WorkerResponse(message.id, SearchWorkerResults.empty));
        return;
      }

      final rankedSongs = message.includeSongs
          ? LibrarySearchEngine.rankWithLyrics(
              parsed,
              indexedSongs,
              idOf: (s) => s.id,
              fieldsOf: (s) => s.fields,
              lyricsOf: (_) => null,
              preparedLyricsOf: (s) => s.preparedLyrics,
              limit: message.songLimit,
            )
          : (items: const <_IndexedSong>[], lyricSnippets: const <String, String>{});

      final rankedAlbums = LibrarySearchEngine.rank(
        parsed,
        indexedAlbums,
        (a) => a.fields,
        limit: message.albumLimit,
      );
      final rankedPlaylists = LibrarySearchEngine.rank(
        parsed,
        indexedPlaylists,
        (p) => p.fields,
        limit: message.playlistLimit,
      );

      replyTo.send(
        _WorkerResponse(
          message.id,
          SearchWorkerResults(
            songIds: [for (final s in rankedSongs.items) s.id],
            albumIds: [for (final a in rankedAlbums) a.id],
            playlistIds: [for (final p in rankedPlaylists) p.id],
            lyricSnippets: rankedSongs.lyricSnippets,
          ),
        ),
      );
    }
  });
}
