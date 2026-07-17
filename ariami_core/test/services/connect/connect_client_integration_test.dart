import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_client.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

/// End-to-end test of the client transport against the real hub over real
/// websockets: an inactive controller must observe every state change the
/// active device publishes after running a routed command.
void main() {
  late HttpServer server;
  late AriamiConnectHub hub;
  final clients = <AriamiConnectClient>[];

  setUp(() async {
    hub = AriamiConnectHub(
      disconnectGracePeriod: const Duration(milliseconds: 50),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final channel = IOWebSocketChannel(socket);
      channel.stream.listen(
        (raw) {
          final message = WsMessage.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
          if (message.type == WsMessageType.identify) {
            final data = message.data ?? const <String, dynamic>{};
            hub.register(
              channel,
              userId: 'user',
              deviceId: data['deviceId'] as String? ?? '',
              deviceName: data['deviceName'] as String? ?? '',
              clientType: data['clientType'] as String? ?? '',
            );
          } else {
            hub.handle(channel, message);
          }
        },
        onDone: () => hub.unregister(channel),
      );
    });
  });

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    await server.close(force: true);
  });

  Future<void> pump([int rounds = 40]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('Condition not reached; hub/client message flow is broken.');
  }

  test('controller sees the new track after the active device runs its command',
      () async {
    // The "TV": owns a two-track queue and applies commands locally.
    var tvIndex = 0;
    var tvPlaying = true;
    var tvQueue = <Map<String, dynamic>>[
      {'id': 'song-a', 'title': 'A'},
      {'id': 'song-b', 'title': 'B'},
    ];
    AriamiPlaybackSnapshot tvSnapshot() => AriamiPlaybackSnapshot(
          queue: tvQueue,
          currentIndex: tvIndex,
          positionMs: 1000,
          durationMs: 60000,
          isPlaying: tvPlaying,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        );
    final tv = AriamiConnectClient(
      deviceId: 'tv',
      deviceName: 'Ariami TV',
      clientType: 'tv',
      snapshotProvider: tvSnapshot,
      applySnapshot: (_) async {},
      handleCommand: (command, arguments) async {
        if (command == AriamiConnectCommand.next) tvIndex = 1;
        if (command == AriamiConnectCommand.pause) tvPlaying = false;
        if (command == AriamiConnectCommand.playQueueIndex) {
          tvIndex = (arguments['index'] as num).toInt();
        }
        if (command == AriamiConnectCommand.playContext) {
          final snapshot = AriamiPlaybackSnapshot.fromJson(
            Map<String, dynamic>.from(arguments['snapshot'] as Map),
          );
          tvQueue = snapshot.queue;
          tvIndex = snapshot.currentIndex;
          tvPlaying = snapshot.isPlaying;
        }
      },
      pauseForTransfer: () async {},
    );
    clients.add(tv);

    // The "laptop": empty local queue, purely a controller here.
    final laptop = AriamiConnectClient(
      deviceId: 'laptop',
      deviceName: 'Laptop',
      clientType: 'desktop',
      snapshotProvider: () => AriamiPlaybackSnapshot.fromJson(const {}),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    clients.add(laptop);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await tv.connect(baseUrl: baseUrl);
    await laptop.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected && laptop.isConnected);

    // TV starts playing and becomes the active device.
    tv.publishState(activate: true);
    await waitFor(() =>
        laptop.activeDeviceId == 'tv' &&
        laptop.remoteSnapshot?.currentTrackId == 'song-a');

    // Laptop skips; the TV runs the command and publishes; the laptop's view
    // of the remote session must advance to the new track.
    laptop.sendCommand(AriamiConnectCommand.next);
    await waitFor(() => laptop.remoteSnapshot?.currentTrackId == 'song-b');

    // Same for jumping to an explicit queue index (queue tap).
    laptop.sendCommand(
        AriamiConnectCommand.playQueueIndex, <String, dynamic>{'index': 0});
    await waitFor(() => laptop.remoteSnapshot?.currentTrackId == 'song-a');

    // And a state change with no track change (pause).
    laptop.sendCommand(AriamiConnectCommand.pause);
    await waitFor(() => laptop.remoteSnapshot?.isPlaying == false);

    // Browsing on the laptop starts a whole new queue on the TV.
    laptop.sendCommand(AriamiConnectCommand.playContext, <String, dynamic>{
      'snapshot': AriamiPlaybackSnapshot(
        queue: [
          {'id': 'song-c', 'title': 'C'},
        ],
        currentIndex: 0,
        positionMs: 0,
        durationMs: 60000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ).toJson(),
    });
    await waitFor(() =>
        laptop.remoteSnapshot?.currentTrackId == 'song-c' &&
        laptop.remoteSnapshot?.isPlaying == true);
  });

  test('explicit refresh reloads authoritative playback without taking over',
      () async {
    var tvTrackId = 'song-a';
    AriamiPlaybackSnapshot tvSnapshot() => AriamiPlaybackSnapshot(
          queue: <Map<String, dynamic>>[
            <String, dynamic>{'id': tvTrackId, 'title': tvTrackId},
          ],
          currentIndex: 0,
          positionMs: 1000,
          durationMs: 60000,
          isPlaying: true,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        );
    final tv = AriamiConnectClient(
      deviceId: 'refresh-tv',
      deviceName: 'TV',
      clientType: 'tv',
      snapshotProvider: tvSnapshot,
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    final phone = AriamiConnectClient(
      deviceId: 'refresh-phone',
      deviceName: 'Phone',
      clientType: 'mobile',
      snapshotProvider: () => AriamiPlaybackSnapshot.fromJson(const {}),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    clients
      ..add(tv)
      ..add(phone);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await tv.connect(baseUrl: baseUrl);
    await phone.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected && phone.isConnected);
    tv.publishState(activate: true);
    await waitFor(() =>
        phone.activeDeviceId == 'refresh-tv' &&
        phone.remoteSnapshot?.currentTrackId == 'song-a');

    // Model a state push missed while the phone process was suspended. First
    // let the hub advance to song-b, then restore the phone's last-seen song-a
    // snapshot so only an authoritative refresh can repair it.
    tvTrackId = 'song-b';
    tv.publishState();
    await waitFor(() => phone.remoteSnapshot?.currentTrackId == 'song-b');
    phone.remoteSnapshot = AriamiPlaybackSnapshot(
      queue: const <Map<String, dynamic>>[
        <String, dynamic>{'id': 'song-a', 'title': 'song-a'},
      ],
      currentIndex: 0,
      positionMs: 1000,
      durationMs: 60000,
      isPlaying: true,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );

    await phone.refreshState();
    await waitFor(() =>
        phone.isConnected &&
        phone.activeDeviceId == 'refresh-tv' &&
        phone.remoteSnapshot?.currentTrackId == 'song-b');
    expect(phone.isThisDeviceActive, isFalse);
  });

  test('local play before welcome takes ownership without a stale overlay',
      () async {
    var desktopPlaying = true;
    final desktop = AriamiConnectClient(
      deviceId: 'startup-desktop',
      deviceName: 'Desktop',
      clientType: 'desktop',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: const [
          {'id': 'desktop-song', 'title': 'Desktop song'},
        ],
        currentIndex: 0,
        positionMs: 12000,
        durationMs: 60000,
        isPlaying: desktopPlaying,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (_) async {},
      handleCommand: (command, _) async {
        if (command == AriamiConnectCommand.pause) desktopPlaying = false;
      },
      pauseForTransfer: () async => desktopPlaying = false,
    );
    final phone = AriamiConnectClient(
      deviceId: 'startup-phone',
      deviceName: 'Phone',
      clientType: 'mobile',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: const [
          {'id': 'phone-song', 'title': 'Phone song'},
        ],
        currentIndex: 0,
        positionMs: 0,
        durationMs: 60000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    clients
      ..add(desktop)
      ..add(phone);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await desktop.connect(baseUrl: baseUrl);
    await waitFor(() => desktop.isConnected);
    desktop.publishState(activate: true);
    await waitFor(() => desktop.isThisDeviceActive);

    // Models tapping the restored phone track before its Connect socket has
    // opened and received the desktop's authoritative welcome snapshot.
    phone.requestLocalTakeover();
    expect(phone.hasPendingLocalTakeover, isTrue);
    await phone.connect(baseUrl: baseUrl);

    await waitFor(() =>
        phone.isThisDeviceActive &&
        desktop.remoteSnapshot?.currentTrackId == 'phone-song' &&
        !desktopPlaying);
    expect(phone.hasPendingLocalTakeover, isFalse);
  });

  test('commands queued while disconnected flush once after welcome', () async {
    var pauseExecutions = 0;
    var tvPlaying = true;
    AriamiPlaybackSnapshot tvSnapshot() => AriamiPlaybackSnapshot(
          queue: const <Map<String, dynamic>>[
            <String, dynamic>{'id': 'song-a', 'title': 'A'},
          ],
          currentIndex: 0,
          positionMs: 1000,
          durationMs: 60000,
          isPlaying: tvPlaying,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        );
    final tv = AriamiConnectClient(
      deviceId: 'queued-tv',
      deviceName: 'Queued TV',
      clientType: 'tv',
      snapshotProvider: tvSnapshot,
      applySnapshot: (_) async {},
      handleCommand: (command, _) async {
        if (command == AriamiConnectCommand.pause) {
          pauseExecutions++;
          tvPlaying = false;
        }
      },
      pauseForTransfer: () async {},
    );
    final controller = AriamiConnectClient(
      deviceId: 'queued-controller',
      deviceName: 'Queued Controller',
      clientType: 'mobile',
      snapshotProvider: () => AriamiPlaybackSnapshot.fromJson(const {}),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
      commandAckTimeout: const Duration(milliseconds: 100),
    );
    clients
      ..add(tv)
      ..add(controller);
    final baseUrl = 'http://127.0.0.1:${server.port}';

    await tv.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected && tv.devices.isNotEmpty);
    tv.publishState(activate: true);
    await pump(4);
    controller.sendCommand(AriamiConnectCommand.pause);
    expect(controller.pendingCommandCount, 1);

    await controller.connect(baseUrl: baseUrl);
    await waitFor(() =>
        controller.pendingCommandCount == 0 &&
        pauseExecutions == 1 &&
        controller.remoteSnapshot?.isPlaying == false);

    expect(pauseExecutions, 1);
  });

  test('"Play here", skip, and hand back: the old device follows the session',
      () async {
    // TV: active first, then hands off and becomes a mirror.
    var tvIndex = 0;
    var tvPlaying = true;
    AriamiPlaybackSnapshot? tvApplied;
    final tv = AriamiConnectClient(
      deviceId: 'tv',
      deviceName: 'Ariami TV',
      clientType: 'tv',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: [
          {'id': 'song-a', 'title': 'A'},
          {'id': 'song-b', 'title': 'B'},
        ],
        currentIndex: tvIndex,
        positionMs: 1000,
        durationMs: 60000,
        isPlaying: tvPlaying,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (snapshot) async => tvApplied = snapshot,
      handleCommand: (command, arguments) async {
        if (command == AriamiConnectCommand.pause) tvPlaying = false;
      },
      pauseForTransfer: () async => tvPlaying = false,
    );
    clients.add(tv);

    // Laptop: takes the session over via "Play here", then skips a track.
    var laptopIndex = 0;
    var laptopPlaying = false;
    AriamiPlaybackSnapshot? laptopQueue;
    late final AriamiConnectClient laptop;
    laptop = AriamiConnectClient(
      deviceId: 'laptop',
      deviceName: 'Laptop',
      clientType: 'desktop',
      snapshotProvider: () {
        final base = laptopQueue;
        if (base == null) return AriamiPlaybackSnapshot.fromJson(const {});
        return AriamiPlaybackSnapshot(
          queue: base.queue,
          currentIndex: laptopIndex,
          positionMs: 0,
          durationMs: 60000,
          isPlaying: laptopPlaying,
          shuffle: base.shuffle,
          repeatMode: base.repeatMode,
          volume: 1,
        );
      },
      applySnapshot: (snapshot) async {
        laptopQueue = snapshot;
        laptopIndex = snapshot.currentIndex;
      },
      handleCommand: (command, arguments) async {
        if (command == AriamiConnectCommand.play) laptopPlaying = true;
        if (command == AriamiConnectCommand.pause) laptopPlaying = false;
        if (command == AriamiConnectCommand.seek) {}
      },
      pauseForTransfer: () async => laptopPlaying = false,
    );
    clients.add(laptop);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await tv.connect(baseUrl: baseUrl);
    await laptop.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected && laptop.isConnected);
    tv.publishState(activate: true);
    await waitFor(() => laptop.activeDeviceId == 'tv');

    // "Play here" on the laptop.
    laptop.transferTo('laptop');
    await waitFor(() =>
        laptop.isThisDeviceActive &&
        tv.activeDeviceId == 'laptop' &&
        laptopQueue != null);

    // Laptop skips to the next track and publishes, as its controller would.
    laptopIndex = 1;
    laptopPlaying = true;
    laptop.publishState();

    // The TV (now a mirror) must follow the laptop's session.
    await waitFor(() => tv.remoteSnapshot?.currentTrackId == 'song-b');

    // Handing the session back to the TV must carry the *current* track.
    laptop.transferTo('tv');
    await waitFor(() => tvApplied != null && tv.isThisDeviceActive);
    expect(tvApplied!.currentTrackId, 'song-b');
  });

  test('first local skip publishes while transfer play is still pending',
      () async {
    var laptopPlaying = true;
    final laptop = AriamiConnectClient(
      deviceId: 'laptop',
      deviceName: 'Laptop',
      clientType: 'desktop',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: const [
          {'id': 'song-a', 'title': 'A'},
          {'id': 'song-b', 'title': 'B'},
        ],
        currentIndex: 0,
        positionMs: 1000,
        durationMs: 60000,
        isPlaying: laptopPlaying,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async => laptopPlaying = false,
    );
    clients.add(laptop);

    var tvIndex = 0;
    var tvPlaying = false;
    AriamiPlaybackSnapshot? tvQueue;
    final playUntilInterrupted = Completer<void>();
    final tv = AriamiConnectClient(
      deviceId: 'tv',
      deviceName: 'Ariami TV',
      clientType: 'tv',
      snapshotProvider: () {
        final queue = tvQueue;
        if (queue == null) return AriamiPlaybackSnapshot.fromJson(const {});
        return AriamiPlaybackSnapshot(
          queue: queue.queue,
          currentIndex: tvIndex,
          positionMs: 0,
          durationMs: 60000,
          isPlaying: tvPlaying,
          shuffle: queue.shuffle,
          repeatMode: queue.repeatMode,
          volume: 1,
        );
      },
      applySnapshot: (snapshot) async {
        tvQueue = snapshot;
        tvIndex = snapshot.currentIndex;
      },
      handleCommand: (command, arguments) async {
        if (command == AriamiConnectCommand.play) {
          tvPlaying = true;
          // Models just_audio: play() starts now, but its Future remains
          // pending until playback is later interrupted.
          await playUntilInterrupted.future;
        }
      },
      pauseForTransfer: () async => tvPlaying = false,
    );
    clients.add(tv);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await laptop.connect(baseUrl: baseUrl);
    await tv.connect(baseUrl: baseUrl);
    await waitFor(() => laptop.isConnected && tv.isConnected);
    laptop.publishState(activate: true);
    await waitFor(() => tv.activeDeviceId == 'laptop');

    laptop.transferTo('tv');
    await waitFor(() =>
        tv.isThisDeviceActive &&
        !tv.isApplyingRemoteState &&
        tvPlaying &&
        tvQueue != null);

    // The TV advances locally before play()'s Future has completed. The Mac
    // must still receive this very first post-transfer track change.
    tvIndex = 1;
    tv.publishState();
    await waitFor(() => laptop.remoteSnapshot?.currentTrackId == 'song-b');

    playUntilInterrupted.complete();
  });

  test('late-joining controller adopts the session from its welcome', () async {
    final tv = AriamiConnectClient(
      deviceId: 'tv',
      deviceName: 'Ariami TV',
      clientType: 'tv',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: [
          {'id': 'song-a', 'title': 'A'},
        ],
        currentIndex: 0,
        positionMs: 5000,
        durationMs: 60000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    clients.add(tv);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await tv.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected);
    tv.publishState(activate: true);
    await pump(4);

    // The laptop connects afterwards: its welcome alone must deliver the
    // active device and the current snapshot.
    final laptop = AriamiConnectClient(
      deviceId: 'laptop',
      deviceName: 'Laptop',
      clientType: 'desktop',
      snapshotProvider: () => AriamiPlaybackSnapshot.fromJson(const {}),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async {},
    );
    clients.add(laptop);
    await laptop.connect(baseUrl: baseUrl);
    await waitFor(() =>
        laptop.activeDeviceId == 'tv' &&
        laptop.remoteSnapshot?.currentTrackId == 'song-a');
  });

  test('controller continues the active song when the player disconnects',
      () async {
    var tvPlaying = true;
    final tv = AriamiConnectClient(
      deviceId: 'tv',
      deviceName: 'Ariami TV',
      clientType: 'tv',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: const [
          {'id': 'song-a', 'title': 'A'},
          {'id': 'song-b', 'title': 'B'},
        ],
        currentIndex: 1,
        positionMs: 12000,
        durationMs: 60000,
        isPlaying: tvPlaying,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      applySnapshot: (_) async {},
      handleCommand: (_, __) async {},
      pauseForTransfer: () async => tvPlaying = false,
    );
    clients.add(tv);

    // The phone has unrelated stale local playback. Before this fix, losing
    // the TV cleared its remote mirror and exposed this song instead.
    var phoneSnapshot = AriamiPlaybackSnapshot(
      queue: const [
        {'id': 'unrelated-local-song', 'title': 'Wrong song'},
      ],
      currentIndex: 0,
      positionMs: 0,
      durationMs: 60000,
      isPlaying: false,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );
    var phoneStartedPlaying = false;
    final phone = AriamiConnectClient(
      deviceId: 'phone',
      deviceName: 'Phone',
      clientType: 'mobile',
      snapshotProvider: () => phoneSnapshot.copyWith(
        isPlaying: phoneStartedPlaying,
      ),
      applySnapshot: (snapshot) async => phoneSnapshot = snapshot,
      handleCommand: (command, arguments) async {
        if (command == AriamiConnectCommand.seek) {
          phoneSnapshot = phoneSnapshot.copyWith(
            positionMs: (arguments['positionMs'] as num).toInt(),
          );
        } else if (command == AriamiConnectCommand.play) {
          phoneStartedPlaying = true;
        } else if (command == AriamiConnectCommand.pause) {
          phoneStartedPlaying = false;
        }
      },
      pauseForTransfer: () async => phoneStartedPlaying = false,
    );
    clients.add(phone);

    final baseUrl = 'http://127.0.0.1:${server.port}';
    await tv.connect(baseUrl: baseUrl);
    await phone.connect(baseUrl: baseUrl);
    await waitFor(() => tv.isConnected && phone.isConnected);
    tv.publishState(activate: true);
    await waitFor(() =>
        phone.activeDeviceId == 'tv' &&
        phone.remoteSnapshot?.currentTrackId == 'song-b');

    // Establish the phone as the controller, then make the player disappear.
    phone.sendCommand(
      AriamiConnectCommand.seek,
      <String, dynamic>{'positionMs': 12000},
    );
    await pump(4);
    await tv.dispose();

    await waitFor(() =>
        phone.isThisDeviceActive &&
        phoneSnapshot.currentTrackId == 'song-b' &&
        phoneStartedPlaying);
    expect(phoneSnapshot.currentTrackId, isNot('unrelated-local-song'));
    expect(phoneSnapshot.positionMs, greaterThanOrEqualTo(12000));
  });
}
