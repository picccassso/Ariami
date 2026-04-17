import 'package:ariami_mobile/models/playback_queue.dart';
import 'package:ariami_mobile/models/repeat_mode.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/audio/playback_state_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Song makeSong(String id) => Song(
        id: id,
        title: 'Song $id',
        artist: 'Artist',
        duration: const Duration(minutes: 3),
        filePath: id,
        fileSize: 123,
        modifiedTime: DateTime(2026, 1, 1),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('save/load complete playback state is isolated per user', () async {
    final manager = PlaybackStateManager();
    final queue = PlaybackQueue(songs: [makeSong('a')], currentIndex: 0);

    await manager.saveCompletePlaybackState(
      queue: queue,
      isShuffleEnabled: false,
      repeatMode: RepeatMode.none,
      position: const Duration(seconds: 42),
      userId: 'user-a',
    );

    final userAState =
        await manager.loadCompletePlaybackState(userId: 'user-a');
    final userBState =
        await manager.loadCompletePlaybackState(userId: 'user-b');

    expect(userAState, isNotNull);
    expect(userAState!.queue.currentSong?.id, 'a');
    expect(userAState.position, const Duration(seconds: 42));
    expect(userBState, isNull);
  });

  test('migrates legacy complete playback state into user scope once',
      () async {
    final manager = PlaybackStateManager();
    final queue = PlaybackQueue(songs: [makeSong('legacy')], currentIndex: 0);

    await manager.saveCompletePlaybackState(
      queue: queue,
      isShuffleEnabled: false,
      repeatMode: RepeatMode.all,
      position: const Duration(seconds: 7),
    );

    await manager.migrateLegacyCompletePlaybackStateToUser('user-legacy');

    final migrated =
        await manager.loadCompletePlaybackState(userId: 'user-legacy');
    final legacy = await manager.loadCompletePlaybackState();

    expect(migrated, isNotNull);
    expect(migrated!.queue.currentSong?.id, 'legacy');
    expect(migrated.repeatMode, RepeatMode.all);
    expect(legacy, isNull);
  });
}
