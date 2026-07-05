import 'dart:io';

import 'package:ariami_core/services/pins/pinned_item_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late PinnedItemStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ariami_pins_');
    store = PinnedItemStore(databasePath: p.join(directory.path, 'pins.db'));
    store.initialize();
  });

  tearDown(() async {
    store.close();
    await directory.delete(recursive: true);
  });

  test('pins albums and playlists with stable explicit order', () {
    final album = store.pin('user-a', 'album', 'album-1');
    final playlist = store.pin('user-a', 'playlist', 'playlist-1');

    expect(album.sortOrder, 0);
    expect(playlist.sortOrder, 1);
    expect(
      store.list('user-a').map((pin) => pin.key),
      <String>['album:album-1', 'playlist:playlist-1'],
    );
  });

  test('duplicate pin is idempotent and keeps sortOrder', () {
    final first = store.pin('user-a', 'album', 'album-1');
    final duplicate = store.pin('user-a', 'album', 'album-1');

    expect(duplicate.id, first.id);
    expect(duplicate.sortOrder, first.sortOrder);
    expect(store.list('user-a'), hasLength(1));
  });

  test('pins are isolated and unpin only removes the requesting user', () {
    store.pin('user-a', 'album', 'shared-album');
    store.pin('user-b', 'album', 'shared-album');

    expect(store.unpin('user-a', 'album', 'shared-album'), isTrue);
    expect(store.list('user-a'), isEmpty);
    expect(store.list('user-b'), hasLength(1));
  });

  test('invalid type is rejected', () {
    expect(
      () => store.pin('user-a', 'song', 'song-1'),
      throwsArgumentError,
    );
  });

  test('backup import preserves order and is idempotent', () {
    final backup = <Map<String, dynamic>>[
      {'type': 'playlist', 'targetId': 'playlist-2', 'sortOrder': 7},
      {'type': 'album', 'targetId': 'missing-album', 'sortOrder': 3},
    ];

    expect(store.import('user-a', backup, replace: false), 2);
    expect(store.import('user-a', backup, replace: false), 2);

    final pins = store.list('user-a');
    expect(pins, hasLength(2));
    expect(pins.map((pin) => pin.sortOrder), <int>[3, 7]);
    expect(pins.map((pin) => pin.targetId),
        <String>['missing-album', 'playlist-2']);
  });

  test('replace import is idempotent and does not cross users', () {
    store.pin('user-a', 'album', 'old');
    store.pin('user-b', 'playlist', 'keep');
    final backup = <Map<String, dynamic>>[
      {'type': 'album', 'targetId': 'new', 'sortOrder': 2},
    ];

    store.import('user-a', backup, replace: true);
    store.import('user-a', backup, replace: true);

    expect(store.list('user-a').map((pin) => pin.targetId), <String>['new']);
    expect(store.list('user-b').map((pin) => pin.targetId), <String>['keep']);
  });

  test('malformed and unsupported backup rows are ignored safely', () {
    final imported = store.import(
      'user-a',
      <Map<String, dynamic>>[
        {'type': 12, 'targetId': 'bad-type'},
        {'type': 'album', 'targetId': 99},
        {'type': 'song', 'targetId': 'unsupported'},
        {'type': 'album', 'targetId': 'good'},
      ],
      replace: false,
    );

    expect(imported, 1);
    expect(store.list('user-a').single.targetId, 'good');
  });
}
