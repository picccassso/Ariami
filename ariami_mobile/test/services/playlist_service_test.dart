import 'dart:convert';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('PlaylistService metadata rehydration', () {
    late PlaylistService playlistService;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      playlistService = PlaylistService();
      await playlistService.clearAllPlaylistData();
    });

    tearDown(() async {
      final dbPath = p.join(await getDatabasesPath(), 'library_sync.db');
      await deleteDatabase(dbPath);
    });

    test('rehydrates missing playlist song metadata from library songs',
        () async {
      final playlist = await playlistService.createPlaylist(name: 'Test');

      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-1',
        title: 'Unknown Song',
        artist: 'Unknown Artist',
        duration: 0,
      );

      final updatedCount =
          await playlistService.rehydrateSongMetadataFromLibrary(
        <SongModel>[
          SongModel(
            id: 'song-1',
            title: 'Real Title',
            artist: 'Real Artist',
            albumId: 'album-1',
            duration: 243,
            trackNumber: 1,
          ),
        ],
      );

      final updatedPlaylist = playlistService.getPlaylist(playlist.id)!;
      final prefs = await SharedPreferences.getInstance();
      final storedPlaylists =
          jsonDecode(prefs.getString('ariami_playlists')!) as List<dynamic>;
      final storedPlaylist = storedPlaylists.single as Map<String, dynamic>;
      final storedDurations =
          storedPlaylist['songDurations'] as Map<String, dynamic>;

      expect(updatedCount, 1);
      expect(updatedPlaylist.songAlbumIds['song-1'], 'album-1');
      expect(updatedPlaylist.songTitles['song-1'], 'Real Title');
      expect(updatedPlaylist.songArtists['song-1'], 'Real Artist');
      expect(updatedPlaylist.songDurations['song-1'], 243);
      expect(storedDurations['song-1'], 243);
    });

    test('refreshes stale playlist song metadata when library has newer data',
        () async {
      final playlist = await playlistService.createPlaylist(name: 'Test');

      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-1',
        albumId: 'album-old',
        title: 'Old Title',
        artist: 'Old Artist',
        duration: 120,
      );

      final updatedCount =
          await playlistService.rehydrateSongMetadataFromLibrary(
        <SongModel>[
          SongModel(
            id: 'song-1',
            title: 'New Title',
            artist: 'New Artist',
            albumId: 'album-new',
            duration: 180,
            trackNumber: 7,
          ),
        ],
      );

      final updatedPlaylist = playlistService.getPlaylist(playlist.id)!;

      expect(updatedCount, 1);
      expect(updatedPlaylist.songAlbumIds['song-1'], 'album-new');
      expect(updatedPlaylist.songTitles['song-1'], 'New Title');
      expect(updatedPlaylist.songArtists['song-1'], 'New Artist');
      expect(updatedPlaylist.songDurations['song-1'], 180);
    });

    test('clears stale song album mapping when library song is standalone',
        () async {
      final playlist = await playlistService.createPlaylist(name: 'Test');

      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-1',
        albumId: 'legacy-playlist-album',
        title: 'Track Title',
        artist: 'Track Artist',
        duration: 210,
      );

      final updatedCount = await playlistService.rehydrateSongMetadataFromLibrary(
        <SongModel>[
          SongModel(
            id: 'song-1',
            title: 'Track Title',
            artist: 'Track Artist',
            albumId: null,
            duration: 210,
          ),
        ],
      );

      final updatedPlaylist = playlistService.getPlaylist(playlist.id)!;

      expect(updatedCount, 1);
      expect(updatedPlaylist.songAlbumIds.containsKey('song-1'), isFalse);
    });

    test('does not notify when server playlists are unchanged', () async {
      await playlistService.loadPlaylists();

      var notifyCount = 0;
      playlistService.addListener(() {
        notifyCount++;
      });

      final playlists = <ServerPlaylist>[
        ServerPlaylist(
          id: 'playlist-1',
          name: 'Playlist 1',
          songIds: const <String>['song-1', 'song-2'],
          songCount: 2,
        ),
      ];

      playlistService.updateServerPlaylists(playlists);
      await Future<void>.delayed(Duration.zero);

      playlistService.updateServerPlaylists(playlists);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, 1);
    });

    test('imports server playlist using fresher repository song durations',
        () async {
      final repository = LibraryRepository();

      await repository.applyBootstrapPage(
        V2BootstrapResponse(
          syncToken: 1,
          albums: const <AlbumModel>[],
          songs: <SongModel>[
            SongModel(
              id: 'song-1',
              title: 'Canonical Song',
              artist: 'Canonical Artist',
              albumId: 'album-1',
              duration: 245,
              trackNumber: 1,
            ),
          ],
          playlists: const <V2PlaylistModel>[],
          pageInfo: V2PageInfo(
            cursor: null,
            nextCursor: null,
            hasMore: false,
            limit: 200,
          ),
        ),
      );
      await repository.completeBootstrap(lastAppliedToken: 1);

      final playlist = await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Server Playlist',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: <SongModel>[
          SongModel(
            id: 'song-1',
            title: 'Stale Song',
            artist: 'Stale Artist',
            albumId: 'album-1',
            duration: 0,
          ),
        ],
      );

      expect(playlist.songTitles['song-1'], 'Canonical Song');
      expect(playlist.songArtists['song-1'], 'Canonical Artist');
      expect(playlist.songDurations['song-1'], 245);
    });
  });

  group('PlaylistService backup import deduplication', () {
    late PlaylistService playlistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      playlistService = PlaylistService();
      await playlistService.clearAllPlaylistData();
    });

    test('importPlaylists skips backup entry when local name already exists',
        () async {
      final local = await playlistService.createPlaylist(name: 'Summer Vibes');
      final backupPlaylist = PlaylistModel(
        id: 'backup-uuid',
        name: 'Summer Vibes',
        songIds: const <String>['song-1'],
        createdAt: DateTime(2024),
        modifiedAt: DateTime(2024),
      );

      final imported =
          await playlistService.importPlaylists(<PlaylistModel>[backupPlaylist]);

      expect(imported, 0);
      expect(playlistService.playlists.length, 1);
      expect(playlistService.getPlaylist(local.id)?.id, local.id);
    });

    test('importServerPlaylist returns existing local playlist for same name',
        () async {
      final local = await playlistService.createPlaylist(name: 'Summer Vibes');
      final serverPlaylist = ServerPlaylist(
        id: 'server-1',
        name: 'Summer Vibes',
        songIds: const <String>['song-1'],
        songCount: 1,
      );

      final result = await playlistService.importServerPlaylist(
        serverPlaylist,
        allSongs: const <SongModel>[],
      );

      expect(result.id, local.id);
      expect(playlistService.playlists.length, 1);
      expect(playlistService.hiddenServerPlaylistIds, contains('server-1'));
      expect(playlistService.getServerPlaylistId(local.id), 'server-1');
    });

    test('importServerPlaylist does not duplicate when server id is hidden',
        () async {
      final first = await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: const <SongModel>[],
      );

      final second = await playlistService.importServerPlaylist(
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
        allSongs: const <SongModel>[],
      );

      expect(second.id, first.id);
      expect(playlistService.playlists.length, 1);
    });

    test('applyServerImportState persists hidden server ids to SharedPreferences',
        () async {
      await playlistService.applyServerImportState(
        hiddenServerPlaylistIds: {'server-1'},
        importedFromServer: {'local-1': 'server-1'},
        replace: true,
      );

      final prefs = await SharedPreferences.getInstance();
      final hiddenJson = prefs.getString('ariami_hidden_server_playlists');
      final importedJson = prefs.getString('ariami_imported_from_server');

      expect(hiddenJson, isNotNull);
      expect(jsonDecode(hiddenJson!) as List<dynamic>, ['server-1']);
      expect(
        jsonDecode(importedJson!) as Map<String, dynamic>,
        {'local-1': 'server-1'},
      );
    });

    test('replaceAllPlaylists persists hidden server ids after auto-hide',
        () async {
      await playlistService.createPlaylist(name: 'Summer Vibes');
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'server-1',
          name: 'Summer Vibes',
          songIds: const <String>['song-1'],
          songCount: 1,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      await playlistService.replaceAllPlaylists(
        playlistService.playlists,
      );

      final prefs = await SharedPreferences.getInstance();
      final hiddenJson = prefs.getString('ariami_hidden_server_playlists');
      expect(hiddenJson, isNotNull);
      expect(jsonDecode(hiddenJson!) as List<dynamic>, contains('server-1'));
    });
  });
}
