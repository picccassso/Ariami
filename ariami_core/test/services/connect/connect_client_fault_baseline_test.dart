import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('slice 4 protocol negotiation', () {
    test(
        '[client_protocol_advertisement] client advertises v3 and v2 '
        'before identify and records selection', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(factory, clock);
      addTearDown(client.dispose);

      await client.connect(baseUrl: 'http://ariami.test');

      expect(socket.sentMessages.take(2).map((message) => message.type),
          <String>[AriamiConnectMessageType.hello, WsMessageType.identify]);
      final hello = socket.sentMessages.first;
      expect(hello.data?['protocolVersions'], <int>[3, 2]);
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 0, owner: 'fault-client'),
          'protocolVersion': 3,
        },
      );
      await _pumpTwice();

      expect(client.negotiatedProtocolVersion, 3);
    });
  });

  group('slice 5 split queue and progress', () {
    test(
        '[progress_coalesced_one_second] 500 tracks publish once while '
        'progress is coalesced to one second', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var positionMs = 0;
      var playing = true;
      final tracks = List<Map<String, dynamic>>.generate(
        500,
        (index) => <String, dynamic>{'id': 'track-$index'},
      );
      AriamiPlaybackSnapshot snapshot() => AriamiPlaybackSnapshot(
            queue: tracks,
            currentIndex: 0,
            positionMs: positionMs,
            durationMs: 60000,
            isPlaying: playing,
            shuffle: false,
            repeatMode: 'off',
            volume: 1,
          );
      final client = _client(
        factory,
        clock,
        snapshotProvider: snapshot,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 0, owner: 'fault-client'),
          'protocolVersion': 3,
          'queueCounter': 0,
          'stateRevision': 0,
        },
      );
      await _pumpTwice();

      client.publishState();
      final queue = socket.sentMessages.lastWhere(
          (message) => message.type == AriamiConnectMessageType.queue);
      expect(queue.data?['tracks'], hasLength(500));
      expect(queue.data?['backingOrder'], List<int>.generate(500, (i) => i));
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.state),
        isEmpty,
      );

      socket.serverMessage(
        AriamiConnectMessageType.queue,
        <String, dynamic>{
          'ownerEpoch': 0,
          'activeDeviceId': 'fault-client',
          'queueCounter': 1,
          'tracks': tracks,
          'backingOrder': List<int>.generate(500, (i) => i),
        },
      );
      await _pumpTwice();
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.state),
        hasLength(1),
      );

      for (var tick = 1; tick <= 10; tick++) {
        positionMs = tick * 100;
        client.publishState();
      }
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.state),
        hasLength(1),
      );
      clock.elapse(const Duration(seconds: 1));
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.state),
        hasLength(2),
      );
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.queue),
        hasLength(1),
      );

      playing = false;
      client.publishState();
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.state),
        hasLength(3),
        reason: 'pause is discrete and must not wait for the progress timer',
      );
      expect(
        socket.sentMessages
            .lastWhere(
                (message) => message.type == AriamiConnectMessageType.state)
            .data?['semanticGeneration'],
        1,
        reason: 'the first semantic change after welcome must be fenced',
      );
    });

    test(
        '[queue_not_resent_before_ack] progress never repeats a queue that '
        'is still awaiting the hub acknowledgement', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var positionMs = 0;
      final tracks = List<Map<String, dynamic>>.generate(
        500,
        (index) => <String, dynamic>{'id': 'track-$index'},
      );
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => AriamiPlaybackSnapshot(
          queue: tracks,
          currentIndex: 0,
          positionMs: positionMs,
          durationMs: 60000,
          isPlaying: true,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        ),
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 0, owner: 'fault-client'),
          'protocolVersion': 3,
          'queueCounter': 0,
          'stateRevision': 0,
        },
      );
      await _pumpTwice();

      // The hub stays silent, so every one of these publishes still believes
      // the queue is unpublished. Only the first may cross the wire.
      for (var tick = 0; tick < 10; tick++) {
        positionMs = tick * 200;
        client.publishState();
      }
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.queue),
        hasLength(1),
      );

      // A takeover still resends, because the hub commits ownership from the
      // queue message itself.
      client.publishState(activate: true);
      expect(
        socket.sentMessages
            .where((message) => message.type == AriamiConnectMessageType.queue),
        hasLength(2),
      );
    });
  });

  group('slice 6 capabilities and takeover intent', () {
    test(
        '[capabilities_advertised] hello advertises the executable command '
        'set before identify', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(
        factory,
        clock,
        supportedCommands: const <String>{
          AriamiConnectCommand.pause,
          AriamiConnectCommand.clearQueue,
        },
      );
      addTearDown(client.dispose);

      await client.connect(baseUrl: 'http://ariami.test');

      final hello = socket.sentMessages.first;
      expect(hello.type, AriamiConnectMessageType.hello);
      expect(
        Set<String>.from(hello.data?['supportedCommands'] as List),
        <String>{
          AriamiConnectCommand.pause,
          AriamiConnectCommand.clearQueue,
        },
      );
    });

    test(
        '[unsupported_command_fails_explicitly] a target refuses commands it '
        'did not advertise instead of reporting false success', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var commandCalls = 0;
      final client = _client(
        factory,
        clock,
        supportedCommands: const <String>{AriamiConnectCommand.pause},
        handleCommand: (_, __) async => commandCalls++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'fault-client'),
      );
      await _pumpTwice();

      socket.serverMessage(
        AriamiConnectMessageType.command,
        <String, dynamic>{
          ..._authority(epoch: 1, owner: 'fault-client'),
          'commandId': 'unsupported-volume',
          'command': AriamiConnectCommand.setVolume,
        },
      );
      await _pumpTwice();

      expect(commandCalls, 0);
      final result = socket.sentMessages.lastWhere((message) =>
          message.type == AriamiConnectMessageType.commandResult &&
          message.data?['commandId'] == 'unsupported-volume');
      expect(result.data?['ok'], isFalse);
      expect(result.data?['code'], 'UNSUPPORTED_COMMAND');
    });

    test(
        '[pending_takeover_cancellation] cancelling before welcome prevents a '
        'stale local play intent from taking ownership', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => AriamiPlaybackSnapshot(
          queue: const <Map<String, dynamic>>[
            <String, dynamic>{'id': 'cancelled-track'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 1000,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        ),
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      client.requestLocalTakeover();
      expect(client.hasPendingLocalTakeover, isTrue);

      client.cancelLocalTakeover();
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'desktop'),
      );
      await _pumpTwice();

      expect(client.hasPendingLocalTakeover, isFalse);
      expect(
        socket.sentMessages.where((message) =>
            (message.type == AriamiConnectMessageType.state ||
                message.type == AriamiConnectMessageType.queue) &&
            message.data?['activate'] == true),
        isEmpty,
      );
    });

    test('a takeover cancelled after send republishes paused on confirmation',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var playing = true;
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => AriamiPlaybackSnapshot(
          queue: const <Map<String, dynamic>>[
            <String, dynamic>{'id': 'local-track'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 1000,
          isPlaying: playing,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        ),
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'desktop'),
      );
      await _pumpTwice();

      client.requestLocalTakeover();
      playing = false;
      client.cancelLocalTakeover();
      socket.serverMessage(
        AriamiConnectMessageType.devices,
        _authority(epoch: 2, owner: 'fault-client'),
      );
      await _pumpTwice();

      final publications = socket.sentMessages
          .where((message) => message.type == AriamiConnectMessageType.state)
          .toList(growable: false);
      expect(publications, hasLength(2));
      expect(publications.first.data?['activate'], isTrue);
      expect(publications.last.data?['activate'], isFalse);
      expect(publications.last.data?['snapshot']['isPlaying'], isFalse);
      expect(publications.last.data?['ownerEpoch'], 2);
    });
  });

  group('slice 2 client transport hardening', () {
    test('[half_open_socket] is replaced after the inbound deadline', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final replacement = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[socket, replacement],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      clock.elapse(const Duration(seconds: 60));
      await _pump();
      await _pump();

      expect(client.isConnected, isTrue);
      expect(factory.openedAt,
          <Duration>[Duration.zero, const Duration(seconds: 60)]);
      expect(socket.sentTypes.where((type) => type == 'ping'), hasLength(2));
    });

    test('any inbound message restarts the liveness deadline', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final replacement = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[socket, replacement],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      clock.elapse(const Duration(seconds: 59));
      socket.serverMessage('pong');
      clock.elapse(const Duration(seconds: 59));
      await _pump();
      expect(factory.openedAt, <Duration>[Duration.zero]);

      clock.elapse(const Duration(seconds: 1));
      await _pump();
      await _pump();
      expect(factory.openedAt,
          <Duration>[Duration.zero, const Duration(seconds: 119)]);
    });

    test('[bounded_connect_wait] connect readiness has a bounded wait',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel(readyCompletes: false);
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(
        factory,
        clock,
        connectTimeout: const Duration(milliseconds: 10),
      );

      await client.connect(baseUrl: 'http://ariami.test');

      expect(client.isConnected, isFalse);
      expect(client.errorMessage, 'Ariami Connect is reconnecting…');
      expect(clock.activeOneShotDelays, contains(const Duration(seconds: 1)));
      await client.dispose();
    });

    test('[bounded_refresh_close] opens a replacement after its deadline',
        () async {
      final clock = _FakeTimerClock();
      final oldSocket = _FakeWebSocketChannel(closeCompletes: false);
      final replacement = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[oldSocket, replacement],
      );
      final client = _client(
        factory,
        clock,
        refreshCloseTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      await client.refreshState();

      expect(factory.openedAt, <Duration>[Duration.zero, Duration.zero]);
      expect(client.isConnected, isTrue);
    });

    test('[unbounded_dispose_wait] completes after the teardown deadline',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel(closeCompletes: false);
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(
        factory,
        clock,
        disposeTimeout: const Duration(milliseconds: 10),
      );
      await client.connect(baseUrl: 'http://ariami.test');

      var disposed = false;
      final disposeFuture = client.dispose().then((_) => disposed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(disposed, isTrue);
      await disposeFuture;
    });

    test('[stale_socket_callback] cannot close its replacement', () async {
      final clock = _FakeTimerClock();
      final oldSocket = _FakeWebSocketChannel();
      final replacement = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[oldSocket, replacement],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      await client.refreshState();

      oldSocket.forceLateDone();

      expect(client.isConnected, isTrue);
      expect(factory.openedAt, <Duration>[Duration.zero, Duration.zero]);
      expect(
        clock.activeOneShotDelays,
        isNot(contains(const Duration(seconds: 1))),
      );
    });

    test('[authentication_4001_reconnects] requests recovery and stays closed',
        () async {
      final clock = _FakeTimerClock();
      final rejected = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[rejected]);
      var authenticationRecoveries = 0;
      final client = _client(
        factory,
        clock,
        onAuthenticationRequired: () => authenticationRecoveries++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      rejected.serverClose(4001, 'Authentication failed');
      await _pump();
      clock.elapse(const Duration(minutes: 5));
      await _pump();

      expect(factory.openedAt, <Duration>[Duration.zero]);
      expect(authenticationRecoveries, 1);
      expect(
          client.errorMessage, 'Your session expired. Please sign in again.');
      expect(client.isConnected, isFalse);
    });

    test('[reconnect_backoff_resets] increases across short-lived sockets',
        () async {
      final clock = _FakeTimerClock();
      final first = _FakeWebSocketChannel();
      final second = _FakeWebSocketChannel();
      final third = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[first, second, third],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      first.serverClose(1006, 'Network lost');
      await _pump();
      clock.elapse(const Duration(seconds: 1));
      await _pump();
      second.serverClose(1006, 'Network lost again');
      await _pump();
      clock.elapse(const Duration(milliseconds: 1999));
      expect(factory.openedAt, hasLength(2));
      clock.elapse(const Duration(milliseconds: 1));
      await _pump();

      expect(
        factory.openedAt,
        <Duration>[
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 3),
        ],
      );
    });

    test('reconnect backoff resets after a stable responsive connection',
        () async {
      final clock = _FakeTimerClock();
      final first = _FakeWebSocketChannel();
      final stable = _FakeWebSocketChannel();
      final third = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[first, stable, third],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      first.serverClose(1006, 'Network lost');
      await _pump();
      clock.elapse(const Duration(seconds: 1));
      await _pump();
      clock.elapse(const Duration(seconds: 59));
      stable.serverMessage('pong');
      clock.elapse(const Duration(seconds: 1));
      stable.serverClose(1006, 'Network lost after stable operation');
      await _pump();
      clock.elapse(const Duration(seconds: 1));
      await _pump();

      expect(
        factory.openedAt,
        <Duration>[
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 62),
        ],
      );
    });

    test('[replaced_4000_reconnects] stays closed without fighting replacement',
        () async {
      final clock = _FakeTimerClock();
      final replaced = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[replaced]);
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      replaced.serverClose(4000, 'Replaced by a newer connection');
      await _pump();
      clock.elapse(const Duration(minutes: 5));
      await _pump();

      expect(factory.openedAt, <Duration>[Duration.zero]);
      expect(client.isConnected, isFalse);
    });

    test('non-replacement close 4000 remains transient', () async {
      final clock = _FakeTimerClock();
      final timedOut = _FakeWebSocketChannel();
      final replacement = _FakeWebSocketChannel();
      final factory = _SocketFactory(
        clock,
        <_FakeWebSocketChannel>[timedOut, replacement],
      );
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');

      timedOut.serverClose(4000, 'Connection timed out');
      await _pump();
      clock.elapse(const Duration(seconds: 1));
      await _pump();

      expect(factory.openedAt,
          <Duration>[Duration.zero, const Duration(seconds: 1)]);
      expect(client.isConnected, isTrue);
    });
  });

  group('slice 3 client ownership fencing', () {
    test('[former_owner_pauses_before_mirror] pause is awaited once per epoch',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final pause = Completer<void>();
      var pauseCalls = 0;
      final client = _client(
        factory,
        clock,
        pauseForTransfer: () {
          pauseCalls++;
          return pause.future;
        },
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
          AriamiConnectMessageType.welcome,
          _authority(
            epoch: 1,
            owner: 'fault-client',
          ));
      await _pumpTwice();

      socket.serverMessage(
          AriamiConnectMessageType.state,
          _authority(
            epoch: 2,
            owner: 'phone',
            revision: 1,
            trackId: 'phone-track',
          ));
      await _pumpTwice();

      expect(pauseCalls, 1);
      expect(client.ownerEpoch, 1);
      expect(client.remoteSnapshot, isNull);

      pause.complete();
      await _pumpTwice();
      expect(client.ownerEpoch, 2);
      expect(client.activeDeviceId, 'phone');
      expect(client.remoteSnapshot?.currentTrackId, 'phone-track');

      socket.serverMessage(
          AriamiConnectMessageType.state,
          _authority(
            epoch: 2,
            owner: 'phone',
            revision: 2,
            trackId: 'phone-track-2',
          ));
      await _pumpTwice();
      expect(pauseCalls, 1);
      expect(client.remoteSnapshot?.currentTrackId, 'phone-track-2');
    });

    test('[controller_observer_keeps_playing] only the former owner pauses',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var pauseCalls = 0;
      final client = _client(
        factory,
        clock,
        pauseForTransfer: () async => pauseCalls++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
          AriamiConnectMessageType.welcome,
          _authority(
            epoch: 1,
            owner: 'phone',
            trackId: 'phone-track',
          ));
      await _pumpTwice();

      socket.serverMessage(
          AriamiConnectMessageType.state,
          _authority(
            epoch: 2,
            owner: 'desktop',
            revision: 1,
            trackId: 'desktop-track',
          ));
      await _pumpTwice();

      expect(pauseCalls, 0);
      expect(client.ownerEpoch, 2);
      expect(client.activeDeviceId, 'desktop');
      expect(client.remoteSnapshot?.currentTrackId, 'desktop-track');
    });

    test('[stale_client_work_rejected] stale state and command are ignored',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var commandCalls = 0;
      final client = _client(
        factory,
        clock,
        handleCommand: (_, __) async => commandCalls++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
          AriamiConnectMessageType.welcome,
          _authority(
            epoch: 3,
            owner: 'fault-client',
            trackId: 'current',
          ));
      await _pumpTwice();

      socket.serverMessage(
          AriamiConnectMessageType.state,
          _authority(
            epoch: 2,
            owner: 'phone',
            revision: 10,
            trackId: 'stale',
          ));
      socket.serverMessage(AriamiConnectMessageType.command, <String, dynamic>{
        'commandId': 'stale-client-command',
        'command': AriamiConnectCommand.next,
        'activeDeviceId': 'fault-client',
        'ownerEpoch': 2,
      });
      await _pumpTwice();

      expect(client.ownerEpoch, 3);
      expect(client.remoteSnapshot?.currentTrackId, 'current');
      expect(commandCalls, 0);
      final result = socket.sentMessages.lastWhere((message) =>
          message.type == AriamiConnectMessageType.commandResult &&
          message.data?['commandId'] == 'stale-client-command');
      expect(result.data?['ok'], isFalse);
      expect(result.data?['ownerEpoch'], 3);
    });

    test('[epoch_wire_propagation] state commands and transfers carry epoch',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
          AriamiConnectMessageType.welcome,
          _authority(
            epoch: 5,
            owner: 'fault-client',
          ));
      await _pumpTwice();

      client.publishState();
      client.sendCommand(AriamiConnectCommand.pause);
      client.transferTo('phone');

      for (final type in <String>[
        AriamiConnectMessageType.state,
        AriamiConnectMessageType.command,
        AriamiConnectMessageType.transfer,
      ]) {
        final message =
            socket.sentMessages.lastWhere((item) => item.type == type);
        expect(message.data?['ownerEpoch'], 5, reason: type);
      }
    });
  });

  group('slice 7 bounded reliable commands', () {
    test('[small_retry_envelope] retries carry only a collision-proof id',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 4, owner: 'tv'),
      );
      await _pumpTwice();

      client.sendCommand(
        AriamiConnectCommand.seek,
        <String, dynamic>{'positionMs': 1234},
      );
      final first = socket.sentMessages.lastWhere(
          (message) => message.type == AriamiConnectMessageType.command);
      final commandId = first.data?['commandId'] as String;
      expect(
        commandId,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );

      clock.elapse(const Duration(seconds: 4));
      final commands = socket.sentMessages
          .where((message) => message.type == AriamiConnectMessageType.command)
          .toList(growable: false);
      expect(commands, hasLength(2));
      expect(commands.last.data, <String, dynamic>{
        'commandId': commandId,
        'retry': true,
      });
      expect(
        utf8.encode(jsonEncode(commands.last.toJson())).length,
        lessThan(utf8.encode(jsonEncode(first.toJson())).length),
      );
    });

    test(
        '[small_retry_envelope] a hub that cannot honour the envelope gets '
        'the retained payload', () async {
      for (final code in <String>['UNKNOWN_COMMAND', 'UNSUPPORTED_COMMAND']) {
        final clock = _FakeTimerClock();
        final socket = _FakeWebSocketChannel();
        final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
        final client = _client(factory, clock);
        addTearDown(client.dispose);
        await client.connect(baseUrl: 'http://ariami.test');
        socket.serverMessage(
          AriamiConnectMessageType.welcome,
          _authority(epoch: 1, owner: 'tv'),
        );
        await _pumpTwice();

        client.sendCommand(
          AriamiConnectCommand.seek,
          <String, dynamic>{'positionMs': 1234},
        );
        final first = socket.sentMessages.lastWhere(
            (message) => message.type == AriamiConnectMessageType.command);
        final commandId = first.data?['commandId'] as String;
        clock.elapse(const Duration(seconds: 4));

        // An older hub reads the envelope as an empty command; a restarted hub
        // no longer holds the payload. Either way the work must still run.
        socket.serverMessage(
          AriamiConnectMessageType.commandResult,
          <String, dynamic>{
            'commandId': commandId,
            'ok': false,
            'code': code,
            'message': 'no retained payload',
            'ownerEpoch': 1,
            'activeDeviceId': 'tv',
          },
        );
        await _pumpTwice();

        final commands = socket.sentMessages
            .where(
                (message) => message.type == AriamiConnectMessageType.command)
            .toList(growable: false);
        expect(commands, hasLength(3), reason: code);
        expect(commands.last.data, first.data, reason: code);
        expect(client.pendingCommandCount, 1, reason: code);
        expect(client.errorCode, isNull, reason: code);

        // The replay is sent once. A hub that fails it again surfaces the
        // failure rather than looping.
        socket.serverMessage(
          AriamiConnectMessageType.commandResult,
          <String, dynamic>{
            'commandId': commandId,
            'ok': false,
            'code': code,
            'ownerEpoch': 1,
            'activeDeviceId': 'tv',
          },
        );
        await _pumpTwice();
        expect(
          socket.sentMessages
              .where(
                  (message) => message.type == AriamiConnectMessageType.command)
              .length,
          3,
          reason: code,
        );
        expect(client.errorCode, code, reason: code);
        expect(client.pendingCommandCount, 0, reason: code);
      }
    });

    test('[target_execution_idempotent] a repeated id executes exactly once',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var executions = 0;
      final client = _client(
        factory,
        clock,
        handleCommand: (_, __) async => executions++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'fault-client'),
      );
      await _pumpTwice();
      final command = <String, dynamic>{
        ..._authority(epoch: 1, owner: 'fault-client'),
        'commandId': 'same-command-id',
        'command': AriamiConnectCommand.pause,
        'arguments': const <String, dynamic>{},
      };

      socket.serverMessage(AriamiConnectMessageType.command, command);
      socket.serverMessage(AriamiConnectMessageType.command, command);
      await _pumpTwice();
      await _pumpTwice();

      expect(executions, 1);
      expect(
        socket.sentMessages.where((message) =>
            message.type == AriamiConnectMessageType.commandResult &&
            message.data?['commandId'] == 'same-command-id'),
        hasLength(2),
      );
    });

    test(
        '[optimistic_reconciliation] [client_retry_exhaustion] failure is visible',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var changes = 0;
      final client = _client(
        factory,
        clock,
        commandAckTimeout: const Duration(seconds: 1),
        maxCommandAttempts: 2,
        onChanged: () => changes++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'tv'),
      );
      await _pumpTwice();
      final changesBefore = changes;

      client.sendCommand(AriamiConnectCommand.pause);
      clock.elapse(const Duration(seconds: 2));
      await _pumpTwice();

      expect(client.pendingCommandCount, 0);
      expect(client.errorCode, 'COMMAND_RETRY_EXHAUSTED');
      expect(client.errorMessage, isNotEmpty);
      expect(changes, greaterThan(changesBefore));

      client.sendCommand(AriamiConnectCommand.play);
      final recovery = socket.sentMessages.lastWhere((message) =>
          message.type == AriamiConnectMessageType.command &&
          message.data?['retry'] != true);
      socket.serverMessage(
        AriamiConnectMessageType.commandResult,
        <String, dynamic>{
          'commandId': recovery.data?['commandId'],
          'ok': true,
          'ownerEpoch': 1,
          'activeDeviceId': 'tv',
        },
      );
      await _pumpTwice();
      expect(client.errorCode, isNull);
      expect(client.errorMessage, isNull);
    });

    test('[oversized_play_context] invalid metadata never crosses the socket',
        () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final client = _client(factory, clock);
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        _authority(epoch: 1, owner: 'tv'),
      );
      await _pumpTwice();
      final before = socket.sentMessages
          .where((message) => message.type == AriamiConnectMessageType.command)
          .length;

      client.sendCommand(
        AriamiConnectCommand.playContext,
        <String, dynamic>{
          'snapshot': <String, dynamic>{
            'queue': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'track', 'title': 'x' * 513},
            ],
          },
        },
      );
      await _pumpTwice();

      expect(client.errorCode, 'PLAY_CONTEXT_TOO_LARGE');
      expect(
        socket.sentMessages.where(
            (message) => message.type == AriamiConnectMessageType.command),
        hasLength(before),
      );
    });
  });

  group('slice 8 reversible handoffs', () {
    test(
        '[prepared_target_restored] cancel restores the exact local '
        'pre-prepare snapshot', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final local = _snapshot('local', positionMs: 4321, isPlaying: true);
      var current = local;
      final applied = <AriamiPlaybackSnapshot>[];
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => current,
        applySnapshot: (snapshot) async {
          applied.add(snapshot);
          current = snapshot;
        },
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 1, owner: 'source'),
          'protocolVersion': 3,
          'queueCounter': 7,
          'stateRevision': 1,
          'semanticGeneration': 4,
        },
      );
      await _pumpTwice();

      socket.serverMessage(
        AriamiConnectMessageType.transfer,
        _transfer(
          phase: 'prepare',
          id: 'transfer-1',
          epoch: 1,
          semanticGeneration: 4,
          snapshot: _snapshot('remote', positionMs: 9000, isPlaying: true),
        ),
      );
      await _pumpTwice();
      expect(current.currentTrackId, 'remote');
      expect(current.isPlaying, isFalse);
      final prepared = socket.sentMessages.lastWhere(
        (message) =>
            message.type == AriamiConnectMessageType.transferResult &&
            message.data?['transferId'] == 'transfer-1',
      );
      expect(prepared.data?['queueCounter'], 7);
      expect(prepared.data?['semanticGeneration'], 4);

      socket.serverMessage(
        AriamiConnectMessageType.transfer,
        _transfer(
          phase: 'cancel',
          id: 'transfer-1',
          epoch: 1,
          semanticGeneration: 4,
        ),
      );
      await _pumpTwice();

      expect(current.currentTrackId, 'local');
      expect(current.positionMs, 4321);
      expect(current.isPlaying, isTrue);
      expect(applied.last.currentTrackId, 'local');
    });

    test(
        '[handoff_cancel_paths] disconnect waits for an in-flight prepare '
        'before restoring local state', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      final local = _snapshot('local', positionMs: 4321, isPlaying: true);
      var current = local;
      final prepareApply = Completer<void>();
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => current,
        applySnapshot: (snapshot) async {
          if (snapshot.currentTrackId == 'remote') {
            await prepareApply.future;
          }
          current = snapshot;
        },
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 1, owner: 'source'),
          'protocolVersion': 3,
          'queueCounter': 7,
          'stateRevision': 1,
          'semanticGeneration': 4,
        },
      );
      await _pumpTwice();

      socket.serverMessage(
        AriamiConnectMessageType.transfer,
        _transfer(
          phase: 'prepare',
          id: 'transfer-1',
          epoch: 1,
          semanticGeneration: 4,
          snapshot: _snapshot('remote', positionMs: 9000, isPlaying: true),
        ),
      );
      await _pumpTwice();
      socket.serverClose(1006, 'Network lost');
      await _pumpTwice();

      prepareApply.complete();
      await _pumpTwice();
      await _pumpTwice();

      expect(current.currentTrackId, 'local');
      expect(current.positionMs, 4321);
      expect(current.isPlaying, isTrue);
    });

    test(
        '[current_transfer_only] [handoff_actions_idempotent] only the current '
        'transfer commits and target start is idempotent', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var current = _snapshot('local', isPlaying: false);
      var seekCalls = 0;
      var playCalls = 0;
      final client = _client(
        factory,
        clock,
        snapshotProvider: () => current,
        applySnapshot: (snapshot) async => current = snapshot,
        handleCommand: (command, _) async {
          if (command == AriamiConnectCommand.seek) seekCalls++;
          if (command == AriamiConnectCommand.play) playCalls++;
        },
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 1, owner: 'source'),
          'protocolVersion': 3,
          'queueCounter': 7,
          'stateRevision': 1,
          'semanticGeneration': 4,
        },
      );
      await _pumpTwice();

      for (final id in <String>['old-transfer', 'current-transfer']) {
        socket.serverMessage(
          AriamiConnectMessageType.transfer,
          _transfer(
            phase: 'prepare',
            id: id,
            epoch: 1,
            semanticGeneration: 4,
            snapshot: _snapshot(id, isPlaying: true),
          ),
        );
        await _pumpTwice();
      }
      final staleCommit = _transfer(
        phase: 'commit',
        id: 'old-transfer',
        epoch: 2,
        semanticGeneration: 5,
        snapshot: _snapshot('old-transfer', isPlaying: true),
      );
      socket.serverMessage(AriamiConnectMessageType.transfer, staleCommit);
      await _pumpTwice();
      expect(seekCalls, 0);
      expect(playCalls, 0);

      final commit = _transfer(
        phase: 'commit',
        id: 'current-transfer',
        epoch: 2,
        semanticGeneration: 5,
        snapshot: _snapshot('current-transfer', isPlaying: true),
      );
      socket.serverMessage(AriamiConnectMessageType.transfer, commit);
      await _pumpTwice();
      socket.serverMessage(AriamiConnectMessageType.transfer, commit);
      await _pumpTwice();

      expect(seekCalls, 1);
      expect(playCalls, 1);
    });

    test(
        '[handoff_actions_idempotent] duplicate commit relinquishes the '
        'source once', () async {
      final clock = _FakeTimerClock();
      final socket = _FakeWebSocketChannel();
      final factory = _SocketFactory(clock, <_FakeWebSocketChannel>[socket]);
      var pauseCalls = 0;
      final client = _client(
        factory,
        clock,
        pauseForTransfer: () async => pauseCalls++,
      );
      addTearDown(client.dispose);
      await client.connect(baseUrl: 'http://ariami.test');
      socket.serverMessage(
        AriamiConnectMessageType.welcome,
        <String, dynamic>{
          ..._authority(epoch: 1, owner: 'fault-client'),
          'protocolVersion': 3,
          'queueCounter': 7,
          'stateRevision': 1,
          'semanticGeneration': 4,
        },
      );
      await _pumpTwice();
      final commit = <String, dynamic>{
        ..._transfer(
          phase: 'commit',
          id: 'source-commit',
          epoch: 2,
          semanticGeneration: 5,
          snapshot: _snapshot('remote', isPlaying: true),
        ),
        'targetDeviceId': 'other-device',
      };

      socket.serverMessage(AriamiConnectMessageType.transfer, commit);
      await _pumpTwice();
      socket.serverMessage(AriamiConnectMessageType.transfer, commit);
      await _pumpTwice();

      expect(pauseCalls, 1);
    });
  });
}

