import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../tool/connect_p0_baseline.dart';

void main() {
  group('P0 contract and measurements', () {
    test('one shared v2 fixture covers all four independent clients', () {
      final fixture = _readFixture('v2_contract.json');
      expect(fixture['protocolVersion'], 2);
      final ownership = Map<String, dynamic>.from(fixture['ownership'] as Map);
      expect(ownership['ownerEpoch'], 7);
      expect(ownership['staleOwnerEpoch'], lessThan(ownership['ownerEpoch']));
      final clients =
          Map<String, dynamic>.from(fixture['clientBaselines'] as Map);
      expect(
        clients.keys,
        containsAll(<String>[
          'mobile',
          'premiumDesktop',
          'flutterTv',
          'nativeTvos',
        ]),
      );
      final snapshot = AriamiPlaybackSnapshot.fromJson(
        Map<String, dynamic>.from(fixture['snapshot'] as Map),
      );
      expect(snapshot.queue.map((track) => track['id']),
          <String>['track-a', 'track-b', 'track-a']);
      expect(snapshot.currentTrackId, 'track-b');
      expect(snapshot.shuffle, isTrue);
      expect(snapshot.repeatMode, 'all');

      final playContext =
          Map<String, dynamic>.from(fixture['playContext'] as Map);
      final playData = Map<String, dynamic>.from(playContext['data'] as Map);
      final arguments = Map<String, dynamic>.from(playData['arguments'] as Map);
      final playSnapshot = AriamiPlaybackSnapshot.fromJson(
        Map<String, dynamic>.from(arguments['snapshot'] as Map),
      );
      expect(playData['command'], AriamiConnectCommand.playContext);
      expect(playData['ownerEpoch'], ownership['ownerEpoch']);
      expect(playSnapshot.queue.map((track) => track['id']),
          <String>['track-a', 'track-b', 'track-a']);

      // Decode the shared connect_queue through the real wire decoder.
      // Re-indexing the fixture's own arrays would pass even against a
      // decoder that dropped backingOrder entirely.
      final v3Queue = Map<String, dynamic>.from(fixture['v3Queue'] as Map);
      final queueData = Map<String, dynamic>.from(v3Queue['data'] as Map);
      final queueSnapshot =
          AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        'queue': queueData['tracks'],
        'backingOrder': queueData['backingOrder'],
        'sourceId': queueData['sourceId'],
        'shuffle': true,
      });
      expect(queueSnapshot.backingOrder, <int>[2, 0, 1]);
      expect(queueSnapshot.sourceId, 'playlist:shared-fixture');
      expect(
        queueSnapshot.queue.map((track) => track['id']),
        <String>['track-a', 'track-b', 'track-a'],
        reason: 'the wire carries resolved play order',
      );
      expect(
        queueSnapshot.backingOrder
            .map((index) => queueSnapshot.queue[index]['title']),
        <String>['First Track (Encore)', 'First Track', 'Second Track'],
      );
    });

    test('fault matrix covers every later slice with named failure modes', () {
      final matrix = _readFixture('fault_matrix.json');
      final slices = (matrix['slices'] as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(growable: false);
      expect(slices.map((entry) => entry['slice']),
          List<int>.generate(9, (i) => i + 2));
      expect(
        slices.every((entry) =>
            ((entry['probe'] as String?)?.isNotEmpty == true ||
                (entry['probes'] as List<dynamic>?)?.isNotEmpty == true) &&
            (entry['failureModes'] as List<dynamic>).isNotEmpty),
        isTrue,
      );
      expect(
        slices.skip(4).map((entry) => entry['probe']).toSet(),
        hasLength(5),
      );

      final slice2 = slices.first;
      final slice3 = slices[1];
      final slice4 = slices[2];
      expect(slice2['coverage'], 'complete');
      expect(slice3['coverage'], 'complete');
      expect(slice4['coverage'], 'complete');
      expect(slices[3]['coverage'], 'complete');
      expect(
        slices.skip(4).every((entry) => entry['coverage'] == 'representative'),
        isTrue,
      );
      final probes = (slice2['probes'] as List<dynamic>).cast<String>();
      final modes = (slice2['failureModes'] as List<dynamic>)
          .map((mode) => Map<String, dynamic>.from(mode as Map))
          .toList(growable: false);
      expect(modes.map((mode) => mode['probe']).toSet(), probes.toSet());
      final source =
          _readCoreTestSource('connect_client_fault_baseline_test.dart');
      for (final probe in probes) {
        expect(source, contains('[$probe]'), reason: 'Missing probe $probe');
      }
      final slice3Probes = (slice3['probes'] as List<dynamic>).cast<String>();
      final slice3Modes = (slice3['failureModes'] as List<dynamic>)
          .map((mode) => Map<String, dynamic>.from(mode as Map))
          .toList(growable: false);
      expect(slice3Modes.map((mode) => mode['probe']).toSet(),
          slice3Probes.toSet());
      final slice3Source = <String>[
        _readCoreTestSource('connect_hub_test.dart'),
        _readCoreTestSource('connect_client_fault_baseline_test.dart'),
      ].join('\n');
      for (final probe in slice3Probes) {
        expect(slice3Source, contains('[$probe]'),
            reason: 'Missing probe $probe');
      }
      final slice4Probes = (slice4['probes'] as List<dynamic>).cast<String>();
      final slice4Modes = (slice4['failureModes'] as List<dynamic>)
          .map((mode) => Map<String, dynamic>.from(mode as Map))
          .toList(growable: false);
      expect(slice4Modes.map((mode) => mode['probe']).toSet(),
          slice4Probes.toSet());
      final slice4Source = <String>[
        _readCoreTestSource('connect_hub_test.dart'),
        _readCoreTestSource('connect_client_fault_baseline_test.dart'),
      ].join('\n');
      for (final probe in slice4Probes) {
        expect(slice4Source, contains('[$probe]'),
            reason: 'Missing probe $probe');
      }
      final slice5 = slices[3];
      final slice5Probes = (slice5['probes'] as List<dynamic>).cast<String>();
      final slice5Modes = (slice5['failureModes'] as List<dynamic>)
          .map((mode) => Map<String, dynamic>.from(mode as Map))
          .toList(growable: false);
      expect(slice5Modes.map((mode) => mode['probe']).toSet(),
          slice5Probes.toSet());
      final slice5Source = <String>[
        _readCoreTestSource('connect_hub_test.dart'),
        _readCoreTestSource('connect_client_fault_baseline_test.dart'),
        File('test/models/connect_models_test.dart').readAsStringSync(),
      ].join('\n');
      for (final probe in slice5Probes) {
        expect(slice5Source, contains('[$probe]'),
            reason: 'Missing probe $probe');
      }
    });

    test('measurements are deterministic and retain the v2 full-queue cost',
        () {
      final first = buildConnectP0Measurements();
      final second = buildConnectP0Measurements();
      expect(first, second);
      expect(first, _readFixture('p0_measurements.json'));
      final statePublish = Map<String, dynamic>.from(
        first['representative500TrackStatePublish'] as Map,
      );
      final minute = Map<String, dynamic>.from(
        first['representative500TrackOneMinuteAt1Hz'] as Map,
      );
      expect(statePublish['messageCount'], 3);
      expect(minute['messageCount'], 180);
      expect(
        minute['totalBytes'],
        (statePublish['totalBytes'] as int) * 60,
      );
      final maximum =
          Map<String, dynamic>.from(first['realisticMaximum'] as Map);
      expect(
        maximum['playContextCommandBytes'],
        greaterThan(maximum['snapshotJsonBytes'] as int),
      );
    });

    test('P0 byte counts retain an explicit owner-epoch overhead', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      final firstPeer = _FakeChannel();
      final secondPeer = _FakeChannel();
      _register(hub, owner, 'active-device');
      _register(hub, firstPeer, 'first-peer');
      _register(hub, secondPeer, 'second-peer');
      owner.rawMessages.clear();
      firstPeer.rawMessages.clear();
      secondPeer.rawMessages.clear();

      final publication = WsMessage(
        type: AriamiConnectMessageType.state,
        data: <String, dynamic>{
          'activate': false,
          'snapshot':
              buildConnectP0Snapshot(500, largeMetadata: false).toJson(),
        },
        timestamp: connectP0WireTimestamp,
      );
      final publicationBytes =
          utf8.encode(jsonEncode(publication.toJson())).length;
      hub.handle(owner, publication);

      final expected = Map<String, dynamic>.from(
        buildConnectP0Measurements()['representative500TrackStatePublish']
            as Map,
      );
      expect(owner.rawMessages, isEmpty);
      expect(firstPeer.rawMessages, hasLength(1));
      expect(secondPeer.rawMessages, hasLength(1));
      final firstPeerBytes = _canonicalWireBytes(firstPeer.rawMessages.single);
      final secondPeerBytes =
          _canonicalWireBytes(secondPeer.rawMessages.single);
      final ownerEpochBytes = utf8.encode(',"ownerEpoch":1').length;
      expect(publicationBytes, expected['ownerPublicationBytes']);
      expect(firstPeerBytes,
          (expected['eachPeerBroadcastBytes'] as int) + ownerEpochBytes);
      expect(
        publicationBytes + firstPeerBytes + secondPeerBytes,
        (expected['totalBytes'] as int) + (ownerEpochBytes * 2),
      );
    });
  });

  group('P0 deterministic fault characterizations', () {
    test('slice 2: old socket teardown cannot remove its replacement', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final observer = _FakeChannel();
      final oldSocket = _FakeChannel();
      final replacement = _FakeChannel();
      _register(hub, observer, 'observer');
      _register(hub, oldSocket, 'player');
      _register(hub, replacement, 'player');

      hub.unregister(oldSocket);

      final devices = _lastDevices(observer);
      expect(
        devices.where((device) => device['id'] == 'player'),
        hasLength(1),
      );
      expect(oldSocket.closeCode, 4000);
    });

    test('slice 3: stale former-owner activation is fenced', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final tv = _FakeChannel();
      final phone = _FakeChannel();
      _register(hub, tv, 'tv');
      _register(hub, phone, 'phone');
      hub.handle(tv, _state(activate: true, trackId: 'tv-old', ownerEpoch: 0));
      hub.handle(phone,
          _state(activate: true, trackId: 'phone-current', ownerEpoch: 1));

      hub.handle(
          tv, _state(activate: true, trackId: 'tv-stale', ownerEpoch: 1));

      expect(
          _lastDevices(phone).firstWhere(
            (device) => device['id'] == 'tv',
          )['isActive'],
          isFalse);
      expect(
          _lastState(tv).data?['snapshot']['queue'][0]['id'], 'phone-current');
      expect(_lastState(tv).data?['ownerEpoch'], 2);
    });

    test('slice 4: a v3 hello negotiates v3 with v2 state semantics', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final socket = _FakeChannel();
      _register(hub, socket, 'client');
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

      final welcome = socket.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome,
      );
      expect(welcome.data?['protocolVersion'], 3);
      expect(welcome.data?.containsKey('snapshot'), isFalse);
    });

    test('slice 5: a position tick repeats the complete 500-track queue', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      final peer = _FakeChannel();
      _register(hub, owner, 'owner');
      _register(hub, peer, 'peer');
      hub.handle(owner, _state(activate: true, queueLength: 500));
      final firstBytes = _lastStateRaw(peer).length;
      final firstQueueBytes =
          jsonEncode(_lastState(peer).data?['snapshot']['queue']).length;

      hub.handle(owner, _state(positionMs: 1000, queueLength: 500));

      final tick = _lastState(peer);
      expect(tick.data?['snapshot']['queue'], hasLength(500));
      expect(
        jsonEncode(tick.data?['snapshot']['queue']).length,
        firstQueueBytes,
      );
      expect((_lastStateRaw(peer).length - firstBytes).abs(), lessThan(8));
    });

    test('slice 6: welcome has no per-client command capabilities', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final socket = _FakeChannel();
      _register(hub, socket, 'native-tvos');
      final welcome = socket.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome,
      );

      expect(welcome.data?.containsKey('supportedCommands'), isFalse);
      expect(AriamiConnectCommand.supported,
          contains(AriamiConnectCommand.clearQueue));
    });

    test('slice 7: target replacement does not redeliver retained command',
        () async {
      final hub = AriamiConnectHub(
        commandTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      final requester = _FakeChannel();
      _register(hub, owner, 'owner');
      _register(hub, requester, 'requester');
      hub.handle(owner, _state(activate: true));
      hub.handle(
        requester,
        WsMessage(
          type: AriamiConnectMessageType.command,
          data: const <String, dynamic>{
            'commandId': 'replace-target-command',
            'command': AriamiConnectCommand.pause,
          },
        ),
      );
      final replacement = _FakeChannel();
      _register(hub, replacement, 'owner');

      expect(
        replacement.messages.where(
          (message) => message.type == AriamiConnectMessageType.command,
        ),
        isEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final result = requester.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.commandResult,
      );
      expect(result.data?['ok'], isFalse);
    });

    test('slice 8: handoff commit overwrites a concurrent owner pause', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      final target = _FakeChannel();
      _register(hub, owner, 'owner');
      _register(hub, target, 'target');
      hub.handle(owner, _state(activate: true, isPlaying: true));
      hub.handle(
        owner,
        WsMessage(
          type: AriamiConnectMessageType.transfer,
          data: const <String, dynamic>{'targetDeviceId': 'target'},
        ),
      );
      final prepare = target.messages.lastWhere(
        (message) =>
            message.type == AriamiConnectMessageType.transfer &&
            message.data?['phase'] == 'prepare',
      );
      hub.handle(owner, _state(isPlaying: false, positionMs: 9000));
      hub.handle(
        target,
        WsMessage(
          type: AriamiConnectMessageType.transferResult,
          data: <String, dynamic>{
            'transferId': prepare.data?['transferId'],
            'ok': true,
          },
        ),
      );

      final commit = target.messages.lastWhere(
        (message) =>
            message.type == AriamiConnectMessageType.transfer &&
            message.data?['phase'] == 'commit',
      );
      expect(commit.data?['snapshot']['isPlaying'], isTrue);
      expect(commit.data?['snapshot']['positionMs'], isNot(9000));
    });

    test('slice 9: an uncontrolled recent peer inherits playing state',
        () async {
      final hub = AriamiConnectHub(
        disconnectGracePeriod: const Duration(milliseconds: 5),
      );
      addTearDown(hub.dispose);
      final candidate = _FakeChannel();
      final owner = _FakeChannel();
      _register(hub, candidate, 'candidate');
      _register(hub, owner, 'owner');
      hub.handle(owner, _state(activate: true, isPlaying: true));

      hub.unregister(owner);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prepare = candidate.messages.lastWhere(
        (message) =>
            message.type == AriamiConnectMessageType.transfer &&
            message.data?['phase'] == 'prepare',
      );
      expect(prepare.data?['snapshot']['isPlaying'], isTrue);
    });

    test('slice 10: an empty hub retains the previous account session', () {
      final hub = AriamiConnectHub();
      addTearDown(hub.dispose);
      final owner = _FakeChannel();
      _register(hub, owner, 'owner');
      hub.handle(owner, _state(activate: true));
      hub.unregister(owner);
      final returning = _FakeChannel();
      _register(hub, returning, 'returning');

      final welcome = returning.messages.lastWhere(
        (message) => message.type == AriamiConnectMessageType.welcome,
      );
      expect(welcome.data?['activeDeviceId'], 'owner');
      expect(welcome.data?['snapshot'], isNotNull);
    });
  });
}

