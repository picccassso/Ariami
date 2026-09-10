import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/models/music_availability.dart';
import 'package:ariami_core/services/library/library_manager.dart';
import 'package:ariami_core/services/library/library_scanner_isolate.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory music;
  late LibraryManager manager;
  late File cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ariami_storage_');
    music = Directory('${temp.path}/music');
    cache = File('${temp.path}/metadata.json');
    manager = LibraryManager()..clear();
    manager.setCachePath(cache.path);
    manager.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
  });

  tearDown(() async {
    manager.clear();
    if (!Platform.isWindows)
      await Process.run('chmod', ['-R', 'u+rwx', temp.path]);
    await temp.delete(recursive: true);
  });

  Future<void> addSong([String name = 'track.mp3']) async {
    await music.create(recursive: true);
    await File('${music.path}/$name')
        .writeAsBytes(List.filled(4096, name.codeUnitAt(0)));
  }

  test('missing root is not a successful empty scanner result', () async {
    final result = await LibraryScannerIsolate.scan(music.path);
    expect(result.library, isNull);
  });

  test('boot before NAS is ready recovers without restarting Ariami', () async {
    await manager.scanMusicFolder(music.path);
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    expect(manager.isScanning, isFalse);
    expect(manager.library, isNull);

    await addSong();
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (manager.musicAvailability != MusicAvailability.ready &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(manager.musicAvailability, MusicAvailability.ready);
    expect(manager.library!.totalSongs, 1);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('empty first-use folder is explicit and recovers when populated',
      () async {
    await music.create();
    await manager.scanMusicFolder(music.path);
    expect(manager.musicAvailability, MusicAvailability.empty);
    await addSong();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.ready);
  });

  test('missing mount preserves cache and catalog across restart', () async {
    await addSong();
    await manager.scanMusicFolder(music.path);
    final token = manager.latestToken;
    final savedCache = await cache.readAsString();
    final detached = await music.rename('${temp.path}/detached');

    manager.clear(); // Process restart with persisted metadata/catalogue.
    manager.setCachePath(cache.path);
    await manager.scanMusicFolder(music.path);
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    expect(manager.latestToken, token);
    expect(await cache.readAsString(), savedCache);

    // A bare mount point can still exist while its NAS is absent.
    await music.create();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    expect(manager.latestToken, token);
    expect(await cache.readAsString(), savedCache);

    await music.delete();
    await detached.rename(music.path);
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.ready);
    expect(manager.library!.totalSongs, 1);
  });

  test('runtime disconnect preserves the in-memory catalogue too', () async {
    await addSong();
    await manager.scanMusicFolder(music.path);
    final token = manager.latestToken;
    await music.rename('${temp.path}/detached');
    await music.create();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    await manager.scanMusicFolder(music.path);
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    expect(manager.library!.totalSongs, 1);
    expect(manager.latestToken, token);
  });

  test('one removed sample does not mark accessible music unavailable',
      () async {
    await addSong('a.mp3');
    await addSong('b.mp3');
    await manager.scanMusicFolder(music.path);
    await File('${music.path}/a.mp3').delete();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.ready);
  });

  test('unreadable root preserves previous catalogue', () async {
    await addSong();
    await manager.scanMusicFolder(music.path);
    final token = manager.latestToken;
    await Process.run('chmod', ['000', music.path]);
    await manager.scanMusicFolder(music.path);
    expect(manager.musicAvailability, MusicAvailability.unavailable);
    expect(manager.library!.totalSongs, 1);
    expect(manager.latestToken, token);
  }, skip: Platform.isWindows);

  test('server stop pauses recovery and restart resumes it', () async {
    await manager.scanMusicFolder(music.path);
    manager.stopMusicAvailabilityMonitoring();
    await addSong();
    await manager.checkMusicAvailability();
    expect(manager.library, isNull);
    manager.resumeMusicAvailabilityMonitoring();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.ready);
  });

  test('clear cancels storage recovery', () async {
    await manager.scanMusicFolder(music.path);
    manager.clear();
    await addSong();
    await manager.checkMusicAvailability();
    expect(manager.musicAvailability, MusicAvailability.unknown);
    expect(manager.library, isNull);
  });

  test('old or unknown server health fields remain compatible', () {
    expect(MusicAvailability.fromJson(null), MusicAvailability.unknown);
    expect(MusicAvailability.fromJson({'status': 'future'}),
        MusicAvailability.unknown);
    expect(MusicAvailability.unknown.needsAttention, isFalse);
  });
}