AriamiConnectClient _client(
  _SocketFactory sockets,
  _FakeTimerClock clock, {
  Duration connectTimeout = const Duration(seconds: 8),
  Duration refreshCloseTimeout = const Duration(seconds: 1),
  Duration disposeTimeout = const Duration(seconds: 1),
  Duration commandAckTimeout = const Duration(seconds: 4),
  int maxCommandAttempts = 4,
  void Function()? onChanged,
  void Function()? onAuthenticationRequired,
  Future<void> Function()? pauseForTransfer,
  ConnectCommandHandler? handleCommand,
  Future<void> Function(AriamiPlaybackSnapshot snapshot)? applySnapshot,
  AriamiPlaybackSnapshot Function()? snapshotProvider,
  Set<String> supportedCommands = AriamiConnectCommand.supported,
}) =>
    AriamiConnectClient(
      deviceId: 'fault-client',
      deviceName: 'Fault client',
      clientType: 'mobile',
      snapshotProvider:
          snapshotProvider ?? () => AriamiPlaybackSnapshot.fromJson(const {}),
      applySnapshot: applySnapshot ?? (_) async {},
      handleCommand: handleCommand ?? (_, __) async {},
      pauseForTransfer: pauseForTransfer ?? () async {},
      supportedCommands: supportedCommands,
      commandAckTimeout: commandAckTimeout,
      maxCommandAttempts: maxCommandAttempts,
      connectTimeout: connectTimeout,
      refreshCloseTimeout: refreshCloseTimeout,
      disposeTimeout: disposeTimeout,
      onChanged: onChanged,
      onAuthenticationRequired: onAuthenticationRequired,
      webSocketFactory: sockets.call,
      timerFactory: clock.timer,
      periodicTimerFactory: clock.periodic,
    );

