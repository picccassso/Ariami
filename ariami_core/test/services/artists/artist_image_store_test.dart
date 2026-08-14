import 'dart:io';

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
  });
}
