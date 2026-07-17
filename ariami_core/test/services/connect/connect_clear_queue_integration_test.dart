import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_client.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

/// End-to-end regression for the atomic clear_queue command: a phone
/// controller clears the desktop's queue while the
/// desktop keeps publishing position-tick states (the real-world broadcast
/// storm). The controller's mirror must converge to the single-track queue.
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

  Future<void> waitFor(bool Function() condition, String what) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('Condition not reached: $what');
  }

  test('clear_queue converges while active device publishes position ticks',
      () async {
    var desktopQueue = <Map<String, dynamic>>[
      {'id': 'song-a', 'title': 'A'},
      {'id': 'song-b', 'title': 'B'},
      {'id': 'song-c', 'title': 'C'},
    ];
    var desktopIndex = 1;
    var positionMs = 5000;
    final receivedCommands = <String>[];

    AriamiPlaybackSnapshot desktopSnapshot() => AriamiPlaybackSnapshot(
          queue: desktopQueue,
          currentIndex: desktopIndex,
          positionMs: positionMs,
          durationMs: 60000,
          isPlaying: true,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        );

    final desktop = AriamiConnectClient(
      deviceId: 'desktop',
      deviceName: 'Desktop',
      clientType: 'desktop',
      snapshotProvider: desktopSnapshot,
      applySnapshot: (_) async {},
      handleCommand: (command, arguments) async {
        receivedCommands.add(command);
        if (command == AriamiConnectCommand.clearQueue) {
          desktopQueue = <Map<String, dynamic>>[desktopQueue[desktopIndex]];
          desktopIndex = 0;
        }
      },
      pauseForTransfer: () async {},
    );
    final phone = AriamiConnectClient(
      deviceId: 'phone',
      deviceName: 'Phone',
      clientType: 'mobile',
      snapshotProvider: () => AriamiPlaybackSnapshot(
        queue: const [],
        currentIndex: -1,
        positionMs: 0,
        durationMs: 0,
        isPlaying: false,
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
    await waitFor(() => desktop.isConnected, 'desktop connected');
    desktop.publishState(activate: true);
    await waitFor(() => desktop.isThisDeviceActive, 'desktop active');

    await phone.connect(baseUrl: baseUrl);
    await waitFor(
      () => phone.remoteSnapshot?.queue.length == 3,
      'phone mirrors full queue',
    );

    // Simulate the desktop's ~500ms position-tick publishes racing the clear.
    final storm = Timer.periodic(const Duration(milliseconds: 100), (_) {
      positionMs += 100;
      desktop.publishState();
    });

    phone.sendCommand(AriamiConnectCommand.clearQueue);

    try {
      await waitFor(
        () => receivedCommands.contains(AriamiConnectCommand.clearQueue),
        'desktop received clear_queue',
      );
      await waitFor(
        () =>
            phone.remoteSnapshot?.queue.length == 1 &&
            phone.remoteSnapshot?.queue.single['id'] == 'song-b',
        'phone mirror converged to the single kept track',
      );
    } finally {
      storm.cancel();
    }
  });
}