AriamiPlaybackSnapshot _snapshot(
  String trackId, {
  int positionMs = 0,
  bool isPlaying = true,
}) =>
    AriamiPlaybackSnapshot(
      queue: <Map<String, dynamic>>[
        <String, dynamic>{'id': trackId, 'title': trackId},
      ],
      currentIndex: 0,
      positionMs: positionMs,
      durationMs: 60000,
      isPlaying: isPlaying,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );

Map<String, dynamic> _transfer({
  required String phase,
  required String id,
  required int epoch,
  required int semanticGeneration,
  AriamiPlaybackSnapshot? snapshot,
}) =>
    <String, dynamic>{
      'phase': phase,
      'transferId': id,
      'sourceDeviceId': 'source',
      'targetDeviceId': 'fault-client',
      if (snapshot != null) 'snapshot': snapshot.toJson(),
      'queueCounter': 7,
      'ownerEpoch': epoch,
      'semanticGeneration': semanticGeneration,
    };

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _pumpTwice() async {
  await _pump();
  await _pump();
}

Map<String, dynamic> _authority({
  required int epoch,
  required String owner,
  int revision = 0,
  String? trackId,
}) =>
    <String, dynamic>{
      'protocolVersion': 2,
      'ownerEpoch': epoch,
      'activeDeviceId': owner,
      'revision': revision,
      'devices': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': owner,
          'name': owner,
          'type': 'mobile',
          'canPlay': true,
          'connectedAt': '2026-08-01T00:00:00.000Z',
          'isActive': true,
        },
      ],
      if (trackId != null)
        'snapshot': AriamiPlaybackSnapshot(
          queue: <Map<String, dynamic>>[
            <String, dynamic>{'id': trackId, 'title': trackId},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 60000,
          isPlaying: true,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        ).toJson(),
    };

