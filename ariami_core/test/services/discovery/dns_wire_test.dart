import 'dart:typed_data';

import 'package:ariami_core/services/discovery/dns_wire.dart';
import 'package:test/test.dart';

void main() {
  group('DnsMessage encode/parse round trip', () {
    test('query with QU bit survives a round trip', () {
      final bytes = DnsMessage.encode(
        id: 42,
        questions: const <DnsQuestion>[
          DnsQuestion(
            name: '_ariami._tcp.local',
            type: DnsType.ptr,
            qclass: DnsClass.internet | DnsClass.topBit,
          ),
        ],
      );

      final message = DnsMessage.parse(bytes);
      expect(message, isNotNull);
      expect(message!.id, 42);
      expect(message.isResponse, isFalse);
      expect(message.questions, hasLength(1));
      final question = message.questions.single;
      expect(question.name, '_ariami._tcp.local');
      expect(question.type, DnsType.ptr);
      expect(question.unicastResponse, isTrue);
    });

    test('full DNS-SD response survives a round trip', () {
      final bytes = DnsMessage.encode(
        flags: DnsMessage.responseFlags,
        answers: const <DnsRecord>[
          DnsRecord(
            name: '_ariami._tcp.local',
            type: DnsType.ptr,
            ttl: 4500,
            target: 'MyServer._ariami._tcp.local',
          ),
        ],
        additionals: const <DnsRecord>[
          DnsRecord(
            name: 'MyServer._ariami._tcp.local',
            type: DnsType.srv,
            ttl: 120,
            cacheFlush: true,
            port: 8085,
            target: 'ariami-myserver-8085.local',
          ),
          DnsRecord(
            name: 'MyServer._ariami._tcp.local',
            type: DnsType.txt,
            ttl: 4500,
            cacheFlush: true,
            txt: <String>['version=1.2.3', 'name=MyServer'],
          ),
          DnsRecord(
            name: 'ariami-myserver-8085.local',
            type: DnsType.a,
            ttl: 120,
            cacheFlush: true,
            address: '192.168.7.20',
          ),
        ],
      );

      final message = DnsMessage.parse(bytes);
      expect(message, isNotNull);
      expect(message!.isResponse, isTrue);
      expect(message.records, hasLength(4));

      final ptr =
          message.records.singleWhere((r) => r.type == DnsType.ptr);
      expect(ptr.name, '_ariami._tcp.local');
      expect(ptr.target, 'MyServer._ariami._tcp.local');
      expect(ptr.cacheFlush, isFalse);

      final srv =
          message.records.singleWhere((r) => r.type == DnsType.srv);
      expect(srv.port, 8085);
      expect(srv.target, 'ariami-myserver-8085.local');
      expect(srv.cacheFlush, isTrue);
      expect(srv.ttl, 120);

      final txt =
          message.records.singleWhere((r) => r.type == DnsType.txt);
      expect(txt.txt, <String>['version=1.2.3', 'name=MyServer']);

      final a = message.records.singleWhere((r) => r.type == DnsType.a);
      expect(a.name, 'ariami-myserver-8085.local');
      expect(a.address, '192.168.7.20');
    });
  });

  group('DnsMessage.parse robustness', () {
    test('decompresses pointer-compressed names', () {
      // Hand-built response: answer PTR "_x._tcp.local" whose rdata target
      // is "svc" + pointer back to the question name at offset 12.
      final packet = <int>[
        0, 0, // id
        0x84, 0x00, // flags: response
        0, 1, // one question
        0, 1, // one answer
        0, 0,
        0, 0,
        // question name at offset 12: _x._tcp.local
        2, 0x5f, 0x78, // "_x"
        4, 0x5f, 0x74, 0x63, 0x70, // "_tcp"
        5, 0x6c, 0x6f, 0x63, 0x61, 0x6c, // "local"
        0,
        0, 12, // PTR
        0, 1, // IN
        // answer: name = pointer to offset 12
        0xc0, 12,
        0, 12, // PTR
        0, 1, // IN
        0, 0, 0, 60, // ttl
        0, 6, // rdlength: "svc" + 2-byte pointer
        3, 0x73, 0x76, 0x63, // "svc"
        0xc0, 12, // pointer back to _x._tcp.local
      ];

      final message = DnsMessage.parse(Uint8List.fromList(packet));
      expect(message, isNotNull);
      expect(message!.questions.single.name, '_x._tcp.local');
      final ptr = message.records.single;
      expect(ptr.name, '_x._tcp.local');
      expect(ptr.target, 'svc._x._tcp.local');
    });

    test('rejects malformed packets instead of throwing', () {
      expect(DnsMessage.parse(Uint8List(0)), isNull);
      expect(DnsMessage.parse(Uint8List(5)), isNull);
      // Header claims a question but the packet ends.
      expect(
        DnsMessage.parse(Uint8List.fromList(
            <int>[0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])),
        isNull,
      );
      // Compression pointer loop.
      expect(
        DnsMessage.parse(Uint8List.fromList(<int>[
          0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, //
          0xc0, 12, 0, 1, 0, 1,
        ])),
        isNull,
      );
    });

    test('names compare case-insensitively', () {
      expect(dnsNamesEqual('_Ariami._TCP.local', '_ariami._tcp.LOCAL'),
          isTrue);
      expect(dnsNamesEqual('a.local', 'b.local'), isFalse);
    });
  });
}
