import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/playlist/widgets/playlist_info_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistInfoSection', () {
    testWidgets('should display playlist name', (tester) async {
      final playlist = PlaylistModel(
        id: 'test-id',
        name: 'Test Playlist',
        songIds: [],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistInfoSection(
              playlist: playlist,
              songs: [],
            ),
          ),
        ),
      );

      expect(find.text('Test Playlist'), findsOneWidget);
    });

    testWidgets('should display song count and duration', (tester) async {
      final playlist = PlaylistModel(
        id: 'test-id',
        name: 'Test Playlist',
        songIds: ['1', '2', '3'],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final songs = [
        SongModel(id: '1', title: 'Song 1', artist: 'Artist 1', duration: 180),
        SongModel(id: '2', title: 'Song 2', artist: 'Artist 2', duration: 240),
        SongModel(id: '3', title: 'Song 3', artist: 'Artist 3', duration: 120),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistInfoSection(
              playlist: playlist,
              songs: songs,
            ),
          ),
        ),
      );

      // Total duration: 540 seconds = 9 minutes
      expect(find.text('3 songs • 9 min'), findsOneWidget);
    });

    testWidgets('should display description when provided', (tester) async {
      final playlist = PlaylistModel(
        id: 'test-id',
        name: 'Test Playlist',
        description: 'My favorite songs',
        songIds: [],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistInfoSection(
              playlist: playlist,
              songs: [],
            ),
          ),
        ),
      );

      expect(find.text('My favorite songs'), findsOneWidget);
    });

    testWidgets('should handle single song correctly', (tester) async {
      final playlist = PlaylistModel(
        id: 'test-id',
        name: 'Test Playlist',
        songIds: ['1'],
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      final songs = [
        SongModel(id: '1', title: 'Song 1', artist: 'Artist 1', duration: 180),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistInfoSection(
              playlist: playlist,
              songs: songs,
            ),
          ),
        ),
      );

      // Should say "1 song" not "1 songs"
      expect(find.text('1 song • 3 min'), findsOneWidget);
    });
  });
}
