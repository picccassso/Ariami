import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
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

  test('remote commands are routed only to the active device', () {
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
          'command': AriamiConnectCommand.pause,
        },
      ),
    );

    expect(phone.messages.length, phoneBefore);
    final command = tv.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.command);
    expect(command.data?['command'], AriamiConnectCommand.pause);
    expect(command.data?['commandId'], 'command-1');
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

    final error = phone.messages
        .lastWhere((message) => message.type == AriamiConnectMessageType.error);
    expect(error.data?['code'], 'DEVICE_OFFLINE');
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
      final renamed = devices
          .whereType<Map>()
          .firstWhere((device) => device['id'] == 'tv');
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
}

WsMessage _stateMessage({required bool activate}) => WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'activate': activate,
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
