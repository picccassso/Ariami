import 'dart:io';

import 'package:ariami_core/services/playlists/playlist_edit_reconcile.dart';
import 'package:ariami_core/services/playlists/playlist_edit_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PlaylistEditStore', () {
    late Directory directory;
    late PlaylistEditStore store;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('ariami_playlist_edits_');
      store = PlaylistEditStore(
        databasePath: p.join(directory.path, 'playlist_edits.db'),
      );
      store.initialize();
    });

    tearDown(() async {
      store.close();
      await directory.delete(recursive: true);
    });

    test('puts, updates, and lists edits for one user', () {
      final first = store.put(
        'user-a',
        'playlist-1',
        songIds: <String>['song-2', 'song-1'],
        name: 'Road Mix',
        baseSnapshot: <String>['song-1', 'song-2', 'song-3'],
        sourceDeviceId: 'device-a',
      );
      final updated = store.put(
        'user-a',
        'playlist-1',
        songIds: <String>['song-1'],
        name: null,
        baseSnapshot: <String>['song-1', 'song-2', 'song-3'],
      );

      expect(first.playlistId, 'playlist-1');
      expect(updated.songIds, <String>['song-1']);
      expect(updated.name, isNull);
      expect(store.list('user-a'), hasLength(1));
      expect(store.list('user-a').single.baseSnapshot,
          <String>['song-1', 'song-2', 'song-3']);
    });

    test('edits are isolated and delete only removes the requesting user', () {
      store.put(
        'user-a',
        'shared-playlist',
        songIds: <String>['song-a'],
        baseSnapshot: <String>['song-a'],
      );
      store.put(
        'user-b',
        'shared-playlist',
        songIds: <String>['song-b'],
        baseSnapshot: <String>['song-b'],
      );

      expect(store.delete('user-a', 'shared-playlist'), isTrue);
      expect(store.list('user-a'), isEmpty);
      expect(store.list('user-b'), hasLength(1));
    });

    test('dedupes ids while preserving order', () {
      final edit = store.put(
        'user-a',
        'playlist-1',
        songIds: <String>['song-2', 'song-1', 'song-2'],
        baseSnapshot: <String>['song-1', 'song-1', 'song-2'],
      );

      expect(edit.songIds, <String>['song-2', 'song-1']);
      expect(edit.baseSnapshot, <String>['song-1', 'song-2']);
    });

    test('put throws on bad input', () {
      expect(
        () => store.put(
          'user-a',
          '',
          songIds: <String>['song-1'],
          baseSnapshot: <String>['song-1'],
        ),
        throwsArgumentError,
      );
      expect(
        () => store.put(
          'user-a',
          'playlist-1',
          songIds: <String>['song-1', ''],
          baseSnapshot: <String>['song-1'],
        ),
        throwsArgumentError,
      );
      expect(
        () => store.put(
          'user-a',
          'playlist-1',
          songIds: List<String>.generate(
            PlaylistEditStore.maxSongIds + 1,
            (index) => 'song-$index',
          ),
          baseSnapshot: const <String>[],
        ),
        throwsArgumentError,
      );
    });

    test('backup import is idempotent and does not trust user ids', () {
      final backup = <Map<String, dynamic>>[
        {
          'userId': 'spoofed-user',
          'playlistId': 'playlist-2',
          'name': 'Imported Mix',
          'songIds': <String>['song-2', 'song-1'],
          'baseSnapshot': <String>['song-1', 'song-2'],
        },
      ];

      expect(store.import('user-a', backup, replace: false), 1);
      expect(store.import('user-a', backup, replace: false), 1);

      expect(store.list('user-a'), hasLength(1));
      expect(store.list('spoofed-user'), isEmpty);
      expect(store.list('user-a').single.name, 'Imported Mix');
    });
  });

  group('reconcilePlaylistSongIds', () {
    test('no-edit passthrough filters to live songs in base order', () {
      expect(
        reconcilePlaylistSongIds(
          baseSongIds: <String>['song-1', 'song-2', 'song-3'],
          liveSongIds: <String>{'song-1', 'song-3'},
        ),
        <String>['song-1', 'song-3'],
      );
    });

    test('reorder preserves edited order', () {
      expect(
        reconcilePlaylistSongIds(
          baseSongIds: <String>['song-1', 'song-2', 'song-3'],
          liveSongIds: <String>{'song-1', 'song-2', 'song-3'},
          editSongIds: <String>['song-3', 'song-1', 'song-2'],
          baseSnapshot: <String>['song-1', 'song-2', 'song-3'],
        ),
        <String>['song-3', 'song-1', 'song-2'],
      );
    });

    test('remove keeps removed song out after rescan still lists it', () {
      expect(
        reconcilePlaylistSongIds(
          baseSongIds: <String>['song-1', 'song-2', 'song-3'],
          liveSongIds: <String>{'song-1', 'song-2', 'song-3'},
          editSongIds: <String>['song-1', 'song-3'],
          baseSnapshot: <String>['song-1', 'song-2', 'song-3'],
        ),
        <String>['song-1', 'song-3'],
      );
    });

    test('deleted-from-library song is dropped', () {
      expect(
        reconcilePlaylistSongIds(
          baseSongIds: <String>['song-1', 'song-2', 'song-3'],
          liveSongIds: <String>{'song-1', 'song-3'},
          editSongIds: <String>['song-2', 'song-3', 'song-1'],
          baseSnapshot: <String>['song-1', 'song-2', 'song-3'],
        ),
        <String>['song-3', 'song-1'],
      );
    });

    test('new-on-disk song is appended', () {
      expect(
        reconcilePlaylistSongIds(
          baseSongIds: <String>['song-1', 'song-2', 'song-3'],
          liveSongIds: <String>{'song-1', 'song-2', 'song-3'},
          editSongIds: <String>['song-2', 'song-1'],
          baseSnapshot: <String>['song-1', 'song-2'],
        ),
        <String>['song-2', 'song-1', 'song-3'],
      );
    });
  });
}
