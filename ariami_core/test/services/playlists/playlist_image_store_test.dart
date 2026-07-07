import 'dart:io';

import 'package:ariami_core/services/playlists/playlist_image_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PlaylistImageStore', () {
    late Directory directory;
    late PlaylistImageStore store;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('ariami_playlist_images_');
      store = PlaylistImageStore(
        databasePath: p.join(directory.path, 'playlist_images.db'),
      );
      store.initialize();
    });

    tearDown(() async {
      store.close();
      await directory.delete(recursive: true);
    });

    test('puts, replaces, and reads back an image', () {
      final first = store.put(
        'user-a',
        'playlist-1',
        bytes: <int>[1, 2, 3],
        contentType: 'image/jpeg',
      );
      final replaced = store.put(
        'user-a',
        'playlist-1',
        bytes: <int>[9, 8, 7, 6],
        contentType: 'image/png',
      );

      expect(replaced.updatedAt, greaterThan(first.updatedAt));
      final record = store.find('user-a', 'playlist-1');
      expect(record, isNotNull);
      expect(record!.contentType, 'image/png');
      expect(record.bytes, <int>[9, 8, 7, 6]);
      expect(store.list('user-a'), hasLength(1));
    });

    test('images are isolated per user', () {
      store.put(
        'user-a',
        'shared-playlist',
        bytes: <int>[1],
        contentType: 'image/jpeg',
      );
      store.put(
        'user-b',
        'shared-playlist',
        bytes: <int>[2],
        contentType: 'image/png',
      );

      expect(store.delete('user-a', 'shared-playlist'), isTrue);
      expect(store.find('user-a', 'shared-playlist'), isNull);
      expect(store.find('user-b', 'shared-playlist'), isNotNull);
    });

    test('delete returns false when nothing was stored', () {
      expect(store.delete('user-a', 'missing'), isFalse);
    });

    test('rejects invalid playlist ids and oversized payloads', () {
      expect(
        () => store.put(
          'user-a',
          '   ',
          bytes: <int>[1],
          contentType: 'image/jpeg',
        ),
        throwsArgumentError,
      );
      expect(
        () => store.put(
          'user-a',
          'playlist-1',
          bytes: List<int>.filled(PlaylistImageStore.maxImageBytes + 1, 0),
          contentType: 'image/jpeg',
        ),
        throwsArgumentError,
      );
      expect(
        () => store.put(
          'user-a',
          'playlist-1',
          bytes: const <int>[],
          contentType: 'image/jpeg',
        ),
        throwsArgumentError,
      );
    });
  });
}