/// Measures a hub-sent message against [connectP0WireTimestamp].
///
/// The hub stamps every message with `DateTime.now()`, and Dart's ISO-8601
/// form drops the microsecond triple whenever the microsecond component is
/// zero. Counting raw bytes would therefore come up three short about once in
/// a thousand runs. Normalizing only the timestamp width keeps the payload
/// itself honestly measured.
int _canonicalWireBytes(String raw) {
  final stamped =
      (jsonDecode(raw) as Map<String, dynamic>)['timestamp'] as String;
  return utf8.encode(raw).length +
      (connectP0WireTimestamp.length - stamped.length);
}

Map<String, dynamic> _readFixture(String name) {
  final files = <File>[
    File('${Directory.current.path}/test/fixtures/connect/$name'),
    File('${Directory.current.path}/ariami_core/test/fixtures/connect/$name'),
  ];
  for (final file in files) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError('Cannot find shared Connect fixture $name');
}

String _readCoreTestSource(String name) {
  final files = <File>[
    File('${Directory.current.path}/test/services/connect/$name'),
    File(
      '${Directory.current.path}/ariami_core/test/services/connect/$name',
    ),
  ];
  for (final file in files) {
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError('Cannot find Core Connect test $name');
}

void _register(
  AriamiConnectHub hub,
  _FakeChannel socket,
  String deviceId,
) {
  hub.register(
    socket,
    userId: 'user',
    deviceId: deviceId,
    deviceName: deviceId,
    clientType: 'tv',
  );
}

WsMessage _state({
  bool activate = false,
  String trackId = 'track',
  int queueLength = 1,
  int positionMs = 0,
  bool isPlaying = true,
  int? ownerEpoch,
}) =>
    WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'activate': activate,
        if (ownerEpoch != null) 'ownerEpoch': ownerEpoch,
        'snapshot': AriamiPlaybackSnapshot(
          queue: List<Map<String, dynamic>>.generate(
            queueLength,
            (index) => <String, dynamic>{
              'id': queueLength == 1 ? trackId : '$trackId-$index',
              'title': 'Track $index',
              'artist': 'Artist',
            },
            growable: false,
          ),
          currentIndex: 0,
          positionMs: positionMs,
          durationMs: 60000,
          isPlaying: isPlaying,
          shuffle: false,
          repeatMode: 'off',
          volume: 1,
          updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        ).toJson(),
      },
    );

