import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/search_screen.dart';
import 'package:ariami_mobile/services/curation/library_curation_service.dart';
import 'package:ariami_mobile/services/library/library_genre_index.dart';
import 'package:ariami_mobile/services/library/library_read_facade.dart';
import 'package:ariami_mobile/services/settings/search_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  final searchSettings = SearchSettingsService();
  final curationService = LibraryCurationService();

  final testBundle = LibraryReadBundle(
    albums: [
      AlbumModel(
        id: 'alb-1',
        title: 'Discovery',
        artist: 'Daft Punk',
        songCount: 1,
        duration: 320,
      ),
      AlbumModel(
        id: 'alb-2',
        title: 'Random Access Memories',
        artist: 'Justice',
        songCount: 1,
        duration: 240,
      ),
    ],
    songs: [
      SongModel(
        id: 'song-1',
        title: 'One More Time',
        artist: 'Daft Punk',
        albumId: 'alb-1',
        duration: 320,
      ),
      SongModel(
        id: 'song-2',
        title: 'One Night Stand',
        artist: 'Justice',
        albumId: 'alb-2',
        duration: 240,
      ),
    ],
    serverPlaylists: const <ServerPlaylist>[],
    genreIndex: LibraryGenreIndex.empty,
    durationsReady: true,
    source: LibraryReadSource.v2LocalStore,
    sourceReason: 'test',
  );

  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
    searchSettings.resetForTesting();
    curationService.setCurationForTest(
      UserLibraryCuration.defaultForUser(
        'u1',
        mode: LibraryCurationMode.full,
        onboardingCompleted: true,
      ),
    );
  });

  tearDown(() {
    curationService.setCurationForTest(
      UserLibraryCuration.defaultForUser(
        'u1',
        mode: LibraryCurationMode.full,
        onboardingCompleted: true,
      ),
    );
  });

  Future<void> pumpSearchScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          focusOnOpen: false,
          libraryBundleLoaderForTest: () async => testBundle,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'hides Search full server catalog toggle in full library mode',
    (tester) async {
      await pumpSearchScreen(tester);

      expect(find.text('Search full server catalog'), findsNothing);

      await tester.enterText(find.byType(TextField), 'One');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Search full server catalog'), findsNothing);
      expect(find.text('One More Time'), findsOneWidget);
      expect(find.text('One Night Stand'), findsOneWidget);
    },
  );

  testWidgets(
    'shows Search full server catalog toggle only while searching in curated mode',
    (tester) async {
      curationService.setCurationForTest(
        UserLibraryCuration.defaultForUser(
          'u1',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'daft punk',
              action: CurationRuleAction.include,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      await pumpSearchScreen(tester);

      // Hidden while search query is empty.
      expect(find.text('Search full server catalog'), findsNothing);

      await tester.enterText(find.byType(TextField), 'One');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Search full server catalog'), findsOneWidget);
      expect(find.text('One More Time'), findsOneWidget);
      expect(find.text('One Night Stand'), findsNothing);

      await tester.tap(find.text('Search full server catalog'));
      await tester.pump();

      expect(find.text('One Night Stand'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Add'), findsOneWidget);

      // Clearing search hides the toggle again.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Search full server catalog'), findsNothing);
    },
  );

  testWidgets(
    'shows toggle in full mode with exclusions and resets when switching to pass-through',
    (tester) async {
      curationService.setCurationForTest(
        UserLibraryCuration.defaultForUser(
          'u1',
          mode: LibraryCurationMode.full,
          onboardingCompleted: true,
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.song,
              targetId: 'song-2',
              action: CurationRuleAction.exclude,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      await pumpSearchScreen(tester);
      await tester.enterText(find.byType(TextField), 'One');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Search full server catalog'), findsOneWidget);
      expect(find.text('One Night Stand'), findsNothing);

      await tester.tap(find.text('Search full server catalog'));
      await tester.pump();
      expect(find.text('One Night Stand'), findsOneWidget);

      // Switching to unrestricted full mode hides toggle and resets its state.
      curationService.setCurationForTest(
        UserLibraryCuration.defaultForUser(
          'u1',
          mode: LibraryCurationMode.full,
          onboardingCompleted: true,
        ),
      );
      await tester.pump();
      expect(find.text('Search full server catalog'), findsNothing);

      // Switching back to curated mode starts with full-catalog toggle unselected.
      curationService.setCurationForTest(
        UserLibraryCuration.defaultForUser(
          'u1',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'daft punk',
              action: CurationRuleAction.include,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await tester.pump();

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Search full server catalog'),
      );
      expect(chip.selected, isFalse);
      expect(find.text('One Night Stand'), findsNothing);
    },
  );
}
