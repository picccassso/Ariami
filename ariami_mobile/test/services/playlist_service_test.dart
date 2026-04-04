import 'dart:convert';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlaylistService metadata rehydration', () {
    late PlaylistService playlistService;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      playlistService = PlaylistService();
      await playlistService.replaceAllPlaylists(const <PlaylistModel>[]);
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
  });
}
