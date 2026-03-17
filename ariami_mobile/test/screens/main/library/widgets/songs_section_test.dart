import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/screens/main/library/widgets/songs_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SongsSection', () {
    final testSongs = [
      SongModel(
        id: 'song-1',
        title: 'Test Song 1',
        artist: 'Test Artist 1',
        duration: 180,
      ),
      SongModel(
        id: 'song-2',
        title: 'Test Song 2',
        artist: 'Test Artist 2',
        duration: 200,
      ),
    ];

    final testOfflineSongs = [
      Song(
        id: 'offline-1',
        title: 'Offline Song 1',
        artist: 'Offline Artist 1',
        duration: const Duration(seconds: 180),
        filePath: '/test/path1.mp3',
        fileSize: 1000,
        modifiedTime: DateTime.now(),
      ),
    ];

    Widget buildTestWidget({
      required LibraryState state,
      bool isOffline = false,
      VoidCallback? onSongTap,
      VoidCallback? onOfflineSongTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SongsSection(
                state: state,
                isOffline: isOffline,
                onSongTap: (_) => onSongTap?.call(),
                onSongLongPress: (_) {},
                onOfflineSongTap: (_) => onOfflineSongTap?.call(),
                onOfflineSongLongPress: (_) {},
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('should display online songs', (tester) async {
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('Test Song 1'), findsOneWidget);
      expect(find.text('Test Song 2'), findsOneWidget);
    });

    testWidgets('should display offline songs when in offline mode',
        (tester) async {
      final state = LibraryState(
        offlineSongs: testOfflineSongs,
        isOfflineMode: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('Offline Song 1'), findsOneWidget);
    });

    testWidgets('should display empty message for offline mode with no songs',
        (tester) async {
      final state = const LibraryState(
        offlineSongs: [],
        isOfflineMode: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('No offline songs available'), findsOneWidget);
    });

    testWidgets('should display empty message for online mode with no songs',
        (tester) async {
      final state = const LibraryState(
        songs: [],
        isOfflineMode: false,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('No standalone songs found'), findsOneWidget);
    });

    testWidgets('should filter songs by downloads', (tester) async {
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
        showDownloadedOnly: true,
        downloadedSongIds: {'song-1'},
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('Test Song 1'), findsOneWidget);
      expect(find.text('Test Song 2'), findsNothing);
    });

    testWidgets('should call onSongTap when online song tapped',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        onSongTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Song 1'));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('should call onOfflineSongTap when offline song tapped',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        offlineSongs: testOfflineSongs,
        isOfflineMode: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        onOfflineSongTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offline Song 1'));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets(
        'should disable tap when offline and song not downloaded or cached',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isOffline: true,
        onSongTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Song 1'));
      await tester.pump();

      expect(tapped, false);
    });

    testWidgets('should enable tap when offline but song is downloaded',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
        downloadedSongIds: {'song-1'},
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isOffline: true,
        onSongTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Song 1'));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('should enable tap when offline but song is cached',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        songs: testSongs,
        isOfflineMode: false,
        isLoading: false,
        cachedSongIds: {'song-1'},
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isOffline: true,
        onSongTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Song 1'));
      await tester.pump();

      expect(tapped, true);
    });
  });
}
