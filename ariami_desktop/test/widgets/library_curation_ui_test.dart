import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/library_curation_picker.dart';
import 'package:ariami_desktop/models/server_user_row.dart';
import 'package:ariami_desktop/utils/constants.dart';
import 'package:ariami_desktop/widgets/curation/artist_detail_pane.dart';
import 'package:ariami_desktop/widgets/curation/curation_rows.dart';
import 'package:ariami_desktop/widgets/curation/library_curation_picker_dialog.dart';
import 'package:ariami_desktop/widgets/server_users_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryCurationPickerDialog UI', () {
    Future<void> openPicker(
      WidgetTester tester, {
      required UserLibraryCuration curation,
      required List<CurationCatalogAlbum> albums,
      List<CurationCatalogPlaylist> playlists = const <CurationCatalogPlaylist>[],
      List<CurationCatalogSong> songs = const <CurationCatalogSong>[],
      List<CurationCatalogSong> standaloneSongs = const <CurationCatalogSong>[],
      CurationSaveCallback? onSave,
    }) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showLibraryCurationPickerDialog(
                      context,
                      title: 'Curate Library · alex',
                      loadBundle: () async => (
                        curation: curation,
                        albums: albums,
                        playlists: playlists,
                        standaloneSongs: standaloneSongs,
                      ),
                      loadAllSongs: songs.isNotEmpty ? () => songs : null,
                      onSave: onSave ??
                          (mode, rules) async =>
                              UserLibraryCuration.defaultForUser(
                                'alex',
                                mode: mode,
                                rules: rules,
                              ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'uses opaque popover surface, clips cleanly, and renders 4 tabs with artwork thumbnails',
      (tester) async {
        await openPicker(
          tester,
          curation: UserLibraryCuration.defaultForUser('alex'),
          albums: const <CurationCatalogAlbum>[
            CurationCatalogAlbum(
              id: 'alb-1',
              title: 'Album One',
              artist: '*NSYNC',
              songCount: 1,
            ),
          ],
          songs: const <CurationCatalogSong>[
            CurationCatalogSong(
              id: 's-1',
              title: 'Bye Bye Bye',
              artist: '*NSYNC',
              albumId: 'alb-1',
              albumTitle: 'Album One',
              trackNumber: 1,
            ),
          ],
        );

        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(dialog.backgroundColor, AppColors.popover);
        expect(dialog.backgroundColor!.a, 1.0);
        expect(dialog.clipBehavior, Clip.antiAlias);

        expect(find.text('Artists 1'), findsOneWidget);
        expect(find.text('Albums 1'), findsOneWidget);
        expect(find.text('Playlists 0'), findsOneWidget);
        expect(find.text('Songs 1'), findsOneWidget);

        expect(find.byType(CurationArtistArtwork), findsNWidgets(2));
        expect(find.byType(CurationAlbumArtwork), findsOneWidget);

        final selectedArtistRow = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('1 album · 1/1 included'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(selectedArtistRow.color, AppColors.surfaceHover);

        expect(find.text('*NSYNC'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'supports all 4 tabs and direct album, playlist, and song toggling',
      (tester) async {
        await openPicker(
          tester,
          curation: UserLibraryCuration.defaultForUser(
            'alex',
            mode: LibraryCurationMode.curated,
            onboardingCompleted: true,
          ),
          albums: const <CurationCatalogAlbum>[
            CurationCatalogAlbum(
              id: 'a1',
              title: 'Discovery',
              artist: 'Daft Punk',
              songCount: 2,
            ),
            CurationCatalogAlbum(
              id: 'a2',
              title: 'Homework',
              artist: 'Daft Punk',
              songCount: 1,
            ),
          ],
          playlists: const <CurationCatalogPlaylist>[
            CurationCatalogPlaylist(
              id: 'sp1',
              name: 'Late Night',
              songCount: 2,
            ),
          ],
          songs: const <CurationCatalogSong>[
            CurationCatalogSong(
              id: 's1',
              title: 'One More Time',
              artist: 'Daft Punk',
              albumId: 'a1',
              albumTitle: 'Discovery',
              trackNumber: 1,
            ),
            CurationCatalogSong(
              id: 's2',
              title: 'Aerodynamic',
              artist: 'Daft Punk',
              albumId: 'a1',
              albumTitle: 'Discovery',
              trackNumber: 2,
            ),
            CurationCatalogSong(
              id: 's3',
              title: 'Around the World',
              artist: 'Daft Punk',
              albumId: 'a2',
              albumTitle: 'Homework',
              trackNumber: 1,
            ),
          ],
        );

        expect(find.text('Artists 1'), findsOneWidget);
        expect(find.text('Albums 2'), findsOneWidget);
        expect(find.text('Playlists 1'), findsOneWidget);
        expect(find.text('Songs 3'), findsOneWidget);

        await tester.tap(find.text('Albums 2'));
        await tester.pumpAndSettle();

        expect(find.text('Discovery'), findsOneWidget);
        expect(find.text('Homework'), findsOneWidget);
        expect(find.byType(CurationAlbumArtwork), findsNWidgets(2));

        await tester.tap(find.text('Discovery'));
        await tester.pumpAndSettle();
        expect(find.text('0 artists · 1 albums · 0 playlists'), findsOneWidget);

        await tester.tap(find.text('Playlists 1'));
        await tester.pumpAndSettle();
        expect(find.text('Late Night'), findsOneWidget);
        expect(find.byType(CurationPlaylistArtwork), findsOneWidget);

        await tester.tap(find.text('Late Night'));
        await tester.pumpAndSettle();
        expect(find.text('0 artists · 1 albums · 1 playlists'), findsOneWidget);

        await tester.tap(find.text('Songs 3'));
        await tester.pumpAndSettle();
        expect(find.text('One More Time'), findsOneWidget);
        expect(find.byType(CurationSongArtwork), findsNWidgets(3));
      },
    );

    testWidgets('status filter pills and batch selection work cleanly',
        (tester) async {
      await openPicker(
        tester,
        curation: UserLibraryCuration.defaultForUser(
          'alex',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'alpha artist',
              action: CurationRuleAction.include,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
        albums: const <CurationCatalogAlbum>[
          CurationCatalogAlbum(
            id: 'a1',
            title: 'Alpha',
            artist: 'Alpha Artist',
            songCount: 1,
          ),
          CurationCatalogAlbum(
            id: 'a2',
            title: 'Beta',
            artist: 'Beta Artist',
            songCount: 1,
          ),
          CurationCatalogAlbum(
            id: 'a3',
            title: 'Gamma',
            artist: 'Alpha Two',
            songCount: 1,
          ),
        ],
        songs: const <CurationCatalogSong>[
          CurationCatalogSong(
            id: 's1',
            title: 'Alpha Song',
            artist: 'Alpha Artist',
            albumId: 'a1',
          ),
          CurationCatalogSong(
            id: 's2',
            title: 'Beta Song',
            artist: 'Beta Artist',
            albumId: 'a2',
          ),
          CurationCatalogSong(
            id: 's3',
            title: 'Gamma Song',
            artist: 'Alpha Two',
            albumId: 'a3',
          ),
        ],
      );

      await tester.tap(find.text('Selected'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Artist'), findsNWidgets(2));
      expect(find.text('Beta Artist'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();

      expect(find.text('Select 2'), findsOneWidget);
      await tester.tap(find.text('Select 2'));
      await tester.pumpAndSettle();

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
      await openPicker(
        tester,
        curation: UserLibraryCuration.defaultForUser(
          'alex',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
        ),
        albums: [
          for (var i = 0; i < letters.length; i++)
            CurationCatalogAlbum(
              id: 'a$i',
              title: 'Record $i',
              artist: letters[i],
              songCount: 1,
            ),
        ],
        songs: [
          for (var i = 0; i < letters.length; i++)
            CurationCatalogSong(
              id: 's$i',
              title: 'Track $i',
              artist: letters[i],
              albumId: 'a$i',
            ),
        ],
      );

      expect(find.text('Zebrahead'), findsNothing);
      final zFinder = find.text('Z').last;
      expect(zFinder, findsOneWidget);

      await tester.tap(zFinder);
      await tester.pumpAndSettle();

      expect(find.text('Zebrahead'), findsWidgets);
    });

    testWidgets('prompts on unsaved changes and saves via callback',
        (tester) async {
      LibraryCurationMode? savedMode;
      List<CurationRuleEntry>? savedRules;

      await openPicker(
        tester,
        curation: UserLibraryCuration.defaultForUser(
          'alex',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
        ),
        albums: const <CurationCatalogAlbum>[
          CurationCatalogAlbum(
            id: 'a1',
            title: 'Discovery',
            artist: 'Daft Punk',
            songCount: 1,
          ),
        ],
        songs: const <CurationCatalogSong>[
          CurationCatalogSong(
            id: 's1',
            title: 'One More Time',
            artist: 'Daft Punk',
            albumId: 'a1',
          ),
        ],
        onSave: (mode, rules) async {
          savedMode = mode;
          savedRules = rules;
          return UserLibraryCuration.defaultForUser(
            'alex',
            mode: mode,
            onboardingCompleted: true,
            rules: rules,
          );
        },
      );

      await tester.tap(find.text('Albums 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discovery'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Library'));
      await tester.pumpAndSettle();

      expect(savedMode, LibraryCurationMode.curated);
      expect(savedRules, isNotNull);
      expect(
        savedRules!.any(
          (r) => r.targetType == CurationTargetType.album && r.targetId == 'a1',
        ),
        isTrue,
      );
    });

    testWidgets(
      'resolves song artwork fallback for single-only artists and top-aligns detail pane',
      (tester) async {
        await openPicker(
          tester,
          curation: UserLibraryCuration.defaultForUser('alex'),
          albums: const <CurationCatalogAlbum>[],
          standaloneSongs: const <CurationCatalogSong>[
            CurationCatalogSong(
              id: 'single-1',
              title: 'Merry Christmas, Happy Holidays',
              artist: '*NSYNC',
            ),
          ],
        );

        final artistArtworks = tester
            .widgetList<CurationArtistArtwork>(
              find.byType(CurationArtistArtwork),
            )
            .toList();
        expect(artistArtworks, hasLength(2));
        for (final artwork in artistArtworks) {
          expect(artwork.fallbackSongId, 'single-1');
        }

        expect(find.byType(CurationSongArtwork), findsOneWidget);

        final listRect = tester.getRect(find.byType(CurationArtistTile).first);
        final detailHeaderRect = tester.getRect(
          find
              .descendant(
                of: find.byType(ArtistCurationDetailPane),
                matching: find.byType(CurationArtistArtwork),
              )
              .first,
        );
        expect(
          (detailHeaderRect.top - listRect.top).abs(),
          lessThan(40),
        );
      },
    );
  });

  group('ServerUsersTable curation UI', () {
    testWidgets('renders Library column and triggers Curate Library action',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ServerUserRow? curatedRow;
      final rows = [
        ServerUserRow(
          userId: 'u1',
          username: 'alex',
          createdAt: DateTime.utc(2026, 1, 1),
          isAdmin: true,
          connectedDeviceCount: 1,
          curationSummary:
              UserLibraryCuration.defaultForUser('u1').toSummaryJson(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ServerUsersTable(
              isLoading: false,
              errorMessage: null,
              rows: rows,
              ownerActionsEnabled: true,
              isChangingPassword: false,
              deletingUserIds: const <String>{},
              onCurateLibrary: (row) => curatedRow = row,
              onChangePassword: (_) {},
              onDeleteUser: (_) {},
              onSetUpOwner: () {},
            ),
          ),
        ),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Include Everything'), findsOneWidget);

      await tester.tap(find.byTooltip('User actions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Curate Library…'));
      await tester.pumpAndSettle();

      expect(curatedRow?.userId, 'u1');
    });
  });
}