class _SocketFactory {
  _SocketFactory(this.clock, this.sockets);

  final _FakeTimerClock clock;
  final List<_FakeWebSocketChannel> sockets;
  final List<Duration> openedAt = <Duration>[];
  int _next = 0;

  WebSocketChannel call(Uri uri) {
    openedAt.add(clock.elapsed);
    if (_next >= sockets.length) {
      throw StateError('No fake socket remains for $uri');
    }
    return sockets[_next++];
  }
}

class _FakeTimerClock {
  Duration elapsed = Duration.zero;
  final List<_ScheduledTimer> _timers = <_ScheduledTimer>[];

  List<Duration> get activeOneShotDelays => _timers
      .where((timer) => timer.isActive && !timer.periodic)
      .map((timer) => timer.due - elapsed)
      .toList(growable: false);

  Timer timer(Duration duration, void Function() callback) {
    final timer = _ScheduledTimer(
      due: elapsed + duration,
      interval: duration,
      callback: (_) => callback(),
      periodic: false,
    );
    _timers.add(timer);
    return timer;
  }

  Timer periodic(Duration duration, void Function(Timer timer) callback) {
    final timer = _ScheduledTimer(
      due: elapsed + duration,
      interval: duration,
      callback: callback,
      periodic: true,
    );
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    final target = elapsed + duration;
    while (true) {
      _ScheduledTimer? next;
      for (final timer in _timers) {
        if (!timer.isActive || timer.due > target) continue;
        if (next == null || timer.due < next.due) next = timer;
      }
      if (next == null) break;
      elapsed = next.due;
      next.fire();
    }
    elapsed = target;
  }
}

