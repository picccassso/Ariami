import 'dart:io';

import 'package:ariami_core/services/hidden/hidden_item_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late HiddenItemStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ariami_hidden_');
    store = HiddenItemStore(databasePath: p.join(directory.path, 'hidden.db'));
    store.initialize();
  });

  tearDown(() async {
    store.close();
    await directory.delete(recursive: true);
  });

  test('hides albums, playlists and artists, oldest first', () {
    store.hide('user-a', 'album', 'album-1');
    store.hide('user-a', 'playlist', 'playlist-1');
    store.hide('user-a', 'artist', 'Kanye West');

    expect(
      store.list('user-a').map((item) => item.key),
      <String>['album:album-1', 'playlist:playlist-1', 'artist:Kanye West'],
    );
  });

  test('hiding twice is idempotent and keeps the original row', () {
    final first = store.hide('user-a', 'album', 'album-1');
    final duplicate = store.hide('user-a', 'album', 'album-1');

    expect(duplicate.id, first.id);
    expect(duplicate.hiddenAt, first.hiddenAt);
    expect(store.list('user-a'), hasLength(1));
  });

  test('accounts are isolated and unhide only touches the requesting user', () {
    store.hide('user-a', 'album', 'shared-album');
    store.hide('user-b', 'album', 'shared-album');

    expect(store.unhide('user-a', 'album', 'shared-album'), isTrue);
    expect(store.list('user-a'), isEmpty);
    expect(store.list('user-b'), hasLength(1));
  });

  test('unhiding something that was never hidden reports no change', () {
    expect(store.unhide('user-a', 'album', 'album-1'), isFalse);
  });

  test('hideAll commits the whole selection and skips invalid rows', () {
    final hidden = store.hideAll('user-a', const [
      (type: 'album', targetId: 'album-1'),
      (type: 'song', targetId: 'song-1'), // unsupported type
      (type: 'artist', targetId: '   '), // blank target
      (type: 'playlist', targetId: 'playlist-1'),
    ]);

    expect(hidden.map((item) => item.key),
        <String>['album:album-1', 'playlist:playlist-1']);
    expect(store.list('user-a'), hasLength(2));
  });

  test('invalid types and targets are rejected', () {
    expect(() => store.hide('user-a', 'song', 'song-1'), throwsArgumentError);
    expect(() => store.hide('user-a', 'album', '  '), throwsArgumentError);
    expect(
      () => store.hide('user-a', 'artist', 'x' * 513),
      throwsArgumentError,
    );
  });

  test('target ids are trimmed on the way in and out', () {
    final item = store.hide('user-a', 'artist', '  Adele  ');

    expect(item.targetId, 'Adele');
    expect(store.unhide('user-a', 'artist', 'Adele'), isTrue);
  });

  test('rows survive a reopen', () {
    store.hide('user-a', 'artist', 'Adele');
    store.close();
    store = HiddenItemStore(databasePath: p.join(directory.path, 'hidden.db'));
    store.initialize();

    expect(store.list('user-a').single.key, 'artist:Adele');
  });
}
