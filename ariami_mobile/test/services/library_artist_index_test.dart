import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/services/library/library_artist_index.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

AlbumModel _album(String id, String title, String artist) => AlbumModel(
      id: id,
      title: title,
      artist: artist,
      songCount: 0,
      duration: 0,
    );

SongModel _track(String id, String artist, {String? albumId}) => SongModel(
      id: id,
      title: id,
      artist: artist,
      albumId: albumId,
      duration: 0,
    );

PlaylistModel _playlist(String id, List<String> songIds) => PlaylistModel(
      id: id,
      name: id,
      songIds: songIds,
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
    );

void main() {
  group('LibraryArtistIndex.build', () {
    test('indexes albums per credited key, title-sorted', () {
      final index = LibraryArtistIndex.build(
        albums: [
          _album('solo', 'Solo Record', 'Alice'),
          _album('duo', 'Duo Record', 'Alice & Bob'),
        ],
        songs: const [],
        playlists: const [],
      );

      expect(
        index.albumsByArtist['alice']!.map((album) => album.id),
        ['duo', 'solo'],
        reason: 'albums sort by title within a key',
      );
      expect(
        index.albumsByArtist['bob']!.map((album) => album.id),
        ['duo'],
        reason: 'the shared album belongs to both credited artists',
      );
    });

    test('indexes tracks per credited key in library order', () {
      final index = LibraryArtistIndex.build(
        albums: const [],
        songs: [
          _track('s1', 'Alice'),
          _track('s2', 'Bob'),
          _track('s3', 'Alice, Bob'),
        ],
        playlists: const [],
      );

      expect(
        index.tracksByArtistKey['alice']!.map((song) => song.id),
        ['s1', 's3'],
      );
      expect(
        index.tracksByArtistKey['bob']!.map((song) => song.id),
        ['s2', 's3'],
      );
    });

    test('maps a playlist under every credited artist key of its songs', () {
      final index = LibraryArtistIndex.build(
        albums: const [],
        songs: [_track('duo-song', 'Alice, Bob')],
        playlists: [
          _playlist('duo-mix', ['duo-song']),
          _playlist('unrelated', ['missing']),
        ],
      );

      expect(
        index.playlistsByArtistKey['alice']!.map((playlist) => playlist.id),
        ['duo-mix'],
      );
      expect(
        index.playlistsByArtistKey['bob']!.map((playlist) => playlist.id),
        ['duo-mix'],
      );
      expect(
        index.playlistsByArtistKey['alice, bob']!
            .map((playlist) => playlist.id),
        ['duo-mix'],
      );
      expect(index.playlistsByArtistKey['zed'], isNull);
    });
  });

  group('LibraryController artist lookups', () {
    late LibraryController controller;

    setUpAll(() async {
      installSqfliteTestMocks();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await initializeSharedPrefs();
    });

    tearDownAll(uninstallSqfliteTestMocks);

    setUp(() async {
      controller = LibraryController();
      await PlaylistService().replaceAllPlaylists(const <PlaylistModel>[]);
    });

    test('artistAppearsOn surfaces compilations, not the artist\'s own albums',
        () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [
          _album('alice-own', 'Alice Owns', 'Alice'),
          _album('va-2', 'Beats Compilation', 'Various Artists'),
          _album('va-1', 'Hit Compilation', 'Various Artists'),
        ],
        songs: [
          _track('own', 'Alice', albumId: 'alice-own'),
          _track('standalone', 'Alice'),
          _track('comp-2', 'Alice', albumId: 'va-2'),
          _track('comp-1', 'Alice', albumId: 'va-1'),
        ],
      ));

      expect(
        controller.artistAppearsOn('Alice').map((album) => album.id),
        ['va-2', 'va-1'],
        reason: 'own albums are excluded and the rest sort by title',
      );
    });

    test('artistAppearsOn includes albums the artist is a guest on', () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [_album('alice-1', 'Alice Songs', 'Alice')],
        songs: [_track('feature', 'Bob', albumId: 'alice-1')],
      ));

      expect(
        controller.artistAppearsOn('Bob').map((album) => album.id),
        ['alice-1'],
      );
    });

    test('artistAppearsOn is empty for an unknown artist', () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [_album('alice-1', 'Alice Songs', 'Alice')],
        songs: [_track('t1', 'Alice', albumId: 'alice-1')],
      ));

      expect(controller.artistAppearsOn('Zed'), isEmpty);
    });

    test('artistAlbums normalizes case/whitespace and collaborative credits',
        () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [_album('duo', 'Duo Record', 'Alice & Bob')],
        songs: const [],
      ));

      expect(controller.artistAlbums('alice').map((album) => album.id),
          ['duo']);
      expect(
        controller.artistAlbums('  BOB ').map((album) => album.id),
        ['duo'],
        reason: 'both credited artists resolve to the shared album',
      );
    });

    test('artistTracks returns credited songs in library order', () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: const [],
        songs: [
          _track('s1', 'Alice'),
          _track('s2', 'Bob'),
          _track('s3', 'Alice, Bob'),
        ],
      ));

      expect(controller.artistTracks('Alice').map((song) => song.id),
          ['s1', 's3']);
      expect(controller.artistTracks('bob').map((song) => song.id),
          ['s2', 's3']);
    });

    test('playlistsWithArtist maps a playlist under every credited key',
        () async {
      await PlaylistService().replaceAllPlaylists([
        _playlist('duo-mix', ['duo-song']),
        _playlist('other', ['other-song']),
      ]);
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: const [],
        songs: [
          _track('duo-song', 'Alice, Bob'),
          _track('other-song', 'Carol'),
        ],
      ));

      expect(controller.playlistsWithArtist('alice').map((p) => p.id),
          ['duo-mix']);
      expect(controller.playlistsWithArtist('BOB').map((p) => p.id),
          ['duo-mix']);
      expect(controller.playlistsWithArtist('Carol').map((p) => p.id),
          ['other']);
      expect(controller.playlistsWithArtist('Zed'), isEmpty);
    });

    test('artist lookups refresh when the library state is replaced', () {
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [_album('a1', 'First Record', 'Alice')],
        songs: const [],
      ));
      expect(controller.artistAlbums('Alice').map((album) => album.id),
          ['a1']);

      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: [_album('a2', 'Second Record', 'Alice')],
        songs: const [],
      ));
      expect(controller.artistAlbums('Alice').map((album) => album.id),
          ['a2']);
    });

    test('playlist lookups refresh when the playlists are replaced',
        () async {
      await PlaylistService().replaceAllPlaylists([_playlist('p1', ['s1'])]);
      controller.setStateForTest(LibraryState(
        isLoading: false,
        albums: const [],
        songs: [_track('s1', 'Alice')],
      ));
      expect(controller.playlistsWithArtist('Alice').map((p) => p.id),
          ['p1']);

      await PlaylistService().replaceAllPlaylists([_playlist('p2', ['s1'])]);
      expect(controller.playlistsWithArtist('Alice').map((p) => p.id),
          ['p2']);
    });
  });
}