class _ScheduledTimer implements Timer {
  _ScheduledTimer({
    required this.due,
    required this.interval,
    required this.callback,
    required this.periodic,
  });

  Duration due;
  final Duration interval;
  final void Function(Timer timer) callback;
  final bool periodic;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick++;
    if (periodic) {
      due += interval;
    } else {
      _active = false;
    }
    callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeWebSocketChannel({
    bool readyCompletes = true,
    this.closeCompletes = true,
  }) : ready = readyCompletes ? Future<void>.value() : Completer<void>().future;

  final _ManualStream _stream = _ManualStream();
  final bool closeCompletes;
  final List<dynamic> sent = <dynamic>[];
  final Completer<void> _pendingClose = Completer<void>();

  @override
  final Future<void> ready;

  int? _closeCode;
  String? _closeReason;

  List<String> get sentTypes => sent
      .whereType<String>()
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .map((message) => message['type'] as String)
      .toList(growable: false);

  void serverClose(int code, String reason) {
    _closeCode = code;
    _closeReason = reason;
    _stream.forceDone();
  }

  List<WsMessage> get sentMessages => sent
      .whereType<String>()
      .map((raw) => WsMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>))
      .toList(growable: false);

  void serverMessage(String type, [Map<String, dynamic>? data]) {
    _stream.add(jsonEncode(<String, dynamic>{
      'type': type,
      if (data != null) 'data': data,
      'timestamp': '2026-08-01T00:00:00.000Z',
    }));
  }

  void forceLateDone() => _stream.forceDone();

  void completePendingClose() {
    if (!_pendingClose.isCompleted) _pendingClose.complete();
  }

  @override
  Stream<dynamic> get stream => _stream;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(
        sent,
        closeCompletes
            ? () => Future<void>.value()
            : () => _pendingClose.future,
      );

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String? get protocol => null;
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this.sent, this.onClose);

  final List<dynamic> sent;
  final Future<void> Function() onClose;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) => onClose();

  @override
  Future<void> get done => Future<void>.value();
}

