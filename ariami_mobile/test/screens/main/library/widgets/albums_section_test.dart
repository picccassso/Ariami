import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:ariami_mobile/screens/main/library/widgets/albums_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlbumsSection', () {
    final testAlbums = [
      AlbumModel(
        id: 'album-1',
        title: 'Test Album 1',
        artist: 'Test Artist 1',
        songCount: 10,
        duration: 3600,
      ),
      AlbumModel(
        id: 'album-2',
        title: 'Test Album 2',
        artist: 'Test Artist 2',
        songCount: 8,
        duration: 2800,
      ),
    ];

    Widget buildTestWidget({
      required LibraryState state,
      bool isOffline = false,
      VoidCallback? onAlbumTap,
      VoidCallback? onAlbumLongPress,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              AlbumsSection(
                state: state,
                isOffline: isOffline,
                onAlbumTap: (album) => onAlbumTap?.call(),
                onAlbumLongPress: (album) => onAlbumLongPress?.call(),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('should display albums in grid view', (tester) async {
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('Test Album 1'), findsOneWidget);
      expect(find.text('Test Album 2'), findsOneWidget);
    });

    testWidgets('should display empty message when no albums', (tester) async {
      final state = const LibraryState(
        albums: [],
        isGridView: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('No albums found'), findsOneWidget);
    });

    testWidgets('should display downloaded only message when filtering',
        (tester) async {
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
        showDownloadedOnly: true,
        albumsWithDownloads: {},
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('No albums with downloaded songs'), findsOneWidget);
    });

    testWidgets('should filter albums by downloads', (tester) async {
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
        showDownloadedOnly: true,
        albumsWithDownloads: {'album-1'},
      );

      await tester.pumpWidget(buildTestWidget(state: state));
      await tester.pumpAndSettle();

      expect(find.text('Test Album 1'), findsOneWidget);
      expect(find.text('Test Album 2'), findsNothing);
    });

    testWidgets('should call onAlbumTap when album tapped', (tester) async {
      var tapped = false;
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        onAlbumTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Album 1'));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('should call onAlbumLongPress when album long pressed',
        (tester) async {
      var longPressed = false;
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        onAlbumLongPress: () => longPressed = true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Test Album 1'));
      await tester.pump();

      expect(longPressed, true);
    });

    testWidgets('should disable tap when offline and no downloads',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isOffline: true,
        onAlbumTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      // Should not trigger tap when offline and no downloads
      await tester.tap(find.text('Test Album 1'));
      await tester.pump();

      expect(tapped, false);
    });

    testWidgets('should enable tap when offline but has downloads',
        (tester) async {
      var tapped = false;
      final state = LibraryState(
        albums: testAlbums,
        isGridView: true,
        isLoading: false,
        albumsWithDownloads: {'album-1'},
      );

      await tester.pumpWidget(buildTestWidget(
        state: state,
        isOffline: true,
        onAlbumTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Album 1'));
      await tester.pump();

      expect(tapped, true);
    });
  });
}