List<Map<String, dynamic>> _lastDevices(_FakeChannel channel) =>
    (channel.messages
            .lastWhere(
              (message) => message.type == AriamiConnectMessageType.devices,
            )
            .data?['devices'] as List<dynamic>)
        .map((device) => Map<String, dynamic>.from(device as Map))
        .toList(growable: false);

WsMessage _lastState(_FakeChannel channel) => channel.messages.lastWhere(
      (message) => message.type == AriamiConnectMessageType.state,
    );

String _lastStateRaw(_FakeChannel channel) => channel.rawMessages.lastWhere(
      (raw) =>
          (jsonDecode(raw) as Map<String, dynamic>)['type'] ==
          AriamiConnectMessageType.state,
    );

class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamChannelController<dynamic> _controller =
      StreamChannelController<dynamic>();
  final List<String> rawMessages = <String>[];
  int? _closeCode;

  List<WsMessage> get messages => rawMessages
      .map(
        (raw) => WsMessage.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);

  @override
  Stream<dynamic> get stream => _controller.local.stream;

  @override
  WebSocketSink get sink => _FakeSink(
        onAdd: (data) => rawMessages.add(data as String),
        onClose: (code) => _closeCode = code,
      );

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink({required this.onAdd, required this.onClose});

  final void Function(dynamic data) onAdd;
  final void Function(int? code) onClose;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) => onAdd(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    onClose(closeCode);
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
