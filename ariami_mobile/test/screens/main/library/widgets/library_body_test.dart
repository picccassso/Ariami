import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/screens/main/library/widgets/library_body.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
  });
  tearDownAll(uninstallSqfliteTestMocks);

  group('LibraryBody', () {
    late PlaylistService playlistService;
    late ScrollController scrollController;

    setUp(() {
      playlistService = PlaylistService();
      scrollController = ScrollController();
    });

    tearDown(() {
      scrollController.dispose();
    });

    final testAlbums = [
      AlbumModel(
        id: 'album-1',
        title: 'Test Album',
        artist: 'Test Artist',
        songCount: 5,
        duration: 1800,
      ),
    ];

    Widget buildTestWidget({
      required LibraryState state,
      bool isOffline = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: LibraryBody(
            state: state,
            isOffline: isOffline,
            scrollController: scrollController,
            onRefresh: () async {},
            onRetry: () {},
            onToggleAlbumsExpanded: () {},
            onToggleSongsExpanded: () {},
            playlistService: playlistService,
            isGridView: true,
            onCreatePlaylist: () {},
            onShowServerPlaylists: () {},
            onPlaylistTap: (_) {},
            onPlaylistLongPress: (_) {},
            onAlbumTap: (_) {},
            onAlbumLongPress: (_) {},
            onSongTap: (_) {},
            onSongLongPress: (_) {},
            onOfflineSongTap: (_) {},
            onOfflineSongLongPress: (_) {},
          ),
        ),
      );
    }

    testWidgets('shows full-screen spinner only for empty initial load',
        (tester) async {
      const state = LibraryState(isLoading: true);

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(CustomScrollView), findsNothing);
      expect(find.text('Test Album'), findsNothing);
    });

    testWidgets('keeps library visible while isLoading with existing content',
        (tester) async {
      final state = const LibraryState(isLoading: true).copyWith(
        albums: testAlbums,
        isLoading: true,
        isMixedMode: true,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pump();

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('Test Album'), findsOneWidget);
    });

    testWidgets('shows refresh indicator while keeping list visible',
        (tester) async {
      final state = const LibraryState(isLoading: false).copyWith(
        albums: testAlbums,
        isRefreshing: true,
        isMixedMode: true,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Test Album'), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });
}
