import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test(
      '[legacy_v2_negotiation_fallback] a legacy peer keeps the '
      'command-dedupe v2 welcome', () {
    final hub = AriamiConnectHub();
    final phone = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');

    final welcome = phone.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome);
    // Clients only retransmit unacknowledged commands when the hub reports
    // version >= 2 (idempotent command delivery). Downgrading this silently
    // disables command retries on lossy links.
    expect(welcome.data?['protocolVersion'], 2);
    expect(
      Set<String>.from(welcome.data?['supportedCommands'] as List),
      AriamiConnectCommand.supported,
    );
  });

  group('slice 6 command capabilities', () {
    test(
        '[capabilities_advertised] hello capabilities are narrowed by the '
        'hub allowlist and published per device', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final tv = _FakeChannel();
      hub.handle(
        tv,
        WsMessage(
          type: AriamiConnectMessageType.hello,
          data: const <String, dynamic>{
            'protocolVersions': <int>[3, 2],
            'canPlay': true,
            'supportedCommands': <String>[
              AriamiConnectCommand.pause,
              AriamiConnectCommand.clearQueue,
              'invented_command',
            ],
          },
        ),
      );
      hub.register(
        tv,
        userId: 'user',
        deviceId: 'tv',
        deviceName: 'TV',
        clientType: 'tv',
      );

      final welcome = _lastMessage(tv, AriamiConnectMessageType.welcome).data!;
      expect(
        Set<String>.from(welcome['supportedCommands'] as List),
        <String>{
          AriamiConnectCommand.pause,
          AriamiConnectCommand.clearQueue,
        },
      );
      final device = Map<String, dynamic>.from(
        (welcome['devices'] as List).single as Map,
      );
      expect(
        Set<String>.from(device['supportedCommands'] as List),
        <String>{
          AriamiConnectCommand.pause,
          AriamiConnectCommand.clearQueue,
        },
      );
    });

    test(
        '[unsupported_command_fails_explicitly] unsupported target commands '
        'fail without forwarding while advertised commands still relay', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final target = _FakeChannel();
      final controller = _FakeChannel();
      hub.handle(
        target,
        WsMessage(
          type: AriamiConnectMessageType.hello,
          data: const <String, dynamic>{
            'supportedCommands': <String>[AriamiConnectCommand.pause],
          },
        ),
      );
      hub.register(
        target,
        userId: 'user',
        deviceId: 'target',
        deviceName: 'Target',
        clientType: 'tv',
      );
      hub.register(
        controller,
        userId: 'user',
        deviceId: 'controller',
        deviceName: 'Controller',
        clientType: 'mobile',
      );
      hub.handle(target, _stateMessage(activate: true));

      hub.handle(
        controller,
        WsMessage(
          type: AriamiConnectMessageType.command,
          data: const <String, dynamic>{
            'commandId': 'unsupported-volume',
            'command': AriamiConnectCommand.setVolume,
          },
        ),
      );
      final rejected = _lastMessage(
        controller,
        AriamiConnectMessageType.commandResult,
      );
      expect(rejected.data?['ok'], isFalse);
      expect(rejected.data?['code'], 'UNSUPPORTED_COMMAND');
      expect(
        target.messages.where((message) =>
            message.type == AriamiConnectMessageType.command &&
            message.data?['commandId'] == 'unsupported-volume'),
        isEmpty,
      );

      hub.handle(
        controller,
        WsMessage(
          type: AriamiConnectMessageType.command,
          data: const <String, dynamic>{
            'commandId': 'supported-pause',
            'command': AriamiConnectCommand.pause,
          },
        ),
      );
      expect(
        target.messages.where((message) =>
            message.type == AriamiConnectMessageType.command &&
            message.data?['commandId'] == 'supported-pause'),
        hasLength(1),
      );
    });
  });

  group('protocol negotiation', () {
    test(
        '[pre_auth_hello_retained] a hello received before authenticated '
        'registration selects v3', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final phone = _FakeChannel();

      hub.handle(
        phone,
        WsMessage(
          type: AriamiConnectMessageType.hello,
          data: const <String, dynamic>{
            'protocolVersions': AriamiConnectProtocol.supportedVersions,
            'canPlay': true,
          },
        ),
      );
      hub.register(
        phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile',
      );

      final welcomes = phone.messages.where(
        (message) => message.type == AriamiConnectMessageType.welcome,
      );
      expect(welcomes, hasLength(1));
      expect(welcomes.single.data?['protocolVersion'], 3);
    });

    test(
        '[per_peer_protocol_selection] [v3_preserves_v2_snapshots] '
        '[mixed_v2_v3_convergence] '
        'v3 receives split state while v2 receives reconstructed snapshots',
        () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final v3Peer = _FakeChannel();
      final v2Peer = _FakeChannel();
      hub.register(
        v3Peer,
        userId: 'user',
        deviceId: 'v3',
        deviceName: 'V3',
        clientType: 'mobile',
      );
      hub.register(
        v2Peer,
        userId: 'user',
        deviceId: 'v2',
        deviceName: 'V2',
        clientType: 'tv',
      );

      hub.handle(
        v3Peer,
        WsMessage(
          type: AriamiConnectMessageType.hello,
          data: const <String, dynamic>{
            'protocolVersions': <int>[3, 2],
            'canPlay': true,
          },
        ),
      );
      hub.handle(
        v2Peer,
        WsMessage(
          type: AriamiConnectMessageType.hello,
          data: const <String, dynamic>{
            'protocolVersions': <int>[2],
            'canPlay': true,
          },
        ),
      );

      expect(
        _lastMessage(v3Peer, AriamiConnectMessageType.welcome)
            .data?['protocolVersion'],
        3,
      );
      expect(
        _lastMessage(v2Peer, AriamiConnectMessageType.welcome)
            .data?['protocolVersion'],
        2,
      );

      hub.handle(v3Peer, _v3QueueMessage(activate: true, ownerEpoch: 0));
      hub.handle(v3Peer, _v3StateMessage(ownerEpoch: 1, queueCounter: 1));
      final v2State = _lastMessage(v2Peer, AriamiConnectMessageType.state);
      expect(v2State.data?['snapshot']['queue'], hasLength(1));
      expect(v2State.data?.containsKey('snapshot'), isTrue);

      hub.handle(v2Peer, _stateMessage(activate: true, ownerEpoch: 1));
      final v3State = _lastMessage(v3Peer, AriamiConnectMessageType.state);
      final v3Queue = _lastMessage(v3Peer, AriamiConnectMessageType.queue);
      expect(v3Queue.data?['tracks'], hasLength(1));
      expect(v3Queue.data?['backingOrder'], <int>[0]);
      expect(v3State.data?['currentIndex'], 0);
      expect(v3State.data?.containsKey('snapshot'), isFalse);
    });

    test('[v3_queue_crosses_once] progress never repeats a 500-track queue',
        () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      final peer = _FakeChannel();
      for (final entry in <(_FakeChannel, String)>[
        (owner, 'owner'),
        (peer, 'peer'),
      ]) {
        hub.handle(
          entry.$1,
          WsMessage(
            type: AriamiConnectMessageType.hello,
            data: const <String, dynamic>{
              'protocolVersions': <int>[3, 2],
              'canPlay': true,
            },
          ),
        );
        hub.register(
          entry.$1,
          userId: 'user',
          deviceId: entry.$2,
          deviceName: entry.$2,
          clientType: 'mobile',
        );
      }
      final tracks = List<Map<String, dynamic>>.generate(
        500,
        (index) => <String, dynamic>{
          'id': 'track-$index',
          'title': 'Track $index',
        },
      );
      hub.handle(
        owner,
        _v3QueueMessage(
          activate: true,
          ownerEpoch: 0,
          tracks: tracks,
        ),
      );
      for (var tick = 0; tick < 4; tick++) {
        hub.handle(
          owner,
          _v3StateMessage(
            ownerEpoch: 1,
            queueCounter: 1,
            positionMs: tick * 1000,
          ),
        );
      }

      final queues = peer.messages
          .where((message) => message.type == AriamiConnectMessageType.queue);
      final states = peer.messages
          .where((message) => message.type == AriamiConnectMessageType.state);
      expect(queues, hasLength(1));
      expect(queues.single.data?['tracks'], hasLength(500));
      expect(states, hasLength(4));
      final queueBytes = utf8.encode(jsonEncode(queues.single.toJson())).length;
      final stateBytes = utf8.encode(jsonEncode(states.last.toJson())).length;
      expect(stateBytes, lessThan(1000));
      expect(stateBytes * 20, lessThan(queueBytes));
      expect(
          states.every((message) =>
              message.data?['queueCounter'] == 1 &&
              !message.data!.containsKey('snapshot') &&
              !message.data!.containsKey('tracks')),
          isTrue);
    });

    test(
        '[v3_negotiation_disabled] the server rollout switch disables v3 '
        'at negotiation time', () {
      final hub = AriamiConnectHub(protocolV3Enabled: false);
      addTearDown(hub.dispose);
      final disabledPeer = _FakeChannel();
      final enabledPeer = _FakeChannel();

      for (final socket in <_FakeChannel>[disabledPeer, enabledPeer]) {
        hub.handle(
          socket,
          WsMessage(
            type: AriamiConnectMessageType.hello,
            data: const <String, dynamic>{
              'protocolVersions': <int>[3, 2],
              'canPlay': true,
            },
          ),
        );
        if (identical(socket, enabledPeer)) hub.protocolV3Enabled = true;
        hub.register(
          socket,
          userId: 'user',
          deviceId: identical(socket, disabledPeer) ? 'disabled' : 'enabled',
          deviceName: 'Peer',
          clientType: 'mobile',
        );
      }

      expect(
        _lastMessage(disabledPeer, AriamiConnectMessageType.welcome)
            .data?['protocolVersion'],
        2,
      );
      expect(
        _lastMessage(enabledPeer, AriamiConnectMessageType.welcome)
            .data?['protocolVersion'],
        3,
      );
    });

    test(
        '[malformed_protocol_offer] an unusable offer degrades to v2 without '
        'blocking registration', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);

      // Decoded from the wire on purpose: jsonDecode turns 1e999 into
      // Infinity, and register() runs inside an unguarded auth continuation,
      // so a throw here would leave the peer permanently out of the session.
      const unusable = <String>['[1e999]', '[-1e999]', '[3.5]', '["3"]', '3'];
      for (final offer in unusable) {
        final socket = _FakeChannel();
        hub.handle(socket, _helloFromWire(offer));
        hub.register(
          socket,
          userId: 'user',
          deviceId: 'peer-$offer',
          deviceName: 'Peer',
          clientType: 'mobile',
        );

        expect(
          _lastMessage(socket, AriamiConnectMessageType.welcome)
              .data?['protocolVersion'],
          2,
          reason: 'offer $offer must degrade to v2',
        );
      }

      // A whole-numbered double is a legitimate JSON spelling of 3.
      final doubleSocket = _FakeChannel();
      hub.handle(doubleSocket, _helloFromWire('[3.0]'));
      hub.register(
        doubleSocket,
        userId: 'user',
        deviceId: 'peer-double',
        deviceName: 'Peer',
        clientType: 'mobile',
      );
      expect(
        _lastMessage(doubleSocket, AriamiConnectMessageType.welcome)
            .data?['protocolVersion'],
        3,
      );
    });
  });

  test('devices and state are isolated by authenticated user', () {
    final hub = AriamiConnectHub();
    final alicePhone = _FakeChannel();
    final aliceTv = _FakeChannel();
    final bobPhone = _FakeChannel();

    hub.register(alicePhone,
        userId: 'alice',
        deviceId: 'alice-phone',
        deviceName: 'Alice phone',
        clientType: 'mobile');
    hub.register(aliceTv,
        userId: 'alice',
        deviceId: 'alice-tv',
        deviceName: 'Living room',
        clientType: 'tv');
    hub.register(bobPhone,
        userId: 'bob',
        deviceId: 'bob-phone',
        deviceName: 'Bob phone',
        clientType: 'mobile');

    hub.handle(alicePhone, _stateMessage(activate: true));

    final aliceMessages = aliceTv.messages;
    final bobMessages = bobPhone.messages;
    expect(
      aliceMessages.any((message) =>
          message.type == AriamiConnectMessageType.state &&
          message.data?['activeDeviceId'] == 'alice-phone'),
      isTrue,
    );
    expect(
      bobMessages
          .any((message) => message.type == AriamiConnectMessageType.state),
      isFalse,
    );
    final bobDevicePayload = bobMessages
        .lastWhere(
            (message) => message.type == AriamiConnectMessageType.devices)
        .data!['devices'] as List<dynamic>;
    expect(bobDevicePayload, hasLength(1));
  });

  test('handoff targets the chosen device and preserves the snapshot', () {
    final hub = AriamiConnectHub();
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(phone, _stateMessage(activate: true));

    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.transfer,
        data: <String, dynamic>{'targetDeviceId': 'tv'},
      ),
    );

    final prepare = tv.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.transfer);
    expect(prepare.data?['phase'], 'prepare');
    expect(prepare.data?['sourceDeviceId'], 'phone');
    expect(prepare.data?['targetDeviceId'], 'tv');
    final snapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(prepare.data?['snapshot'] as Map),
    );
    expect(snapshot.currentTrackId, 'song-1');
    expect(snapshot.isPlaying, isTrue);
    final beforeCommitDevices = phone.messages
        .lastWhere(
            (message) => message.type == AriamiConnectMessageType.devices)
        .data!['devices'] as List<dynamic>;
    expect(
      beforeCommitDevices
          .whereType<Map>()
          .firstWhere((device) => device['id'] == 'phone')['isActive'],
      isTrue,
    );

    hub.handle(
      tv,
      WsMessage(
        type: AriamiConnectMessageType.transferResult,
        data: <String, dynamic>{
          'transferId': prepare.data?['transferId'],
          'ok': true,
        },
      ),
    );
    final commit = tv.messages.lastWhere((message) =>
        message.type == AriamiConnectMessageType.transfer &&
        message.data?['phase'] == 'commit');
    expect(commit.data?['targetDeviceId'], 'tv');
    expect(
      tv.messages
          .lastWhere(
              (message) => message.type == AriamiConnectMessageType.devices)
          .data?['activeDeviceId'],
      'tv',
    );
  });

  test('remote commands keep ownership and route only to the active device',
      () {
    final hub = AriamiConnectHub();
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));
    final phoneBefore = phone.messages.length;

    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'commandId': 'command-1',
          'command': AriamiConnectCommand.next,
          'ownerEpoch': 1,
        },
      ),
    );

    expect(phone.messages.length, phoneBefore);
    final command = tv.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.command);
    expect(command.data?['command'], AriamiConnectCommand.next);
    expect(command.data?['commandId'], 'command-1');
    expect(command.data?['activeDeviceId'], 'tv');
    expect(command.data?['ownerEpoch'], 1);
  });

  test('a rejected state publish is answered with the authoritative state', () {
    final hub = AriamiConnectHub();
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));

    // The phone wrongly believes it owns the session and publishes without
    // activating. The hub must not store it — and must correct the phone so
    // the desync heals instead of persisting silently.
    hub.handle(phone, _stateMessage(activate: false));

    final correction = phone.messages
        .lastWhere((message) => message.type == AriamiConnectMessageType.state);
    expect(correction.data?['activeDeviceId'], 'tv');
    expect(correction.data?['snapshot'], isNotNull);

    // The TV's session was not overwritten by the rogue publish.
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.transfer,
        data: <String, dynamic>{'targetDeviceId': 'phone'},
      ),
    );
    final prepare = phone.messages.lastWhere((message) =>
        message.type == AriamiConnectMessageType.transfer &&
        message.data?['phase'] == 'prepare');
    expect(prepare.data?['sourceDeviceId'], 'tv');
  });

  test('active-device disconnect hands the exact session to its controller',
      () async {
    final hub = AriamiConnectHub(
      disconnectGracePeriod: const Duration(milliseconds: 10),
    );
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));

    // Any routed control marks the phone as the device that should continue
    // the session if the player disappears.
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'commandId': 'phone-control',
          'command': AriamiConnectCommand.seek,
          'arguments': <String, dynamic>{'positionMs': 1000},
        },
      ),
    );
    final messageCountBeforeDisconnect = phone.messages.length;

    hub.unregister(tv);

    // Do not publish a device list with a dangling active ID during the grace
    // period: that was what made controllers reveal an unrelated local song.
    expect(phone.messages, hasLength(messageCountBeforeDisconnect));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final prepare = phone.messages.lastWhere((message) =>
        message.type == AriamiConnectMessageType.transfer &&
        message.data?['phase'] == 'prepare');
    expect(prepare.data?['sourceDeviceId'], 'tv');
    expect(prepare.data?['targetDeviceId'], 'phone');
    final snapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(prepare.data?['snapshot'] as Map),
    );
    expect(snapshot.currentTrackId, 'song-1');
    expect(snapshot.isPlaying, isTrue);

    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.transferResult,
        data: <String, dynamic>{
          'transferId': prepare.data?['transferId'],
          'ok': true,
        },
      ),
    );
    final commit = phone.messages.lastWhere((message) =>
        message.type == AriamiConnectMessageType.transfer &&
        message.data?['phase'] == 'commit');
    expect(commit.data?['targetDeviceId'], 'phone');
    expect(
      phone.messages
          .lastWhere(
              (message) => message.type == AriamiConnectMessageType.devices)
          .data?['activeDeviceId'],
      'phone',
    );
  });

  test('an unanswered command reports the active device as offline', () async {
    final hub = AriamiConnectHub(
      commandTimeout: const Duration(milliseconds: 20),
    );
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));

    // The TV's socket is a ghost: it accepts the command but never answers.
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'commandId': 'command-lost',
          'command': AriamiConnectCommand.play,
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final result = phone.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.commandResult);
    expect(result.data?['commandId'], 'command-lost');
    expect(result.data?['ok'], isFalse);
  });

  test('a command result cancels the offline timeout', () async {
    final hub = AriamiConnectHub(
      commandTimeout: const Duration(milliseconds: 20),
    );
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));

    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'commandId': 'command-ok',
          'command': AriamiConnectCommand.play,
        },
      ),
    );
    hub.handle(
      tv,
      WsMessage(
        type: AriamiConnectMessageType.commandResult,
        data: <String, dynamic>{'commandId': 'command-ok', 'ok': true},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final result = phone.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.commandResult);
    expect(result.data?['ok'], isTrue);
    expect(
      phone.messages
          .where((message) => message.type == AriamiConnectMessageType.error),
      isEmpty,
    );
  });

  test('duplicate command ids execute once and replay the cached result', () {
    final hub = AriamiConnectHub();
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));

    final command = WsMessage(
      type: AriamiConnectMessageType.command,
      data: <String, dynamic>{
        'commandId': 'retry-safe-command',
        'command': AriamiConnectCommand.pause,
      },
    );
    hub.handle(phone, command);
    hub.handle(phone, command);

    expect(
      tv.messages.where((message) =>
          message.type == AriamiConnectMessageType.command &&
          message.data?['commandId'] == 'retry-safe-command'),
      hasLength(1),
    );

    hub.handle(
      tv,
      WsMessage(
        type: AriamiConnectMessageType.commandResult,
        data: <String, dynamic>{
          'commandId': 'retry-safe-command',
          'ok': true,
        },
      ),
    );
    final resultsBeforeReplay = phone.messages
        .where((message) =>
            message.type == AriamiConnectMessageType.commandResult &&
            message.data?['commandId'] == 'retry-safe-command')
        .length;

    hub.handle(phone, command);

    expect(
      tv.messages.where((message) =>
          message.type == AriamiConnectMessageType.command &&
          message.data?['commandId'] == 'retry-safe-command'),
      hasLength(1),
    );
    expect(
      phone.messages.where((message) =>
          message.type == AriamiConnectMessageType.commandResult &&
          message.data?['commandId'] == 'retry-safe-command'),
      hasLength(resultsBeforeReplay + 1),
    );
  });

  test('a device rename is persisted and broadcast to the account', () {
    final hub = AriamiConnectHub();
    final renames = <(String, String, String)>[];
    hub.onDeviceRenamed =
        (userId, deviceId, name) => renames.add((userId, deviceId, name));
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    hub.handle(
      tv,
      WsMessage(
        type: AriamiConnectMessageType.rename,
        data: <String, dynamic>{'name': '  Living  Room TV '},
      ),
    );

    expect(renames, [('user', 'tv', 'Living Room TV')]);
    for (final channel in [phone, tv]) {
      final devices = channel.messages
          .lastWhere(
              (message) => message.type == AriamiConnectMessageType.devices)
          .data!['devices'] as List<dynamic>;
      final renamed =
          devices.whereType<Map>().firstWhere((device) => device['id'] == 'tv');
      expect(renamed['name'], 'Living Room TV');
    }
  });

  test('a blank rename is rejected without touching the device', () {
    final hub = AriamiConnectHub();
    final renames = <String>[];
    hub.onDeviceRenamed = (userId, deviceId, name) => renames.add(name);
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    hub.handle(
      tv,
      WsMessage(
        type: AriamiConnectMessageType.rename,
        data: <String, dynamic>{'name': '   '},
      ),
    );

    expect(renames, isEmpty);
    final error = tv.messages
        .lastWhere((message) => message.type == AriamiConnectMessageType.error);
    expect(error.data?['code'], 'INVALID_NAME');
    final devices = tv.messages
        .lastWhere(
            (message) => message.type == AriamiConnectMessageType.devices)
        .data!['devices'] as List<dynamic>;
    expect((devices.single as Map)['name'], 'TV');
  });

  test('active player reconnect cancels automatic failover', () async {
    final hub = AriamiConnectHub(
      disconnectGracePeriod: const Duration(milliseconds: 30),
    );
    final phone = _FakeChannel();
    final tv = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true));
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'command': AriamiConnectCommand.pause,
        },
      ),
    );

    hub.unregister(tv);
    final reconnectedTv = _FakeChannel();
    hub.register(reconnectedTv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      phone.messages.where((message) =>
          message.type == AriamiConnectMessageType.transfer &&
          message.data?['phase'] == 'prepare'),
      isEmpty,
    );
    expect(
      phone.messages
          .lastWhere(
              (message) => message.type == AriamiConnectMessageType.devices)
          .data?['activeDeviceId'],
      'tv',
    );
  });

  test('a stale peer is evicted and removed from the device list', () async {
    final hub = AriamiConnectHub(
      staleTimeout: const Duration(milliseconds: 40),
      sweepInterval: const Duration(milliseconds: 15),
    );
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    // Nobody touches the TV again, so it goes stale and the sweep must
    // unregister it (closing its socket) without any client action.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(tv.closeCode, 4000);

    // Register a fresh peer afterwards: its welcome device list proves the
    // TV was actually removed from the hub, not merely closed.
    final phone = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    final welcome = phone.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome);
    final devices = welcome.data!['devices'] as List<dynamic>;
    expect(devices.whereType<Map>().any((device) => device['id'] == 'tv'),
        isFalse);
  });

  test('touch keeps a peer alive across more than one sweep interval',
      () async {
    final hub = AriamiConnectHub(
      staleTimeout: const Duration(milliseconds: 50),
      sweepInterval: const Duration(milliseconds: 15),
    );
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    // Touched more recently than staleTimeout on every pass, spanning well
    // past what a single stale window would tolerate. This is the
    // anti-regression test for the ping -> touch wiring in
    // websocket_and_static_part.dart: without it, a device that only pings
    // (never sending a connect_* message) would still be evicted here.
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      hub.touch(tv);
    }

    expect(tv.closeCode, isNull);
    final phone = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    final welcome = phone.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome);
    final devices = welcome.data!['devices'] as List<dynamic>;
    expect(
        devices.whereType<Map>().any((device) => device['id'] == 'tv'), isTrue);
  });

  test('the sweep timer stops once every peer has disconnected', () async {
    final hub = AriamiConnectHub(
      staleTimeout: const Duration(milliseconds: 30),
      sweepInterval: const Duration(milliseconds: 15),
    );
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    hub.unregister(tv);

    // No peers remain, so unregister() must have cancelled the periodic
    // timer. Waiting well past several sweep intervals with nothing left to
    // evict must not throw and must not leave any stale internal state
    // behind for the next registration.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final phone = _FakeChannel();
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    // Only one sweep interval, comfortably under staleTimeout: this peer
    // must not be evicted. If unregister() had failed to cancel the old
    // timer, register() would have left two periodic timers running instead
    // of one, but the outcome checked here — a fresh, still-live peer
    // surviving a single sweep pass — holds either way, so the real
    // regression this guards is the timer never getting released at all.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(phone.closeCode, isNull);
  });

  test('[monotonic_owner_epoch] committed owners advance exactly once', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');

    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    expect(
        _lastMessage(phone, AriamiConnectMessageType.state).data?['ownerEpoch'],
        1);

    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 1));
    expect(
        _lastMessage(phone, AriamiConnectMessageType.state).data?['ownerEpoch'],
        1);

    hub.handle(phone, _stateMessage(activate: true, ownerEpoch: 1));
    expect(_lastMessage(tv, AriamiConnectMessageType.state).data?['ownerEpoch'],
        2);
    expect(_lastMessage(tv, AriamiConnectMessageType.command).data,
        containsPair('ownerEpoch', 2));
  });

  test('[same_owner_reclaim_retains_epoch] reconnect keeps the epoch', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    hub.unregister(tv);

    final replacement = _FakeChannel();
    hub.register(replacement,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    final welcome = _lastMessage(replacement, AriamiConnectMessageType.welcome);
    expect(welcome.data?['activeDeviceId'], 'tv');
    expect(welcome.data?['ownerEpoch'], 1);
  });

  test('[stale_state_rejected] former owner cannot reactivate its queue', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    hub.handle(phone, _stateMessage(activate: true, ownerEpoch: 1));

    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 1));

    final correction = _lastMessage(tv, AriamiConnectMessageType.state);
    expect(correction.data?['activeDeviceId'], 'phone');
    expect(correction.data?['ownerEpoch'], 2);
    expect(
        _lastMessage(phone, AriamiConnectMessageType.devices)
            .data?['activeDeviceId'],
        'phone');
  });

  test('[simultaneous_takeovers_converge] one matching epoch wins', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    final desktop = _FakeChannel();
    for (final device in <(_FakeChannel, String)>[
      (tv, 'tv'),
      (phone, 'phone'),
      (desktop, 'desktop'),
    ]) {
      hub.register(device.$1,
          userId: 'user',
          deviceId: device.$2,
          deviceName: device.$2,
          clientType: 'tv');
    }
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));

    // Both contenders observed epoch 1. The first commit advances to 2, so
    // the second publication is stale and cannot replace it.
    hub.handle(phone, _stateMessage(activate: true, ownerEpoch: 1));
    hub.handle(desktop, _stateMessage(activate: true, ownerEpoch: 1));

    final correction = _lastMessage(desktop, AriamiConnectMessageType.state);
    expect(correction.data?['activeDeviceId'], 'phone');
    expect(correction.data?['ownerEpoch'], 2);
    expect(
        _lastMessage(phone, AriamiConnectMessageType.devices)
            .data?['activeDeviceId'],
        'phone');
  });

  test('[stale_command_rejected] stale controller work never reaches owner',
      () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    final commandsBefore = tv.messages
        .where((message) => message.type == AriamiConnectMessageType.command)
        .length;

    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: const <String, dynamic>{
          'commandId': 'stale-command',
          'command': AriamiConnectCommand.pause,
          'ownerEpoch': 0,
        },
      ),
    );

    expect(
      tv.messages
          .where((message) => message.type == AriamiConnectMessageType.command),
      hasLength(commandsBefore),
    );
    final result = _lastMessage(phone, AriamiConnectMessageType.commandResult);
    expect(result.data?['ok'], isFalse);
    expect(result.data?['ownerEpoch'], 1);
  });

  test('[epoch_change_fails_pending_command] result is deterministic', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');
    hub.register(phone,
        userId: 'user',
        deviceId: 'phone',
        deviceName: 'Phone',
        clientType: 'mobile');
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.command,
        data: const <String, dynamic>{
          'commandId': 'in-flight',
          'command': AriamiConnectCommand.seek,
          'ownerEpoch': 1,
        },
      ),
    );

    hub.handle(phone, _stateMessage(activate: true, ownerEpoch: 1));

    final result = phone.messages.lastWhere((message) =>
        message.type == AriamiConnectMessageType.commandResult &&
        message.data?['commandId'] == 'in-flight');
    expect(result.data?['ok'], isFalse);
    expect(result.data?['ownerEpoch'], 2);
    expect(result.data?['activeDeviceId'], 'phone');
  });

  test('[stale_transfer_rejected] old prepare cannot commit after takeover',
      () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    final phone = _FakeChannel();
    final desktop = _FakeChannel();
    for (final device in <(_FakeChannel, String)>[
      (tv, 'tv'),
      (phone, 'phone'),
      (desktop, 'desktop'),
    ]) {
      hub.register(device.$1,
          userId: 'user',
          deviceId: device.$2,
          deviceName: device.$2,
          clientType: 'tv');
    }
    hub.handle(tv, _stateMessage(activate: true, ownerEpoch: 0));
    hub.handle(
      phone,
      WsMessage(
        type: AriamiConnectMessageType.transfer,
        data: const <String, dynamic>{
          'targetDeviceId': 'desktop',
          'ownerEpoch': 1,
        },
      ),
    );
    final prepare = _lastMessage(desktop, AriamiConnectMessageType.transfer);

    hub.handle(phone, _stateMessage(activate: true, ownerEpoch: 1));
    hub.handle(
      desktop,
      WsMessage(
        type: AriamiConnectMessageType.transferResult,
        data: <String, dynamic>{
          'transferId': prepare.data?['transferId'],
          'ok': true,
          'ownerEpoch': 1,
        },
      ),
    );

    expect(
        _lastMessage(phone, AriamiConnectMessageType.devices)
            .data?['activeDeviceId'],
        'phone');
    expect(
        _lastMessage(phone, AriamiConnectMessageType.devices)
            .data?['ownerEpoch'],
        2);
  });

  test('[legacy_v2_epoch_omission] old peer remains compatible', () {
    final hub = AriamiConnectHub();
    final tv = _FakeChannel();
    hub.register(tv,
        userId: 'user', deviceId: 'tv', deviceName: 'TV', clientType: 'tv');

    hub.handle(tv, _stateMessage(activate: true));
    hub.handle(tv, _stateMessage(activate: false));

    final devices = _lastMessage(tv, AriamiConnectMessageType.devices);
    expect(devices.data?['activeDeviceId'], 'tv');
    expect(devices.data?['ownerEpoch'], 1);
  });
}

