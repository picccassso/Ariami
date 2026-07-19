import 'dart:convert';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/library/library_repository.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_support/private_sqflite_ffi.dart';

void main() {
  group('PlaylistService metadata rehydration', () {
    late PlaylistService playlistService;

    setUpAll(() async {
      await initPrivateSqfliteFfi('ariami_playlist_rehydration_');
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

      final updatedCount = await playlistService.rehydrateSongMetadataFromLibrary(
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

      final updatedCount =
          await playlistService.rehydrateSongMetadataFromLibrary(
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

    test('visible server playlists apply the account edit overlay', () {
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'playlist-1',
          name: 'Base name',
          songIds: const <String>['song-1', 'song-2', 'song-3'],
          songCount: 3,
        ),
      ]);
      playlistService.setServerPlaylistEditsForTest(<ServerPlaylistEdit>[
        ServerPlaylistEdit(
          playlistId: 'playlist-1',
          name: 'Synced name',
          songIds: const <String>['song-2', 'song-1'],
          baseSnapshot: const <String>['song-1', 'song-2', 'song-3'],
        ),
      ]);

      final visible = playlistService.visibleServerPlaylists.single;

      expect(visible.name, 'Synced name');
      expect(visible.songIds, const <String>['song-2', 'song-1']);
      expect(visible.songCount, 2);
    });

    test('effective server playlist appends songs added to the base later', () {
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'playlist-1',
          name: 'Base name',
          songIds: const <String>['song-1', 'song-2', 'song-new'],
          songCount: 3,
        ),
      ]);
      playlistService.setServerPlaylistEditsForTest(<ServerPlaylistEdit>[
        ServerPlaylistEdit(
          playlistId: 'playlist-1',
          name: null,
          songIds: const <String>['song-2', 'song-1'],
          baseSnapshot: const <String>['song-1', 'song-2'],
        ),
      ]);

      final visible = playlistService.visibleServerPlaylists.single;

      expect(
        visible.songIds,
        const <String>['song-2', 'song-1', 'song-new'],
      );
      expect(visible.songCount, 3);
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

  group('PlaylistService imported playlist sync', () {
    late PlaylistService playlistService;

    setUpAll(() async {
      await initPrivateSqfliteFfi('ariami_playlist_sync_');
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

    Future<PlaylistModel> importBasePlaylist() async {
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'server-1',
          name: 'Base name',
          songIds: const <String>['song-1', 'song-2', 'song-3'],
          songCount: 3,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      return playlistService.importServerPlaylist(
        playlistService.visibleServerPlaylists.single,
        allSongs: <SongModel>[
          SongModel(id: 'song-1', title: 'One', artist: 'A', duration: 60),
          SongModel(id: 'song-2', title: 'Two', artist: 'B', duration: 60),
          SongModel(id: 'song-3', title: 'Three', artist: 'C', duration: 60),
        ],
      );
    }

    test('imported copy mirrors the account edit overlay', () async {
      final imported = await importBasePlaylist();

      playlistService.setServerPlaylistEditsForTest(<ServerPlaylistEdit>[
        ServerPlaylistEdit(
          playlistId: 'server-1',
          name: 'Synced name',
          songIds: const <String>['song-3', 'song-1'],
          baseSnapshot: const <String>['song-1', 'song-2', 'song-3'],
        ),
      ]);
      await playlistService.syncImportedPlaylistsFromServer();

      final local = playlistService.getPlaylist(imported.id)!;
      expect(local.name, 'Synced name');
      expect(local.songIds, const <String>['song-3', 'song-1']);
    });

    test('imported copy without an edit overlay stays a local fork', () async {
      final imported = await importBasePlaylist();

      await playlistService.reorderSongs(
        playlistId: imported.id,
        oldIndex: 2,
        newIndex: 0,
      );
      await playlistService.syncImportedPlaylistsFromServer();

      final local = playlistService.getPlaylist(imported.id)!;
      expect(local.songIds, const <String>['song-3', 'song-1', 'song-2']);
      expect(local.name, 'Base name');
    });

    test('edit made without a connection is queued for a later push',
        () async {
      final imported = await importBasePlaylist();

      await playlistService.reorderSongs(
        playlistId: imported.id,
        oldIndex: 2,
        newIndex: 0,
      );
      // The push runs unawaited after the local mutation.
      await Future<void>.delayed(Duration.zero);

      expect(playlistService.pendingImportedEditPushIds, {imported.id});
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('ariami_pending_imported_edit_pushes'),
        contains(imported.id),
      );
    });

    test('like made without a connection is queued for cross-device sync',
        () async {
      await playlistService.toggleLikedSong(
        'song-liked-offline',
        'album-1',
        title: 'Offline Like',
        artist: 'Ariami',
        duration: 180,
      );
      // The server push runs unawaited after the local mutation.
      await Future<void>.delayed(Duration.zero);

      expect(playlistService.isLikedSong('song-liked-offline'), isTrue);
      expect(
        playlistService.pendingImportedEditPushIds,
        {PlaylistService.likedSongsId},
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('ariami_pending_imported_edit_pushes'),
        contains(PlaylistService.likedSongsId),
      );
    });

    test('inbound sync leaves playlists with queued offline edits untouched',
        () async {
      final imported = await importBasePlaylist();

      await playlistService.reorderSongs(
        playlistId: imported.id,
        oldIndex: 2,
        newIndex: 0,
      );
      await Future<void>.delayed(Duration.zero);

      playlistService.setServerPlaylistEditsForTest(<ServerPlaylistEdit>[
        ServerPlaylistEdit(
          playlistId: 'server-1',
          name: 'Synced name',
          songIds: const <String>['song-2', 'song-1', 'song-3'],
          baseSnapshot: const <String>['song-1', 'song-2', 'song-3'],
        ),
      ]);
      await playlistService.syncImportedPlaylistsFromServer();

      final local = playlistService.getPlaylist(imported.id)!;
      expect(local.songIds, const <String>['song-3', 'song-1', 'song-2']);
      expect(local.name, 'Base name');
    });

    test('deleting an imported playlist drops its queued push', () async {
      final imported = await importBasePlaylist();

      await playlistService.reorderSongs(
        playlistId: imported.id,
        oldIndex: 2,
        newIndex: 0,
      );
      await Future<void>.delayed(Duration.zero);
      expect(playlistService.pendingImportedEditPushIds, {imported.id});

      await playlistService.deleteImportedPlaylist(
        imported.id,
        restoreServerVersion: true,
      );

      expect(playlistService.pendingImportedEditPushIds, isEmpty);
    });

    test('discarded edit overlay reverts the imported copy to base', () async {
      final imported = await importBasePlaylist();

      playlistService.setServerPlaylistEditsForTest(<ServerPlaylistEdit>[
        ServerPlaylistEdit(
          playlistId: 'server-1',
          name: 'Synced name',
          songIds: const <String>['song-3', 'song-1'],
          baseSnapshot: const <String>['song-1', 'song-2', 'song-3'],
        ),
      ]);
      await playlistService.syncImportedPlaylistsFromServer();

      playlistService.setServerPlaylistEditsForTest(const []);
      await playlistService.syncImportedPlaylistsFromServer(
        revertedServerPlaylistIds: {'server-1'},
      );

      final local = playlistService.getPlaylist(imported.id)!;
      expect(local.name, 'Base name');
      expect(local.songIds, const <String>['song-1', 'song-2', 'song-3']);
    });
  });

  group('PlaylistService backup import deduplication', () {
    late PlaylistService playlistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      playlistService = PlaylistService();
      await playlistService.clearAllPlaylistData();
    });

    Future<void> seedLikedSongs() async {
      await playlistService.replaceAllPlaylists(<PlaylistModel>[
        PlaylistModel(
          id: PlaylistService.likedSongsId,
          name: 'Liked Songs',
          songIds: const <String>['local-liked-song'],
          createdAt: DateTime(2024),
          modifiedAt: DateTime(2024),
        ),
      ]);
    }

    test('importPlaylists preserves a backup entry with a duplicate name',
        () async {
      final local = await playlistService.createPlaylist(name: 'Summer Vibes');
      final backupPlaylist = PlaylistModel(
        id: 'backup-uuid',
        name: 'Summer Vibes',
        songIds: const <String>['song-1'],
        createdAt: DateTime(2024),
        modifiedAt: DateTime(2024),
      );

      final imported = await playlistService
          .importPlaylists(<PlaylistModel>[backupPlaylist]);

      expect(imported, 1);
      expect(playlistService.playlists.length, 2);
      expect(playlistService.getPlaylist(local.id)?.id, local.id);
      expect(playlistService.getPlaylist(backupPlaylist.id)?.id,
          backupPlaylist.id);
    });

    test('importServerPlaylist creates a distinct playlist for the same name',
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

      expect(result.id, isNot(local.id));
      expect(playlistService.playlists.length, 2);
      expect(playlistService.hiddenServerPlaylistIds, contains('server-1'));
      expect(playlistService.getServerPlaylistId(result.id), 'server-1');
      expect(playlistService.getServerPlaylistId(local.id), isNull);
    });

    test('importAllServerPlaylists preserves duplicate display names',
        () async {
      await playlistService.createPlaylist(name: 'Summer Vibes');
      final imported = await playlistService.importAllServerPlaylists(
        <ServerPlaylist>[
          ServerPlaylist(
            id: 'server-1',
            name: 'Summer Vibes',
            songIds: const <String>['song-1'],
            songCount: 1,
          ),
        ],
        allSongs: const <SongModel>[],
      );

      expect(imported, 1);
      expect(
        playlistService.playlists
            .where((playlist) => playlist.name == 'Summer Vibes'),
        hasLength(2),
      );
    });

    test('server Liked Songs imports beside the account-owned playlist',
        () async {
      await seedLikedSongs();
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'server-liked',
          name: 'Liked Songs',
          songIds: const <String>['server-liked-song'],
          songCount: 1,
        ),
      ]);
      await pumpEventQueue();

      final imported = await playlistService.importServerPlaylist(
        playlistService.visibleServerPlaylists.single,
        allSongs: const <SongModel>[],
      );

      expect(imported.id, isNot(PlaylistService.likedSongsId));
      expect(
        playlistService.playlists
            .where((playlist) => playlist.name == 'Liked Songs'),
        hasLength(2),
      );
      expect(
        playlistService.getServerPlaylistId(imported.id),
        'server-liked',
      );
      expect(
        playlistService.getServerPlaylistId(PlaylistService.likedSongsId),
        isNull,
      );
    });

    test('repairs an already-hidden Liked Songs name collision once', () async {
      await seedLikedSongs();
      await playlistService.applyServerImportState(
        hiddenServerPlaylistIds: {'server-liked'},
        importedFromServer: {
          PlaylistService.likedSongsId: 'server-liked',
        },
        replace: true,
      );

      final serverPlaylist = ServerPlaylist(
        id: 'server-liked',
        name: 'Liked Songs',
        songIds: const <String>['server-liked-song'],
        songCount: 1,
      );
      playlistService.updateServerPlaylists(<ServerPlaylist>[serverPlaylist]);
      await pumpEventQueue();

      expect(playlistService.visibleServerPlaylists.single.id, 'server-liked');
      expect(
        playlistService.hiddenServerPlaylistIds,
        isNot(contains('server-liked')),
      );
      expect(
        playlistService.getServerPlaylistId(PlaylistService.likedSongsId),
        isNull,
      );

      final imported = await playlistService.importServerPlaylist(
        serverPlaylist,
        allSongs: const <SongModel>[],
      );
      await playlistService.deleteImportedPlaylist(
        imported.id,
        restoreServerVersion: false,
      );
      playlistService.updateServerPlaylists(<ServerPlaylist>[
        ServerPlaylist(
          id: 'server-liked',
          name: 'Liked Songs',
          songIds: const <String>['server-liked-song', 'new-song'],
          songCount: 2,
        ),
      ]);
      await pumpEventQueue();

      expect(
        playlistService.hiddenServerPlaylistIds,
        contains('server-liked'),
      );
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

    test(
        'applyServerImportState persists hidden server ids to SharedPreferences',
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

    test('replaceAllPlaylists does not hide a server playlist by name',
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
      expect(
        jsonDecode(hiddenJson!) as List<dynamic>,
        isNot(contains('server-1')),
      );
    });
  });

  group('PlaylistService unavailable-song cleanup', () {
    late PlaylistService playlistService;

    final librarySongs = <SongModel>[
      SongModel(
        id: 'song-live',
        title: 'Live Song',
        artist: 'Artist',
        albumId: 'album-1',
        duration: 200,
        trackNumber: 1,
      ),
    ];

    setUpAll(() async {
      await initPrivateSqfliteFfi('ariami_playlist_cleanup_');
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

    Future<String> seedPlaylist() async {
      final playlist = await playlistService.createPlaylist(name: 'Mixed');
      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-live',
        title: 'Live Song',
        artist: 'Artist',
        duration: 200,
      );
      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-ghost',
        title: 'Missing from library',
      );
      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'song-downloaded',
        title: 'Downloaded Song',
        artist: 'Artist',
        duration: 100,
      );
      return playlist.id;
    }

    test('preview counts ghosts but spares downloaded and library songs',
        () async {
      final playlistId = await seedPlaylist();

      final preview = await playlistService.previewUnavailableSongCleanup(
        librarySongs: librarySongs,
        downloadedSongIds: {'song-downloaded'},
      );

      expect(preview.playlistCount, 1);
      expect(preview.songCount, 1);
      // Preview must not mutate.
      expect(playlistService.getPlaylist(playlistId)!.songIds,
          ['song-live', 'song-ghost', 'song-downloaded']);
    });

    test('remove drops only the ghost entries and persists', () async {
      final playlistId = await seedPlaylist();

      final result = await playlistService.removeUnavailableSongs(
        librarySongs: librarySongs,
        downloadedSongIds: {'song-downloaded'},
      );

      expect(result.playlistCount, 1);
      expect(result.songCount, 1);
      expect(playlistService.getPlaylist(playlistId)!.songIds,
          ['song-live', 'song-downloaded']);

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('ariami_playlists')!) as List<dynamic>;
      final storedIds =
          (stored.single as Map<String, dynamic>)['songIds'] as List<dynamic>;
      expect(storedIds, ['song-live', 'song-downloaded']);
    });

    test('empty library yields zero counts and never deletes', () async {
      final playlistId = await seedPlaylist();

      final result = await playlistService.removeUnavailableSongs(
        librarySongs: const <SongModel>[],
        downloadedSongIds: const <String>{},
      );

      expect(result.isEmpty, isTrue);
      expect(playlistService.getPlaylist(playlistId)!.songIds, hasLength(3));
    });

    test('id-churned entries heal via remap instead of being removed',
        () async {
      final playlist = await playlistService.createPlaylist(name: 'Churned');
      // Stale id, but metadata matches a library song exactly — the remap
      // pass must rescue it before the sweep counts it.
      await playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: 'old-id-after-move',
        title: 'Live Song',
        artist: 'Artist',
        duration: 200,
      );

      final result = await playlistService.removeUnavailableSongs(
        librarySongs: librarySongs,
        downloadedSongIds: const <String>{},
      );

      expect(result.isEmpty, isTrue);
      expect(playlistService.getPlaylist(playlist.id)!.songIds, ['song-live']);
    });
  });
}
