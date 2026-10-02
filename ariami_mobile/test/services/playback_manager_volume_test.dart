import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/sqflite_mock.dart';

AriamiRemotePlayback _remote({
  String id = 'desktop-a',
  String type = 'desktop',
  double volume = 0.4,
  String? castDeviceName,
}) =>
    AriamiRemotePlayback(
      deviceId: id,
      deviceName: id,
      deviceType: type,
      snapshot: AriamiPlaybackSnapshot(
        queue: const [],
        currentIndex: -1,
        positionMs: 1000,
        durationMs: 10000,
        isPlaying: false,
        shuffle: false,
        repeatMode: 'off',
        volume: volume,
        castDeviceName: castDeviceName,
      ),
    );

Future<void> _castSession(WidgetTester tester, {double? volume}) async {
  // Construct the singleton so its inbound platform handler is installed.
  GoogleCastSessionManager.instance;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'google_cast.session_manager',
    const StandardMethodCodec().encodeMethodCall(MethodCall(
      'onCurrentSessionChanged',
      volume == null
          ? null
          : {
              'device': {
                'deviceID': 'speaker',
                'friendlyName': 'Speaker',
                'isOnLocalNetwork': true,
                'category': 'cast',
                'uniqueID': 'speaker',
              },
              'sessionID': 'session',
              'connectionState': GoogleCastConnectState.connected.index,
              'currentDeviceMuted': false,
              'currentDeviceVolume': volume,
            },
    )),
    (_) {},
  );
  await tester.pump();
}

