import 'dart:convert';

import 'package:ariami_core/models/api_models.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:shelf/shelf.dart';

typedef CatalogRepositoryProvider = CatalogRepository? Function();

/// V2 API handlers backed only by catalog repository reads.
class AriamiV2Handlers {
  AriamiV2Handlers({
    required CatalogRepositoryProvider catalogRepositoryProvider,
  }) : _catalogRepositoryProvider = catalogRepositoryProvider;

  static const int _defaultEntityPageLimit = 100;
  static const int _maxEntityPageLimit = 500;
  static const int _defaultChangesLimit = 200;
  static const int _maxChangesLimit = 1000;

  final CatalogRepositoryProvider _catalogRepositoryProvider;

  Response handleBootstrap(Request request) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      return _catalogUnavailable();
    }

    final parsedLimit = _parseLimit(
      request.url.queryParameters['limit'],
      defaultValue: _defaultEntityPageLimit,
      maxValue: _maxEntityPageLimit,
    );
    if (parsedLimit == null) {
      return _badRequest('limit must be an integer between 1 and 500');
    }

    final parsedCursor = _parseBootstrapCursor(
      request.url.queryParameters['cursor'],
    );
    if (request.url.queryParameters['cursor'] != null && parsedCursor == null) {
      return _badRequest('cursor is invalid');
    }

    final albumsPage = repository.listAlbumsPage(
      cursor: parsedCursor?.albumsCursor,
      limit: parsedLimit,
    );
    final songsPage = repository.listSongsPage(
      cursor: parsedCursor?.songsCursor,
      limit: parsedLimit,
    );
    final playlistsPage = repository.listPlaylistsPage(
      cursor: parsedCursor?.playlistsCursor,
      limit: parsedLimit,
    );
    final latestToken = repository.getLatestToken();

    final nextAlbumsCursor = _cursorPosition(
        parsedCursor?.albumsCursor, albumsPage.items.map((r) => r.id));
    final nextSongsCursor = _cursorPosition(
        parsedCursor?.songsCursor, songsPage.items.map((r) => r.id));
    final nextPlaylistsCursor = _cursorPosition(
      parsedCursor?.playlistsCursor,
      playlistsPage.items.map((r) => r.id),
    );
    final hasMore =
        albumsPage.hasMore || songsPage.hasMore || playlistsPage.hasMore;
    final nextCursor = hasMore
        ? _encodeBootstrapCursor(
            _BootstrapCursor(
              albumsCursor: nextAlbumsCursor,
              songsCursor: nextSongsCursor,
              playlistsCursor: nextPlaylistsCursor,
            ),
          )
        : null;

    final response = V2BootstrapResponse(
      syncToken: latestToken,
      albums: albumsPage.items
          .map(
            (record) => AlbumModel(
              id: record.id,
              title: record.title,
              artist: record.artist,
              coverArt: record.coverArtKey == null
                  ? null
                  : '/api/artwork/${Uri.encodeComponent(record.id)}',
              songCount: record.songCount,
              duration: record.durationSeconds,
            ),
          )
          .toList(),
      songs: songsPage.items
          .map(
            (record) => SongModel(
              id: record.id,
              title: record.title,
              artist: record.artist,
              albumId: record.albumId,
              duration: record.durationSeconds,
              trackNumber: record.trackNumber,
            ),
          )
          .toList(),
      playlists: playlistsPage.items.map(
        (record) {
          final songIds = repository
              .listPlaylistSongs(record.id)
              .map((item) => item.songId)
              .toList();
          return PlaylistModel(
            id: record.id,
            name: record.name,
            songCount: record.songCount,
            duration: record.durationSeconds,
            songIds: songIds,
          );
        },
      ).toList(),
      pageInfo: V2PageInfo(
        cursor: request.url.queryParameters['cursor'],
        nextCursor: nextCursor,
        hasMore: hasMore,
        limit: parsedLimit,
      ),
    );

    return _jsonOk(response.toJson());
  }

  Response handleAlbums(Request request) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      return _catalogUnavailable();
    }

    final parsedLimit = _parseLimit(
      request.url.queryParameters['limit'],
      defaultValue: _defaultEntityPageLimit,
      maxValue: _maxEntityPageLimit,
    );
    if (parsedLimit == null) {
      return _badRequest('limit must be an integer between 1 and 500');
    }

    final cursor = request.url.queryParameters['cursor'];
    final page = repository.listAlbumsPage(cursor: cursor, limit: parsedLimit);
    final syncToken = repository.getLatestToken();

    final body = <String, dynamic>{
      'syncToken': syncToken,
      'albums': page.items
          .map(
            (record) => AlbumModel(
              id: record.id,
              title: record.title,
              artist: record.artist,
              coverArt: record.coverArtKey == null
                  ? null
                  : '/api/artwork/${Uri.encodeComponent(record.id)}',
              songCount: record.songCount,
              duration: record.durationSeconds,
            ).toJson(),
          )
          .toList(),
      'pageInfo': V2PageInfo(
        cursor: cursor,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        limit: parsedLimit,
      ).toJson(),
    };
    return _jsonOk(body);
  }

  Response handleSongs(Request request) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      return _catalogUnavailable();
    }

    final parsedLimit = _parseLimit(
      request.url.queryParameters['limit'],
      defaultValue: _defaultEntityPageLimit,
      maxValue: _maxEntityPageLimit,
    );
    if (parsedLimit == null) {
      return _badRequest('limit must be an integer between 1 and 500');
    }

    final cursor = request.url.queryParameters['cursor'];
    final page = repository.listSongsPage(cursor: cursor, limit: parsedLimit);
    final syncToken = repository.getLatestToken();

    final body = <String, dynamic>{
      'syncToken': syncToken,
      'songs': page.items
          .map(
            (record) => SongModel(
              id: record.id,
              title: record.title,
              artist: record.artist,
              albumId: record.albumId,
              duration: record.durationSeconds,
              trackNumber: record.trackNumber,
            ).toJson(),
          )
          .toList(),
      'pageInfo': V2PageInfo(
        cursor: cursor,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        limit: parsedLimit,
      ).toJson(),
    };
    return _jsonOk(body);
  }

  Response handlePlaylists(Request request) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      return _catalogUnavailable();
    }

    final parsedLimit = _parseLimit(
      request.url.queryParameters['limit'],
      defaultValue: _defaultEntityPageLimit,
      maxValue: _maxEntityPageLimit,
    );
    if (parsedLimit == null) {
      return _badRequest('limit must be an integer between 1 and 500');
    }

    final cursor = request.url.queryParameters['cursor'];
    final page =
        repository.listPlaylistsPage(cursor: cursor, limit: parsedLimit);
    final syncToken = repository.getLatestToken();

    final body = <String, dynamic>{
      'syncToken': syncToken,
      'playlists': page.items.map(
        (record) {
          final songIds = repository
              .listPlaylistSongs(record.id)
              .map((item) => item.songId)
              .toList();
          return PlaylistModel(
            id: record.id,
            name: record.name,
            songCount: record.songCount,
            duration: record.durationSeconds,
            songIds: songIds,
          ).toJson();
        },
      ).toList(),
      'pageInfo': V2PageInfo(
        cursor: cursor,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        limit: parsedLimit,
      ).toJson(),
    };
    return _jsonOk(body);
  }

  Response handleChanges(Request request) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      return _catalogUnavailable();
    }

    final since =
        _parseNonNegativeInt(request.url.queryParameters['since']) ?? 0;
    if (request.url.queryParameters['since'] != null &&
        _parseNonNegativeInt(request.url.queryParameters['since']) == null) {
      return _badRequest('since must be a non-negative integer');
    }

    final parsedLimit = _parseLimit(
      request.url.queryParameters['limit'],
      defaultValue: _defaultChangesLimit,
      maxValue: _maxChangesLimit,
    );
    if (parsedLimit == null) {
      return _badRequest('limit must be an integer between 1 and 1000');
    }

    final events = repository.readChangesSince(since, parsedLimit);
    final latestToken = repository.getLatestToken();
    final hasMore = events.length == parsedLimit;
    final toToken = events.isEmpty ? since : events.last.token;

    final body = <String, dynamic>{
      'fromToken': since,
      'toToken': toToken,
      'events': events
          .map(
            (event) => <String, dynamic>{
              'token': event.token,
              'op': event.op,
              'entityType': event.entityType,
              'entityId': event.entityId,
              'payload': _decodePayload(event.payloadJson),
              'occurredAt': DateTime.fromMillisecondsSinceEpoch(
                event.occurredEpochMs,
                isUtc: true,
              ).toIso8601String(),
            },
          )
          .toList(),
      'hasMore': hasMore,
      'syncToken': latestToken,
    };

    return _jsonOk(body);
  }

  int? _parseLimit(
    String? rawValue, {
    required int defaultValue,
    required int maxValue,
  }) {
    if (rawValue == null || rawValue.isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(rawValue);
    if (parsed == null || parsed <= 0 || parsed > maxValue) {
      return null;
    }
    return parsed;
  }

  int? _parseNonNegativeInt(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(rawValue);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  String? _cursorPosition(String? previousCursor, Iterable<String> pageIds) {
    String? current = previousCursor;
    for (final id in pageIds) {
      current = id;
    }
    return current;
  }

  _BootstrapCursor? _parseBootstrapCursor(String? rawCursor) {
    if (rawCursor == null || rawCursor.isEmpty) {
      return const _BootstrapCursor();
    }

    try {
      final decodedBytes = base64Url.decode(rawCursor);
      final decodedJson = jsonDecode(utf8.decode(decodedBytes));
      if (decodedJson is! Map<String, dynamic>) {
        return null;
      }
      return _BootstrapCursor(
        albumsCursor: decodedJson['albumsCursor'] as String?,
        songsCursor: decodedJson['songsCursor'] as String?,
        playlistsCursor: decodedJson['playlistsCursor'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String _encodeBootstrapCursor(_BootstrapCursor cursor) {
    final map = <String, dynamic>{
      'albumsCursor': cursor.albumsCursor,
      'songsCursor': cursor.songsCursor,
      'playlistsCursor': cursor.playlistsCursor,
    };
    return base64Url.encode(utf8.encode(jsonEncode(map)));
  }

  Map<String, dynamic>? _decodePayload(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Response _catalogUnavailable() {
    return Response(
      503,
      body: jsonEncode({
        'error': {
          'code': 'CATALOG_UNAVAILABLE',
          'message': 'Catalog database is not initialized',
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _badRequest(String message) {
    return Response.badRequest(
      body: jsonEncode({
        'error': {
          'code': 'INVALID_REQUEST',
          'message': message,
        },
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _jsonOk(Map<String, dynamic> body) {
    return Response.ok(
      jsonEncode(body),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}

class _BootstrapCursor {
  const _BootstrapCursor({
    this.albumsCursor,
    this.songsCursor,
    this.playlistsCursor,
  });

  final String? albumsCursor;
  final String? songsCursor;
  final String? playlistsCursor;
}
