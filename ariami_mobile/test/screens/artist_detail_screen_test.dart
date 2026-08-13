import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/screens/artist_detail_screen.dart';
import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:ariami_mobile/widgets/common/artist_link.dart';
import 'package:ariami_mobile/widgets/library/song_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The stats overlay needs the service initialized (its stream controllers
    // and database are created lazily on initialize).
    await StreamingStatsService().initialize();
  });

  tearDownAll(uninstallSqfliteTestMocks);

  AlbumModel album(
    String id,
    String title,
    String artist, {
    bool hasArtwork = true,
  }) =>
      AlbumModel(
        id: id,
        title: title,
        artist: artist,
        coverArt: hasArtwork ? '/api/artwork/$id' : null,
        songCount: 1,
        duration: 180,
      );

  SongModel track(String id, String title, String artist, String? albumId) =>
      SongModel(
        id: id,
        title: title,
        artist: artist,
        albumId: albumId,
        duration: 180,
      );

  PlaylistModel playlist(String id, String name, List<String> songIds) =>
      PlaylistModel(
        id: id,
        name: name,
        songIds: songIds,
        songAlbumIds: {
          for (final songId in songIds) songId: 'a1',
        },
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
      );

  /// Reset the shared singletons so no test state leaks into the next one.
  Future<void> resetSingletons() async {
    LibraryController().setStateForTest(const LibraryState());
    await PlaylistService().replaceAllPlaylists(const <PlaylistModel>[]);
    StreamingStatsService().setAccountStatsOverlay(null);
  }

  Future<void> pumpArtistPage(
    WidgetTester tester,
    String artistName, {
    Size size = const Size(1200, 4000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ArtistDetailScreen(artistName: artistName)),
    );
    await tester.pump();
  }

  group('ArtistDetailScreen', () {
    testWidgets('shows the empty state when the artist is unknown',
        (tester) async {
      await resetSingletons();

      await pumpArtistPage(tester, 'Nobody');

      expect(find.text("This artist isn't in your library."), findsOneWidget);
    });

    testWidgets('top songs ranked by play count, capped at 10', (tester) async {
      await resetSingletons();

      LibraryController().setStateForTest(
        LibraryState(
          albums: [album('a1', 'Album One', 'Test Artist')],
          songs: [
            for (var i = 1; i <= 12; i++)
              track('s$i', 'Song $i', 'Test Artist', 'a1'),
          ],
          isLoading: false,
        ),
      );
      StreamingStatsService().setAccountStatsOverlay(
        [
          SongStats(
            songId: 's3',
            playCount: 50,
            totalTime: const Duration(minutes: 5),
          ),
          SongStats(
            songId: 's1',
            playCount: 10,
            totalTime: const Duration(minutes: 1),
          ),
          SongStats(
            songId: 's2',
            playCount: 5,
            totalTime: const Duration(minutes: 2),
          ),
        ],
        activeDays: 1,
      );

      await pumpArtistPage(tester, 'Test Artist');

      expect(find.text('Top songs'), findsOneWidget);
      expect(find.byType(SongListItem), findsNWidgets(10));

      final renderedTitles = tester
          .widgetList<SongListItem>(find.byType(SongListItem))
          .map((item) => item.song.title)
          .toList();
      expect(renderedTitles.first, 'Song 3');
      expect(renderedTitles[1], 'Song 1');
      expect(renderedTitles[2], 'Song 2');
      expect(renderedTitles, isNot(contains('Song 11')));
      expect(renderedTitles, isNot(contains('Song 12')));
    });

    testWidgets('renders albums and appears-on sections', (tester) async {
      await resetSingletons();

      LibraryController().setStateForTest(
        LibraryState(
          albums: [
            album('a1', 'Own Album A', 'Test Artist'),
            album('a2', 'Own Album B', 'Test Artist'),
            album('c1', 'Now That Compilation', 'Other Artist'),
          ],
          songs: [
            track('s1', 'Song 1', 'Test Artist', 'a1'),
            track('s2', 'Song 2', 'Test Artist', 'a2'),
            track('s3', 'Featured Song', 'Test Artist', 'c1'),
          ],
          isLoading: false,
        ),
      );

      await pumpArtistPage(tester, 'Test Artist');

      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Appears on'), findsOneWidget);
      expect(find.text('Own Album A'), findsOneWidget);
      expect(find.text('Own Album B'), findsOneWidget);
      expect(find.text('Now That Compilation'), findsOneWidget);
    });

    testWidgets('header skips coverless albums and falls back to song art',
        (tester) async {
      await resetSingletons();

      LibraryController().setStateForTest(
        LibraryState(
          albums: [
            album('a1', 'Coverless', 'Test Artist', hasArtwork: false),
            album('a2', 'With Art', 'Test Artist'),
          ],
          songs: [track('s1', 'Song 1', 'Test Artist', 'a1')],
          isLoading: false,
        ),
      );

      await pumpArtistPage(tester, 'Test Artist');

      expect(
          find.byKey(const ValueKey('artist-header-album-a2')), findsOneWidget);

      LibraryController().setStateForTest(
        LibraryState(
          albums: [
            album('a1', 'Coverless', 'Test Artist', hasArtwork: false),
          ],
          songs: [track('s1', 'Song 1', 'Test Artist', 'a1')],
          isLoading: false,
        ),
      );
      await tester.pump();

      expect(
          find.byKey(const ValueKey('artist-header-song-s1')), findsOneWidget);
    });

    testWidgets('shows only playlists containing the artist songs',
        (tester) async {
      await resetSingletons();

      LibraryController().setStateForTest(
        LibraryState(
          albums: [album('a1', 'Album One', 'Test Artist')],
          songs: [track('s1', 'Song 1', 'Test Artist', 'a1')],
          isLoading: false,
        ),
      );
      await PlaylistService().replaceAllPlaylists([
        playlist('p1', 'Artist Mix', ['s1']),
        playlist('p2', 'Other Mix', ['other-song']),
      ]);

      await pumpArtistPage(tester, 'Test Artist');

      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Artist Mix'), findsOneWidget);
      expect(find.text('Other Mix'), findsNothing);
    });
  });

  group('ArtistLink', () {
    testWidgets('tap pushes the /artist route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const Scaffold(
                  body: ArtistLink(name: 'Test Artist'),
                ),
            '/artist': (_) => const Scaffold(body: Text('Artist Page')),
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Test Artist'));
      await tester.pumpAndSettle();

      expect(find.text('Artist Page'), findsOneWidget);
    });

    testWidgets('disabled link does not navigate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const Scaffold(
                  body: ArtistLink(name: 'Test Artist', enabled: false),
                ),
            '/artist': (_) => const Scaffold(body: Text('Artist Page')),
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Test Artist'));
      await tester.pumpAndSettle();

      expect(find.text('Artist Page'), findsNothing);
      expect(find.text('Test Artist'), findsOneWidget);
    });
  });
}