void main() {
  installSqfliteTestMocks();
  final manager = PlaybackManager();
  late List<(String, Map<String, dynamic>?)> sent;

  void mirror(AriamiRemotePlayback remote, {bool supportsVolume = true}) {
    manager.setConnectRemoteMirror(
      remote,
      supportsVolume: supportsVolume,
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );
  }

  setUp(() {
    sent = [];
    manager.setConnectRemoteMirror(null);
  });
  tearDown(() => manager.setConnectRemoteMirror(null));

  testWidgets('only a capable desktop exposes artwork volume control',
      (tester) async {
    expect(manager.canControlOutputVolume, isFalse);
    expect(PlaybackManager.connectSupportedCommands,
        isNot(contains(AriamiConnectCommand.setVolume)));
    for (final type in ['mobile', 'tv', 'unknown', 'desktop']) {
      mirror(_remote(type: type), supportsVolume: type != 'desktop');
      expect(manager.canControlOutputVolume, isFalse);
      manager.setOutputVolume(0.8, outputId: 'invalid');
    }
    mirror(_remote());
    expect(manager.canControlOutputVolume, isTrue);
    expect(manager.outputVolume, 0.4);
    expect(manager.outputVolumeLabel, 'Desktop volume');
    expect(sent, isEmpty); // Joining must never write volume.
  });

  testWidgets('coalesces drag updates without postponing sends indefinitely',
      (tester) async {
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    manager.setOutputVolume(0.5, outputId: outputId);
    expect(manager.outputVolume, 0.5);
    expect(manager.isPlaying, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    manager.setOutputVolume(0.7, outputId: outputId);
    await tester.pump(const Duration(milliseconds: 49));
    expect(sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent.single.$1, AriamiConnectCommand.setVolume);
    expect(sent.single.$2, {'volume': 0.7});
    manager.setOutputVolume(0.8, outputId: outputId);
    await tester.pump(const Duration(milliseconds: 150));
    expect(sent.last.$1, AriamiConnectCommand.setVolume);
    expect(sent.last.$2, {'volume': 0.8});
    expect(sent.length, 2);
  });

  testWidgets('flushes the final value once and accepts authoritative state',
      (tester) async {
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    manager.setOutputVolume(0.6, outputId: outputId);
    manager.flushOutputVolume(outputId: outputId);
    expect(sent.single.$1, AriamiConnectCommand.setVolume);
    expect(sent.single.$2, {'volume': 0.6});
    await tester.pump(const Duration(milliseconds: 300));
    expect(sent.length, 1);
    mirror(_remote(volume: 0.35));
    expect(manager.outputVolume, 0.35);
  });

  testWidgets('clamps levels and rejects non-finite values', (tester) async {
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      manager.setOutputVolume(value, outputId: outputId);
    }
    await tester.pump(const Duration(milliseconds: 150));
    expect(sent, isEmpty);
    expect(manager.outputVolume, 0.4);
    manager.setOutputVolume(2, outputId: outputId);
    manager.flushOutputVolume(outputId: outputId);
    expect(sent.last.$2, {'volume': 1.0});
    manager.setOutputVolume(-1, outputId: outputId);
    manager.flushOutputVolume(outputId: outputId);
    expect(sent.last.$2, {'volume': 0.0});
    expect(manager.isPlaying, isFalse);
  });

  testWidgets('disconnect cancels queued volume and ignores stale gestures',
      (tester) async {
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    manager.setOutputVolume(0.8, outputId: outputId);
    manager.setConnectRemoteMirror(null);
    manager.setOutputVolume(0.9, outputId: outputId);
    manager.flushOutputVolume(outputId: outputId);
    await tester.pump(const Duration(milliseconds: 300));
    expect(sent, isEmpty);
    expect(manager.canControlOutputVolume, isFalse);
  });

  testWidgets('switching desktop, output, or capability cancels pending sends',
      (tester) async {
    for (final next in [
      _remote(id: 'desktop-b'),
      _remote(castDeviceName: 'Speaker'),
      _remote(type: 'tv'),
    ]) {
      mirror(_remote());
      final outputId = manager.volumeOutputId!;
      manager.setOutputVolume(0.8, outputId: outputId);
      mirror(next);
      manager.setOutputVolume(0.9, outputId: outputId);
      manager.flushOutputVolume(outputId: outputId);
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent, isEmpty);
    }
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    manager.setOutputVolume(0.8, outputId: outputId);
    mirror(_remote(), supportsVolume: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(sent, isEmpty);
    expect(manager.canControlOutputVolume, isFalse);
  });

  testWidgets(
      'broadcasts and optimistic edits preserve capability and pending value',
      (tester) async {
    mirror(_remote());
    final outputId = manager.volumeOutputId!;
    manager.setOutputVolume(0.7, outputId: outputId);
    manager.setConnectRemoteMirror(_remote(volume: 0.4));
    expect(manager.canControlOutputVolume, isTrue);
    expect(manager.outputVolume, 0.4);
    await tester.pump(const Duration(milliseconds: 150));
    expect(sent.single.$2, {'volume': 0.7});
  });

  testWidgets('desktop casting uses its receiver volume through Connect',
      (tester) async {
    mirror(_remote(volume: 0.25, castDeviceName: 'Speaker'));
    expect(manager.outputVolume, 0.25);
    expect(manager.outputVolumeLabel, 'Cast volume');
    manager.setOutputVolume(0.3, outputId: manager.volumeOutputId!);
    manager.flushOutputVolume(outputId: manager.volumeOutputId!);
    expect(sent.single.$1, AriamiConnectCommand.setVolume);
    expect(sent.single.$2, {'volume': 0.3});
  });

  testWidgets('direct mobile casting still uses the native receiver control',
      (tester) async {
    final nativeCalls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_cast.session_manager'),
      (call) async => nativeCalls.add(call),
    );
    await _castSession(tester, volume: 0.2);
    try {
      expect(manager.canControlOutputVolume, isTrue);
      expect(manager.outputVolume, 0.2);
      expect(manager.outputVolumeLabel, 'Cast volume');
      final castOutputId = manager.volumeOutputId!;
      manager.setOutputVolume(0.3, outputId: castOutputId);
      manager.flushOutputVolume(outputId: castOutputId);
      await tester.pump();
      expect(nativeCalls.single.method, 'setDeviceVolume');
      expect(nativeCalls.single.arguments, 0.3);
      expect(manager.outputVolume, 0.3);
      expect(sent, isEmpty);
      // Mirrored playback must take precedence over a leftover Cast session.
      mirror(_remote());
      manager.setOutputVolume(0.4, outputId: manager.volumeOutputId!);
      manager.flushOutputVolume(outputId: manager.volumeOutputId!);
      expect(sent.single.$2, {'volume': 0.4});
      expect(nativeCalls.length, 1);
      mirror(_remote(type: 'tv'));
      expect(manager.canControlOutputVolume, isFalse);
    } finally {
      await _castSession(tester);
      messenger.setMockMethodCallHandler(
        const MethodChannel('google_cast.session_manager'),
        null,
      );
    }
  });
}
