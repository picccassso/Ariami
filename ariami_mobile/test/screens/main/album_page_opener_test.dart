import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/album_page_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testAlbum = AlbumModel(
    id: 'alb-1',
    title: 'Test Album',
    artist: 'Test Artist',
    songCount: 10,
    duration: 1800,
  );

  test('forwards opens to the registered callback', () {
    final opener = AlbumPageOpener();
    final received = <AlbumModel>[];

    opener.register(received.add);
    opener.open(testAlbum);

    expect(received, [testAlbum]);
  });

  test('unregister stops the handoff', () {
    final opener = AlbumPageOpener();
    final received = <AlbumModel>[];
    void open(AlbumModel album) => received.add(album);

    opener.register(open);
    opener.unregister(open);
    opener.open(testAlbum);

    expect(received, isEmpty);
  });

  test('open without a registered callback is a no-op', () {
    expect(() => AlbumPageOpener().open(testAlbum), returnsNormally);
  });
}
