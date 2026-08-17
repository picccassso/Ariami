import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/widgets/player/player_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({String artist = 'Alice'}) => Song(
      id: 's1',
      title: 'T1',
      artist: artist,
      duration: const Duration(seconds: 180),
      filePath: 's1',
      fileSize: 0,
      modifiedTime: DateTime.now(),
    );

Widget _buildInfo({
  VoidCallback? onArtistTap,
  VoidCallback? onAlbumTap,
}) =>
    MaterialApp(
      home: Scaffold(
        body: PlayerInfo(
          song: _song(),
          isFavorite: false,
          onToggleFavorite: () {},
          onArtistTap: onArtistTap,
          onAlbumTap: onAlbumTap,
        ),
      ),
    );

void main() {
  testWidgets('tapping the song title fires onAlbumTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_buildInfo(onAlbumTap: () => taps++));

    await tester.tap(find.byKey(const ValueKey('title-s1-T1')), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('song title is plain text without onAlbumTap', (tester) async {
    await tester.pumpWidget(_buildInfo());

    expect(find.byKey(const ValueKey('title-s1-T1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('title-s1-T1')), warnIfMissed: false);
  });

  testWidgets('tapping the artist name fires onArtistTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_buildInfo(onArtistTap: () => taps++));

    await tester.tap(find.byKey(const ValueKey('artist-s1-Alice')), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('artist name is plain text without onArtistTap', (tester) async {
    await tester.pumpWidget(_buildInfo());

    // The marquee is still rendered; a tap simply does not throw or navigate.
    expect(find.byKey(const ValueKey('artist-s1-Alice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artist-s1-Alice')), warnIfMissed: false);
  });
}
