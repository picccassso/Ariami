import 'package:ariami_mobile/models/repeat_mode.dart' as playback_repeat;
import 'package:ariami_mobile/widgets/player/playback_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enables boundary skip buttons when repeat is active',
      (tester) async {
    await tester.pumpWidget(
      _buildControls(
        repeatMode: playback_repeat.RepeatMode.one,
        hasNext: false,
        hasPrevious: false,
      ),
    );

    expect(_buttonByIcon(Icons.skip_previous).onPressed, isNotNull);
    expect(_buttonByIcon(Icons.skip_next).onPressed, isNotNull);

    await tester.pumpWidget(
      _buildControls(
        repeatMode: playback_repeat.RepeatMode.all,
        hasNext: false,
        hasPrevious: false,
      ),
    );

    expect(_buttonByIcon(Icons.skip_previous).onPressed, isNotNull);
    expect(_buttonByIcon(Icons.skip_next).onPressed, isNotNull);
  });

  testWidgets('keeps boundary skip buttons disabled when repeat is off',
      (tester) async {
    await tester.pumpWidget(
      _buildControls(
        repeatMode: playback_repeat.RepeatMode.none,
        hasNext: false,
        hasPrevious: false,
      ),
    );

    expect(_buttonByIcon(Icons.skip_previous).onPressed, isNull);
    expect(_buttonByIcon(Icons.skip_next).onPressed, isNull);
  });
}

Widget _buildControls({
  required playback_repeat.RepeatMode repeatMode,
  required bool hasNext,
  required bool hasPrevious,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PlaybackControls(
        isPlaying: false,
        isLoading: false,
        isShuffleEnabled: false,
        repeatMode: repeatMode,
        hasNext: hasNext || repeatMode.allowsBoundaryRestart,
        hasPrevious: hasPrevious || repeatMode.allowsBoundaryRestart,
        onPlayPause: () {},
        onSkipNext: () {},
        onSkipPrevious: () {},
        onToggleShuffle: () {},
        onToggleRepeat: () {},
      ),
    ),
  );
}

IconButton _buttonByIcon(IconData icon) {
  return testerWidget<IconButton>(
    find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(IconButton),
    ),
  );
}

T testerWidget<T extends Widget>(Finder finder) {
  final element = finder.evaluate().single;
  return element.widget as T;
}
