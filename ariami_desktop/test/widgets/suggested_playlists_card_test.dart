import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_desktop/widgets/dashboard/suggested_playlists_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gym = PlaylistSuggestion(
    folderPath: '/music/Gym Mix',
    name: 'Gym Mix',
    songCount: 24,
    artistCount: 12,
    albumCount: 9,
  );
  const untagged = PlaylistSuggestion(
    folderPath: '/music/Road Trip',
    name: 'Road Trip',
    songCount: 10,
    artistCount: 0,
    albumCount: 0,
    missingTags: true,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<PlaylistSuggestion> suggestions,
    Set<String> deciding = const {},
    void Function(PlaylistSuggestion)? onImport,
    void Function(PlaylistSuggestion)? onIgnore,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SuggestedPlaylistsCard(
              suggestions: suggestions,
              decidingFolderPaths: deciding,
              onImport: onImport ?? (_) {},
              onIgnore: onIgnore ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when there are no suggestions', (tester) async {
    await pumpCard(tester, suggestions: const []);

    expect(find.text('Suggested Playlists'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('lists suggestions with counts and a tags-missing badge',
      (tester) async {
    await pumpCard(tester, suggestions: const [gym, untagged]);

    expect(find.text('Suggested Playlists'), findsOneWidget);
    expect(find.text('Gym Mix'), findsOneWidget);
    expect(find.text('24 songs · 12 artists · 9 albums'), findsOneWidget);
    expect(find.text('Tags missing — review before importing'), findsOneWidget);
  });

  testWidgets('Import and Ignore report the tapped suggestion', (tester) async {
    PlaylistSuggestion? imported;
    PlaylistSuggestion? ignored;
    await pumpCard(
      tester,
      suggestions: const [gym, untagged],
      onImport: (s) => imported = s,
      onIgnore: (s) => ignored = s,
    );

    await tester.tap(find.text('Import').first);
    await tester.tap(find.text('Ignore').last);

    expect(imported, gym);
    expect(ignored, untagged);
  });

  testWidgets('a row being decided shows a spinner instead of buttons',
      (tester) async {
    await pumpCard(
      tester,
      suggestions: const [gym, untagged],
      deciding: {gym.folderPath},
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
  });
}
