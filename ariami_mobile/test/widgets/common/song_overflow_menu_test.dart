import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/widgets/common/song_overflow_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  late PlaylistService playlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    playlistService = PlaylistService();
    await playlistService.clearAllPlaylistData();
  });

  testWidgets('likes and dislikes a song from its overflow menu',
      (tester) async {
    final song = SongModel(
      id: 'song-1',
      title: 'Track One',
      artist: 'Artist One',
      albumId: 'album-1',
      duration: 180,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongOverflowMenu(song: song),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Like song'), findsOneWidget);
    await tester.tap(find.text('Like song'));
    await tester.pumpAndSettle();

    expect(playlistService.isLikedSong(song.id), isTrue);
    expect(
      playlistService.getPlaylist(PlaylistService.likedSongsId)?.songIds,
      contains(song.id),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Dislike song'), findsOneWidget);
    await tester.tap(find.text('Dislike song'));
    await tester.pumpAndSettle();

    expect(playlistService.isLikedSong(song.id), isFalse);
    expect(
      playlistService.getPlaylist(PlaylistService.likedSongsId)?.songIds,
      isNot(contains(song.id)),
    );
  });
}