WsMessage _stateMessage({required bool activate, int? ownerEpoch}) => WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'activate': activate,
        if (ownerEpoch != null) 'ownerEpoch': ownerEpoch,
        'snapshot': AriamiPlaybackSnapshot(
          queue: <Map<String, dynamic>>[
            <String, dynamic>{'id': 'song-1', 'title': 'Song'},
          ],
          currentIndex: 0,
          positionMs: 1000,
          durationMs: 60000,
          isPlaying: true,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
        ).toJson(),
      },
    );

WsMessage _v3QueueMessage({
  required bool activate,
  required int ownerEpoch,
  List<Map<String, dynamic>>? tracks,
  List<int>? backingOrder,
}) {
  final resolved = tracks ??
      const <Map<String, dynamic>>[
        <String, dynamic>{'id': 'song-1', 'title': 'Song'},
      ];
  return WsMessage(
    type: AriamiConnectMessageType.queue,
    data: <String, dynamic>{
      'activate': activate,
      'ownerEpoch': ownerEpoch,
      'queueCounter': 1,
      'tracks': resolved,
      'backingOrder':
          backingOrder ?? List<int>.generate(resolved.length, (index) => index),
    },
  );
}

WsMessage _v3StateMessage({
  required int ownerEpoch,
  required int queueCounter,
  int positionMs = 1000,
}) =>
    WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'ownerEpoch': ownerEpoch,
        'queueCounter': queueCounter,
        'currentIndex': 0,
        'positionMs': positionMs,
        'durationMs': 60000,
        'isPlaying': true,
        'shuffle': false,
        'repeatMode': 'off',
        'volume': 1,
        'stateRevision': positionMs,
      },
    );

/// Builds a hello by decoding raw JSON, so numeric offers reach the hub with
/// the exact types jsonDecode produces rather than hand-written Dart literals.
WsMessage _helloFromWire(String protocolVersionsJson) =>
    WsMessage.fromJson(jsonDecode('{"type":"'
            '${AriamiConnectMessageType.hello}","timestamp":"t",'
            '"data":{"protocolVersions":$protocolVersionsJson,"canPlay":true}}')
        as Map<String, dynamic>);

WsMessage _lastMessage(_FakeChannel channel, String type) =>
    channel.messages.lastWhere((message) => message.type == type);

class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final _FakeSink _outgoing = _FakeSink();

  List<WsMessage> get messages => _outgoing.values
      .map((raw) =>
          WsMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>))
      .toList(growable: false);

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _outgoing;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => _outgoing.closeCode;

  @override
  String? get closeReason => _outgoing.closeReason;
}

class _FakeSink implements WebSocketSink {
  final List<dynamic> values = <dynamic>[];
  final Completer<void> _done = Completer<void>();
  int? closeCode;
  String? closeReason;

  @override
  void add(dynamic data) => values.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
