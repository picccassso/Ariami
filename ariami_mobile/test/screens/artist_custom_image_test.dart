import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/artist_detail_screen.dart';
import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/services/artist_image_service.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_support/sqflite_mock.dart';

void main() {
  setUpAll(() async {
    installSqfliteTestMocks();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StreamingStatsService().initialize();
  });

  tearDownAll(uninstallSqfliteTestMocks);

  tearDown(() {
    ArtistImageService().clear();
  });

  testWidgets('ArtistDetailScreen renders custom artist image if available',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    LibraryController().setStateForTest(
      LibraryState(
        albums: [
          AlbumModel(
            id: 'alb-1',
            title: 'Discovery',
            artist: 'Daft Punk',
            coverArt: '/api/artwork/alb-1',
            songCount: 1,
            duration: 180,
          ),
        ],
        songs: [
          SongModel(
            id: 'song-1',
            title: 'One More Time',
            artist: 'Daft Punk',
            albumId: 'alb-1',
            duration: 180,
          ),
        ],
      ),
    );

    // Initial render without custom artist image
    await tester.pumpWidget(
      const MaterialApp(
        home: ArtistDetailScreen(artistName: 'Daft Punk'),
      ),
    );
    await tester.pump();

    // The artwork key should be the album art
    expect(
      find.byKey(const ValueKey('artist-header-album-alb-1')),
      findsOneWidget,
    );

    // Now update ArtistImageService with a custom image version
    ArtistImageService().setVersionsForTesting({'daft punk': 123456789});
    await tester.pump();

    // Now the custom artist image key should be rendered!
    expect(
      find.byKey(const ValueKey('artist-header-custom-Daft Punk-123456789')),
      findsOneWidget,
    );

    // Now remove custom artist image
    ArtistImageService().clear();
    await tester.pump();

    // Should fall back to album art again
    expect(
      find.byKey(const ValueKey('artist-header-album-alb-1')),
      findsOneWidget,
    );
  });
}
