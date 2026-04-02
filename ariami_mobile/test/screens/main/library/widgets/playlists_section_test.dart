import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/screens/main/library/widgets/playlists_section.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  group('PlaylistsSection', () {
    // Create a simple mock by using the actual service and overriding properties
    late PlaylistService playlistService;

    setUp(() {
      playlistService = PlaylistService();
    });

    Widget buildTestWidget({
      required LibraryState state,
      required bool isGridView,
      VoidCallback? onCreatePlaylist,
      VoidCallback? onShowServerPlaylists,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PlaylistsSection(
            state: state,
            playlistService: playlistService,
            isGridView: isGridView,
            onCreatePlaylist: onCreatePlaylist ?? () {},
            onShowServerPlaylists: onShowServerPlaylists ?? () {},
            onPlaylistTap: (_) {},
            onPlaylistLongPress: (_) {},
          ),
        ),
      );
    }

    testWidgets('should render in grid view mode', (tester) async {
      const state = LibraryState(isLoading: false);

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isGridView: true,
      ));
      await tester.pump();

      // Should render without errors
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('should render in list view mode', (tester) async {
      const state = LibraryState(isLoading: false);

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isGridView: false,
      ));
      await tester.pump();

      // Empty-state list mode renders the create/import column.
      expect(find.text('Create Playlist'), findsOneWidget);
    });

    testWidgets('should display empty state when no playlists', (tester) async {
      const state = LibraryState(isLoading: false);

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isGridView: true,
      ));
      await tester.pump();

      // Should show create playlist card
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Create Playlist'), findsOneWidget);
    });

    testWidgets('should call onCreatePlaylist when triggered', (tester) async {
      var tapped = false;
      const state = LibraryState(isLoading: false);

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isGridView: false,
        onCreatePlaylist: () => tapped = true,
      ));
      await tester.pump();

      // Tap the empty-state create action.
      await tester.tap(find.text('Create Playlist'));
      await tester.pump();

      expect(tapped, true);
    });
  });
}