class _ManualStream extends Stream<dynamic> {
  void Function(dynamic data)? _onData;
  void Function()? _onDone;

  void add(dynamic data) => _onData?.call(data);
  void forceDone() => _onDone?.call();

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    _onDone = onDone;
    return _ManualSubscription(
      setOnData: (callback) => _onData = callback,
      setOnError: (_) {},
      setOnDone: (callback) => _onDone = callback,
    );
  }
}

class _ManualSubscription implements StreamSubscription<dynamic> {
  _ManualSubscription({
    required this.setOnData,
    required this.setOnError,
    required this.setOnDone,
  });

  final void Function(void Function(dynamic data)? callback) setOnData;
  final void Function(Function? callback) setOnError;
  final void Function(void Function()? callback) setOnDone;
  bool _isPaused = false;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    final completer = Completer<E>();
    if (futureValue != null) completer.complete(futureValue);
    return completer.future;
  }

  @override
  Future<void> cancel() => Future<void>.value();

  @override
  bool get isPaused => _isPaused;

  @override
  void onData(void Function(dynamic data)? handleData) => setOnData(handleData);

  @override
  void onDone(void Function()? handleDone) => setOnDone(handleDone);

  @override
  void onError(Function? handleError) => setOnError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) {
    _isPaused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _isPaused = false;
}
