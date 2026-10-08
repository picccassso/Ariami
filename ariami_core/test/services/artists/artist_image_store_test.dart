import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/artists/artist_image_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArtistImageStore', () {
    late Directory directory;
    late ArtistImageStore store;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('ariami_artist_images_');
      store = ArtistImageStore(
        databasePath: p.join(directory.path, 'artist_images.db'),
      );
      store.initialize();
    });

    tearDown(() async {
      store.close();
      await directory.delete(recursive: true);
    });

    test('puts, replaces, and reads back an image with key normalization', () {
      final first = store.put(
        'user-a',
        'Daft Punk',
        bytes: <int>[1, 2, 3],
        contentType: 'image/jpeg',
      );
      expect(first.artistName, 'Daft Punk');
      expect(first.artistKey, 'daft punk');

      final replaced = store.put(
        'user-a',
        'daft  PUNK ',
        bytes: <int>[9, 8, 7, 6],
        contentType: 'image/png',
      );

      expect(replaced.updatedAt, greaterThan(first.updatedAt));
      expect(replaced.artistName, 'daft  PUNK');
      expect(replaced.artistKey, 'daft punk');

      final record = store.find('user-a', 'DAFT PUNK');
      expect(record, isNotNull);
      expect(record!.contentType, 'image/png');
      expect(record.bytes, <int>[9, 8, 7, 6]);
      expect(store.list('user-a'), hasLength(1));
    });

    test('images are isolated per user', () {
      store.put(
        'user-a',
        'Radiohead',
        bytes: <int>[1],
        contentType: 'image/jpeg',
      );
      store.put(
        'user-b',
        'Radiohead',
        bytes: <int>[2],
        contentType: 'image/png',
      );

      expect(store.delete('user-a', 'Radiohead'), isTrue);
      expect(store.find('user-a', 'Radiohead'), isNull);
      expect(store.find('user-b', 'Radiohead'), isNotNull);
    });

    test('delete returns false when nothing was stored', () {
      expect(store.delete('user-a', 'missing-artist'), isFalse);
    });

    test('rejects invalid artist names and oversized payloads', () {
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
          'Daft Punk',
          bytes: List<int>.filled(ArtistImageStore.maxImageBytes + 1, 0),
          contentType: 'image/jpeg',
        ),
        throwsArgumentError,
      );
      expect(
        () => store.put(
          'user-a',
          'Daft Punk',
          bytes: const <int>[],
          contentType: 'image/jpeg',
        ),
        throwsArgumentError,
      );
    });

    test('shrinkImages replaces shrunk rows with a new version only', () async {
      final before = store.put('user-a', 'one',
          bytes: <int>[1, 2, 3, 4], contentType: 'image/jpeg');
      store.put('user-a', 'two', bytes: <int>[9, 9], contentType: 'image/jpeg');

      final seen = <int>[];
      final count = await store.shrinkImages((bytes, contentType) async {
        seen.add(bytes.length);
        return bytes.length == 4 ? Uint8List.fromList([7]) : null;
      });

      expect(count, 1);
      expect(seen..sort(), [2, 4]);
      final shrunk = store.find('user-a', 'one');
      expect(shrunk!.bytes, [7]);
      expect(shrunk.contentType, 'image/jpeg');
      expect(shrunk.updatedAt, greaterThan(before.updatedAt));
      expect(store.find('user-a', 'two')!.bytes, [9, 9]);
    });

    test('shrinkImages leaves a row replaced while shrinking', () async {
      store.put('user-a', 'one',
          bytes: <int>[1, 2, 3, 4], contentType: 'image/jpeg');

      final count = await store.shrinkImages((bytes, contentType) async {
        store.put('user-a', 'one',
            bytes: <int>[5, 5, 5], contentType: 'image/jpeg');
        return Uint8List.fromList([7]);
      });

      expect(count, 0);
      expect(store.find('user-a', 'one')!.bytes, [5, 5, 5]);
    });
  });
}
