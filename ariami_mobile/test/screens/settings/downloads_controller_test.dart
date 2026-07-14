import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/settings/downloads/downloads_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist bulk downloads include only local library playlists', () {
    final now = DateTime(2026);
    final importedPlaylist = PlaylistModel(
      id: 'local-imported-playlist',
      name: 'Imported Mix',
      songIds: const <String>['local-song', 'missing-song'],
      createdAt: now,
      modifiedAt: now,
    );

    final resolvedSongIds = DownloadsController.resolveLocalPlaylistSongIds(
      <PlaylistModel>[importedPlaylist],
      validSongIds: const <String>{
        'local-song',
        'missing-song',
        'unimported-server-playlist-song',
      },
    );

    expect(resolvedSongIds, <String>{'local-song', 'missing-song'});
    expect(resolvedSongIds, isNot(contains('unimported-server-playlist-song')));
  });

  test('playlist bulk downloads discard songs missing from the library', () {
    final now = DateTime(2026);
    final playlist = PlaylistModel(
      id: 'local-playlist',
      name: 'Local Mix',
      songIds: const <String>['available-song', 'stale-song'],
      createdAt: now,
      modifiedAt: now,
    );

    final resolvedSongIds = DownloadsController.resolveLocalPlaylistSongIds(
      <PlaylistModel>[playlist],
      validSongIds: const <String>{'available-song'},
    );

    expect(resolvedSongIds, <String>{'available-song'});
  });
}
