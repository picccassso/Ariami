import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/discovery/discovery_protocol.dart';
import 'package:ariami_core/services/discovery/discovery_responder.dart';
import 'package:ariami_core/services/discovery/dns_wire.dart';
import 'package:test/test.dart';

void main() {
  group('beacon protocol', () {
    test('probe payload is recognized and replies round-trip', () {
      expect(DiscoveryProtocol.isProbe(DiscoveryProtocol.probePayload), isTrue);
      expect(DiscoveryProtocol.isProbe('nonsense'.codeUnits), isFalse);
      expect(DiscoveryProtocol.isProbe(const <int>[]), isFalse);

      final reply = DiscoveryProtocol.parseBeaconReply(
        DiscoveryProtocol.encodeBeaconReply(
          port: 8083,
          name: 'living-room-pi',
          version: '1.2.3',
        ),
      );
      expect(reply, isNotNull);
      expect(reply!.port, 8083);
      expect(reply.name, 'living-room-pi');
      expect(reply.version, '1.2.3');
    });

    test('rejects non-reply payloads', () {
      expect(DiscoveryProtocol.parseBeaconReply('hello'.codeUnits), isNull);
      expect(
        DiscoveryProtocol.parseBeaconReply('{"ariami":"client"}'.codeUnits),
        isNull,
      );
      expect(
        DiscoveryProtocol.parseBeaconReply(
            '{"ariami":"server","port":"nope"}'.codeUnits),
        isNull,
      );
      expect(
        DiscoveryProtocol.parseBeaconReply(
            '{"ariami":"server","port":700000}'.codeUnits),
        isNull,
      );
    });
  });

  group('DiscoveryResponder beacon (loopback)', () {
    test('answers a probe with the server description', () async {
      // Port 0 = ephemeral, so the test never collides with a real server.
      final responder = DiscoveryResponder(beaconPort: 0);
      await responder.start(
        httpPort: 8089,
        serviceName: 'test-host',
        version: '9.9.9',
      );
      addTearDown(responder.stop);

      final beaconPort = responder.boundBeaconPort;
      expect(beaconPort, isNotNull);

      final prober =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(prober.close);

      final replyCompleter = Completer<BeaconReply>();
      prober.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = prober.receive();
        if (datagram == null) return;
        final reply = DiscoveryProtocol.parseBeaconReply(datagram.data);
        if (reply != null && !replyCompleter.isCompleted) {
          replyCompleter.complete(reply);
        }
      });

      prober.send(
        DiscoveryProtocol.probePayload,
        InternetAddress.loopbackIPv4,
        beaconPort!,
      );

      final reply = await replyCompleter.future
          .timeout(const Duration(seconds: 5));
      expect(reply.port, 8089);
      expect(reply.name, 'test-host');
      expect(reply.version, '9.9.9');
    });

    test('ignores non-probe datagrams', () async {
      final responder = DiscoveryResponder(beaconPort: 0);
      await responder.start(
        httpPort: 8080,
        serviceName: 'test-host',
        version: '1.0.0',
      );
      addTearDown(responder.stop);

      final prober =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(prober.close);

      var heardReply = false;
      prober.listen((event) {
        if (event == RawSocketEvent.read && prober.receive() != null) {
          heardReply = true;
        }
      });

      prober.send('GARBAGE'.codeUnits, InternetAddress.loopbackIPv4,
          responder.boundBeaconPort!);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(heardReply, isFalse);
    });
  });

  group('MdnsServiceRecords', () {
    final records = MdnsServiceRecords(
      httpPort: 8080,
      serviceName: 'Living Room Mac',
      version: '1.2.3',
    );
    final addresses = <InternetAddress>[
      InternetAddress('192.168.1.20'),
      InternetAddress('10.0.5.9'),
    ];

    test('derives sane instance and host names', () {
      expect(records.instanceName, 'Living-Room-Mac._ariami._tcp.local');
      expect(records.hostTarget, 'ariami-living-room-mac-8080.local');

      // A non-default port must yield a distinct instance, so two servers
      // on one machine don't claim the same records.
      final alt = MdnsServiceRecords(
        httpPort: 8081,
        serviceName: 'Living Room Mac',
        version: '1.2.3',
      );
      expect(alt.instanceName, 'Living-Room-Mac-8081._ariami._tcp.local');
      expect(alt.instanceName, isNot(records.instanceName));
    });

    test('answers a service PTR query with the full record set', () {
      final query = DnsMessage.parse(DnsMessage.encode(
        questions: const <DnsQuestion>[
          DnsQuestion(name: '_ariami._tcp.local', type: DnsType.ptr),
        ],
      ))!;

      final responseBytes = records.buildResponse(query, addresses);
      expect(responseBytes, isNotNull);
      final response = DnsMessage.parse(responseBytes!)!;
      expect(response.isResponse, isTrue);

      final ptr = response.records.singleWhere((r) => r.type == DnsType.ptr);
      expect(ptr.target, records.instanceName);
      final srv = response.records.singleWhere((r) => r.type == DnsType.srv);
      expect(srv.port, 8080);
      expect(srv.target, records.hostTarget);
      final aRecords =
          response.records.where((r) => r.type == DnsType.a).toList();
      expect(aRecords.map((r) => r.address),
          containsAll(<String>['192.168.1.20', '10.0.5.9']));
      final txt = response.records.singleWhere((r) => r.type == DnsType.txt);
      expect(txt.txt, contains('version=1.2.3'));
    });

    test('query name matching is case-insensitive', () {
      final query = DnsMessage.parse(DnsMessage.encode(
        questions: const <DnsQuestion>[
          DnsQuestion(name: '_ARIAMI._TCP.LOCAL', type: DnsType.ptr),
        ],
      ))!;
      expect(records.buildResponse(query, addresses), isNotNull);
    });

    test('stays silent for unrelated queries', () {
      final query = DnsMessage.parse(DnsMessage.encode(
        questions: const <DnsQuestion>[
          DnsQuestion(name: '_googlecast._tcp.local', type: DnsType.ptr),
          DnsQuestion(name: 'someone-else.local', type: DnsType.a),
        ],
      ))!;
      expect(records.buildResponse(query, addresses), isNull);
    });

    test('goodbye announcement carries TTL 0 on every record', () {
      final bytes = records.buildAnnouncement(addresses, ttl: 0);
      final message = DnsMessage.parse(Uint8List.fromList(bytes))!;
      expect(message.records, isNotEmpty);
      for (final record in message.records) {
        expect(record.ttl, 0);
      }
    });
  });
}
