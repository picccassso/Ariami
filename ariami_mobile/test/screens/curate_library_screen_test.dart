import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/curation/curate_library_screen.dart';
import 'package:ariami_mobile/screens/main/library/library_controller.dart';
import 'package:ariami_mobile/services/artist_image_service.dart';
import 'package:ariami_mobile/services/curation/library_curation_service.dart';
import 'package:ariami_mobile/utils/constants.dart';
import 'package:ariami_mobile/widgets/common/cached_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    installSqfliteTestMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async => '/tmp');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDownAll(() {
    uninstallSqfliteTestMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  tearDown(() {
    LibraryCurationService().saveHandlerForTest = null;
    ArtistImageService().clear();
  });

  AlbumModel makeAlbum(
    String id,
    String title,
    String artist, {
    int songCount = 2,
    String? coverArt,
  }) =>
      AlbumModel(
        id: id,
        title: title,
        artist: artist,
        coverArt: coverArt,
        songCount: songCount,
        duration: 360,
      );

  SongModel makeSong(
    String id,
    String title,
    String artist, {
    String? albumId,
    int? trackNumber,
  }) =>
      SongModel(
        id: id,
        title: title,
        artist: artist,
        albumId: albumId,
        trackNumber: trackNumber,
        duration: 180,
      );

  void seedCatalog({
    required List<AlbumModel> albums,
    required List<SongModel> songs,
    List<ServerPlaylist> playlists = const <ServerPlaylist>[],
    LibraryCurationMode mode = LibraryCurationMode.curated,
    List<CurationRuleEntry> rules = const <CurationRuleEntry>[],
  }) {
    LibraryCurationService().setCurationForTest(
      UserLibraryCuration.defaultForUser(
        'u1',
        mode: mode,
        onboardingCompleted: true,
        rules: rules,
      ),
    );
    LibraryController().setRawCatalogForTest(
      albums: albums,
      songs: songs,
      serverPlaylists: playlists,
    );
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpCurateScreen(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildNeutralTheme(brightness: Brightness.dark),
        home: const CurateLibraryScreen(),
      ),
    );
    await pumpFrames(tester);
  }

  group('CurateLibraryScreen', () {
    testWidgets('switches mode via compact pill and bottom sheet',
        (tester) async {
      seedCatalog(
        albums: [makeAlbum('a1', 'Discovery', 'Daft Punk')],
        songs: [
          makeSong('s1', 'One More Time', 'Daft Punk', albumId: 'a1'),
        ],
        mode: LibraryCurationMode.curated,
      );

      await pumpCurateScreen(tester);

      expect(find.text('Curated'), findsOneWidget);
      await tester.tap(find.text('Curated'));
      await pumpFrames(tester);

      expect(find.text('Library Mode'), findsOneWidget);
      await tester.tap(find.text('Include Everything'));
      await pumpFrames(tester);

      expect(find.text('Include All'), findsOneWidget);
      expect(
        find.text('Include Everything · Full server catalog'),
        findsOneWidget,
      );
    });

    testWidgets('supports all 4 tabs and direct album toggling',
        (tester) async {
      seedCatalog(
        albums: [
          makeAlbum('a1', 'Discovery', 'Daft Punk'),
          makeAlbum('a2', 'Homework', 'Daft Punk'),
        ],
        songs: [
          makeSong('s1', 'One More Time', 'Daft Punk',
              albumId: 'a1', trackNumber: 1),
          makeSong('s2', 'Aerodynamic', 'Daft Punk',
              albumId: 'a1', trackNumber: 2),
          makeSong('s3', 'Around the World', 'Daft Punk',
              albumId: 'a2', trackNumber: 1),
        ],
        playlists: [
          ServerPlaylist(
            id: 'sp1',
            name: 'Late Night',
            songIds: const ['s1', 's3'],
            songCount: 2,
          ),
        ],
        mode: LibraryCurationMode.curated,
      );

      await pumpCurateScreen(tester);

      expect(find.text('Artists 1'), findsOneWidget);
      expect(find.text('Albums 2'), findsOneWidget);
      expect(find.text('Playlists 1'), findsOneWidget);
      expect(find.text('Songs 3'), findsOneWidget);

      await tester.tap(find.text('Albums 2'));
      await pumpFrames(tester);

      expect(find.text('Discovery'), findsOneWidget);
      expect(find.text('Homework'), findsOneWidget);

      await tester.tap(find.text('Discovery'));
      await pumpFrames(tester);
      expect(find.text('0 artists · 1 albums · 0 playlists'), findsOneWidget);

      await tester.tap(find.text('Playlists 1'));
      await pumpFrames(tester);
      expect(find.text('Late Night'), findsOneWidget);
      await tester.tap(find.text('Late Night'));
      await pumpFrames(tester);
      expect(find.text('0 artists · 1 albums · 1 playlists'), findsOneWidget);

      await tester.tap(find.text('Songs 3'));
      await pumpFrames(tester);
      expect(find.text('One More Time'), findsOneWidget);
    });

    testWidgets('status filter pills and batch selection work cleanly',
        (tester) async {
      seedCatalog(
        albums: [
          makeAlbum('a1', 'Alpha', 'Alpha Artist'),
          makeAlbum('a2', 'Beta', 'Beta Artist'),
          makeAlbum('a3', 'Gamma', 'Alpha Two'),
        ],
        songs: [
          makeSong('s1', 'Alpha Song', 'Alpha Artist', albumId: 'a1'),
          makeSong('s2', 'Beta Song', 'Beta Artist', albumId: 'a2'),
          makeSong('s3', 'Gamma Song', 'Alpha Two', albumId: 'a3'),
        ],
        mode: LibraryCurationMode.curated,
        rules: [
          CurationRuleEntry(
            targetType: CurationTargetType.artist,
            targetId: 'alpha artist',
            action: CurationRuleAction.include,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      await pumpCurateScreen(tester);

      // Selected filter shows only already-selected Alpha Artist.
      await tester.tap(find.text('Selected'));
      await pumpFrames(tester);
      expect(find.text('Alpha Artist'), findsOneWidget);
      expect(find.text('Beta Artist'), findsNothing);

      // Switch back to All, search "Alpha", and batch-select remaining match
      // without flipping already-selected Alpha Artist off.
      await tester.tap(find.text('All'));
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField), 'Alpha');
      await pumpFrames(tester);

      expect(find.text('Select 2'), findsOneWidget);
      await tester.tap(find.text('Select 2'));
      await pumpFrames(tester);

      expect(find.text('2 artists · 2 albums · 0 playlists'), findsOneWidget);
      expect(find.text('Deselect 2'), findsOneWidget);
    });

    testWidgets('shows A-Z scrubber on large lists and jumps when tapped',
        (tester) async {
      final letters = [
        'Aardvark',
        'Bowie',
        'Coldplay',
        'Daft Punk',
        'Eagles',
        'Fleetwood Mac',
        'Gorillaz',
        'Hozier',
        'Interpol',
        'Justice',
        'Kendrick',
        'LCD Soundsystem',
        'Metallica',
        'Zebrahead',
      ];
      seedCatalog(
        albums: [
          for (var i = 0; i < letters.length; i++)
            makeAlbum('a$i', 'Record $i', letters[i]),
        ],
        songs: [
          for (var i = 0; i < letters.length; i++)
            makeSong('s$i', 'Track $i', letters[i], albumId: 'a$i'),
        ],
        mode: LibraryCurationMode.curated,
      );

      await pumpCurateScreen(tester);

      // Verify Z is in the rail and Zebrahead is initially off-screen.
      expect(find.text('Zebrahead'), findsNothing);
      final zFinder = find.text('Z').last;
      expect(zFinder, findsOneWidget);

      await tester.tap(zFinder);
      await pumpFrames(tester);

      expect(find.text('Zebrahead'), findsOneWidget);
    });

    testWidgets('prompts on unsaved changes and saves via service',
        (tester) async {
      LibraryCurationMode? savedMode;
      List<CurationRuleEntry>? savedRules;
      LibraryCurationService().saveHandlerForTest =
          (mode, rules, onboardingCompleted) async {
        savedMode = mode;
        savedRules = rules;
        return UserLibraryCuration.defaultForUser(
          'u1',
          mode: mode,
          onboardingCompleted: onboardingCompleted,
          rules: rules,
        );
      };

      seedCatalog(
        albums: [makeAlbum('a1', 'Discovery', 'Daft Punk')],
        songs: [makeSong('s1', 'One More Time', 'Daft Punk', albumId: 'a1')],
        mode: LibraryCurationMode.curated,
      );

      await pumpCurateScreen(tester);

      await tester.tap(find.text('Albums 1'));
      await pumpFrames(tester);
      await tester.tap(find.text('Discovery'));
      await pumpFrames(tester);

      // Tapping Back prompts discard confirmation.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await pumpFrames(tester);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await pumpFrames(tester);

      // Saving persists updated rules.
      await tester.tap(find.text('Save Library'));
      await pumpFrames(tester);

      expect(savedMode, LibraryCurationMode.curated);
      expect(savedRules, isNotNull);
      expect(
        savedRules!.any(
          (r) =>
              r.targetType == CurationTargetType.album && r.targetId == 'a1',
        ),
        isTrue,
      );
    });

    testWidgets(
        'resolves artist thumbnails from album coverArt, credited songs, and standalone singles',
        (tester) async {
      seedCatalog(
        albums: [
          // First album alphabetically for Daft Punk has no coverArt; second has it.
          makeAlbum('a1', 'Alive 1997', 'Daft Punk'),
          makeAlbum(
            'a2',
            'Discovery',
            'Daft Punk',
            coverArt: '/api/artwork/a2',
          ),
          // Compilation album whose primary artist is Various Artists.
          makeAlbum(
            'a_comp',
            'Club Hits',
            'Various Artists',
            coverArt: '/api/artwork/a_comp',
          ),
        ],
        songs: [
          makeSong('s1', 'One More Time', 'Daft Punk', albumId: 'a2'),
          // Kavinsky has a standalone single and is also credited on a compilation with art.
          makeSong('s_kav_solo', 'Testarossa', 'Kavinsky'),
          makeSong(
            's_feat',
            'Nightcall',
            'Kavinsky',
            albumId: 'a_comp',
          ),
          // Standalone single with no album.
          makeSong('s_solo', 'Midnight', 'Solo Artist'),
        ],
        mode: LibraryCurationMode.curated,
      );

      await pumpCurateScreen(tester);

      final daftPunkArt = tester.widget<CachedArtwork>(
        find.byKey(const ValueKey('curation-artist-album-a2')),
      );
      expect(daftPunkArt.albumId, 'a2');
      expect(daftPunkArt.artworkUrl, '/api/artwork/a2');

      // Various Artists + Kavinsky both resolve to a_comp.
      final compArts = tester.widgetList<CachedArtwork>(
        find.byKey(const ValueKey('curation-artist-album-a_comp')),
      );
      expect(compArts.length, 2);
      expect(compArts.first.artworkUrl, '/api/artwork/a_comp');

      final soloArt = tester.widget<CachedArtwork>(
        find.byKey(const ValueKey('curation-artist-song-s_solo')),
      );
      expect(soloArt.albumId, 'song_s_solo');
      expect(soloArt.artworkUrl, '/api/song-artwork/s_solo');
    });
  });
}
