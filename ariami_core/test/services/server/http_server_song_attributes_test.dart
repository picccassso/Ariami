import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('song attributes API', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late String baseUrl;
    late String token;

    Future<(int, Map<String, dynamic>)> send(
      String method,
      String path, [
      Object? body,
      bool authorized = true,
    ]) async {
      final client = HttpClient();
      try {
        final request =
            await client.openUrl(method, Uri.parse('$baseUrl$path'));
        if (authorized) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        final text = await utf8.decodeStream(response);
        return (
          response.statusCode,
          text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>,
        );
      } finally {
        client.close(force: true);
      }
    }

    Future<List<String>> queryIds(Map<String, Object?> body) async {
      final (status, json) = await send('POST', '/api/v2/songs/query', body);
      expect(status, 200, reason: '$json');
      return [for (final song in json['songs'] as List) song['id'] as String];
    }

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      testDir = await Directory.systemTemp.createTemp('ariami_song_attrs_');
      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
      server.setMusicFolderPath('/music');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
      _seedCatalog(server.libraryManager.createCatalogRepository()!);

      final port = await startHttpTestServer(server);
      baseUrl = 'http://127.0.0.1:$port';
      final credentials = {'username': 'tagger', 'password': 'tagger-pass'};
      expect((await send('POST', '/api/auth/register', credentials, false)).$1,
          200);
      final (_, login) = await send(
        'POST',
        '/api/auth/login',
        {...credentials, 'deviceId': 'tool', 'deviceName': 'Tool'},
        false,
      );
      token = login['sessionToken'] as String;
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) await testDir.delete(recursive: true);
    });

    test('requires a session', () async {
      final (status, _) = await send('POST', '/api/v2/songs/query', {}, false);
      expect(status, 401);
    });

    test('writes by path or song id and reports unknown tracks', () async {
      final (status, json) = await send('PUT', '/api/v2/song-attributes', {
        'items': [
          {
            'path': 'Artist/Album/01 Calm.flac',
            'attributes': {
              'instrumental': true,
              'genres': ['ambient', 'post-rock'],
              'bpm': 80,
            },
          },
          {
            'songId': 'song-b',
            'attributes': {'instrumental': false, 'bpm': 128.5},
          },
          {
            'path': 'Missing/track.flac',
            'attributes': {'bpm': 1},
          },
        ],
      });
      expect(status, 200);
      expect(json['results'], [
        {'songId': 'song-a', 'status': 'updated'},
        {'songId': 'song-b', 'status': 'updated'},
        {'status': 'not_found'},
      ]);

      final (_, all) = await send('POST', '/api/v2/songs/query', {});
      final songA = (all['songs'] as List).first as Map<String, dynamic>;
      expect(songA['path'], 'Artist/Album/01 Calm.flac');
      expect(songA['attributes'], {
        'instrumental': true,
        'genres': ['ambient', 'post-rock'],
        'bpm': 80,
      });

      // null removes a key and leaves the others alone.
      await send('PUT', '/api/v2/song-attributes', {
        'items': [
          {
            'songId': 'song-a',
            'attributes': {'bpm': null},
          },
        ],
      });
      final (_, after) = await send('POST', '/api/v2/songs/query', {});
      expect(((after['songs'] as List).first as Map)['attributes'], {
        'instrumental': true,
        'genres': ['ambient', 'post-rock'],
      });
    });

    test('rejects malformed writes', () async {
      for (final item in [
        {
          'attributes': {'bpm': 1}
        },
        {'songId': 'song-a', 'attributes': {}},
        {
          'songId': 'song-a',
          'attributes': {'mood': 'calm'}
        },
        {
          'songId': 'song-a',
          'attributes': {
            'genres': ['a', 1]
          }
        },
      ]) {
        final (status, _) = await send('PUT', '/api/v2/song-attributes', {
          'items': [item],
        });
        expect(status, 400, reason: '$item');
      }
    });

    test('filters, sorts, pages and resolves playlists per user', () async {
      await send('PUT', '/api/v2/song-attributes', {
        'items': [
          {
            'songId': 'song-a',
            'attributes': {
              'instrumental': true,
              'genres': ['ambient'],
              'bpm': 80
            },
          },
          {
            'songId': 'song-b',
            'attributes': {
              'instrumental': true,
              'genres': ['rock'],
              'bpm': 140
            },
          },
          {
            'songId': 'song-c',
            'attributes': {
              'instrumental': false,
              'genres': ['ambient']
            },
          },
        ],
      });

      expect(
        await queryIds({
          'where': [
            {'attr': 'instrumental', 'eq': true},
          ],
          'sort': [
            {'attr': 'bpm', 'dir': 'desc'},
          ],
        }),
        ['song-b', 'song-a'],
      );
      expect(
        await queryIds({
          'where': [
            {
              'attr': 'genres',
              'containsAny': ['ambient', 'jazz']
            },
            {'attr': 'bpm', 'exists': false},
          ],
        }),
        ['song-c'],
      );
      expect(
        await queryIds({
          'where': [
            {'attr': 'bpm', 'gte': 80, 'lt': 140},
          ],
        }),
        ['song-a'],
      );

      // Folder playlist holds song-a; a created playlist holds song-b.
      expect(
        await queryIds({
          'where': [
            {'attr': 'instrumental', 'eq': true},
            {'notInPlaylist': 'folder-1'},
          ],
        }),
        ['song-b'],
      );
      final (editStatus, _) = await send(
        'PUT',
        '/api/playlists/${Uri.encodeComponent('created:mine')}/edit',
        {
          'songIds': ['song-b'],
          'baseSnapshot': <String>[],
          'name': 'Mine'
        },
      );
      expect(editStatus, 200);
      expect(
        await queryIds({
          'where': [
            {'notInPlaylist': 'created:mine'},
          ],
        }),
        ['song-a', 'song-c'],
      );

      final (_, page1) =
          await send('POST', '/api/v2/songs/query', {'limit': 2});
      expect(page1['total'], 3);
      expect(page1['nextCursor'], '2');
      final (_, page2) = await send(
          'POST', '/api/v2/songs/query', {'limit': 2, 'cursor': '2'});
      expect([for (final s in page2['songs'] as List) s['id']], ['song-c']);
      expect(page2['nextCursor'], isNull);
    });

    test('rejects malformed queries', () async {
      for (final body in [
        {
          'where': [
            {'attr': 'bpm', 'like': 3},
          ],
        },
        {
          'where': [
            {'attr': 'bpm', 'gt': 'fast'},
          ],
        },
        {
          'where': [
            {'notInPlaylist': 'x', 'attr': 'bpm'},
          ],
        },
        {
          'sort': [
            {'attr': 'bpm', 'dir': 'up'},
          ],
        },
        {'limit': 0},
        {'cursor': 'abc'},
      ]) {
        final (status, _) = await send('POST', '/api/v2/songs/query', body);
        expect(status, 400, reason: '$body');
      }
    });
  });
}

void _seedCatalog(CatalogRepository repository) {
  for (final (id, path) in [
    ('song-a', '/music/Artist/Album/01 Calm.flac'),
    ('song-b', '/music/Artist/Album/02 Loud.flac'),
    ('song-c', '/music/Other/03 Voice.flac'),
  ]) {
    repository.upsertSong(CatalogSongRecord(
      id: id,
      filePath: path,
      title: id,
      artist: 'Artist',
      durationSeconds: 100,
      updatedToken: 1,
    ));
  }
  repository.upsertPlaylist(CatalogPlaylistRecord(
    id: 'folder-1',
    name: 'Folder',
    songCount: 1,
    durationSeconds: 100,
    updatedToken: 1,
  ));
  repository.upsertPlaylistSong(CatalogPlaylistSongRecord(
    playlistId: 'folder-1',
    songId: 'song-a',
    position: 0,
    updatedToken: 1,
  ));
}
