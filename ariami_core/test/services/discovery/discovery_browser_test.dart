import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/discovery/discovery_browser.dart';
import 'package:ariami_core/services/discovery/discovery_responder.dart';
import 'package:ariami_core/services/discovery/dns_wire.dart';
import 'package:test/test.dart';

void main() {
  group('DiscoveryBrowser.parseMdnsEndpoints', () {
    test('understands what our own responder advertises', () {
      // The exact packet a DiscoveryResponder would multicast: the browser
      // and advertiser must stay mutually intelligible.
      final records = MdnsServiceRecords(
        httpPort: 8082,
        serviceName: 'office-nas',
        version: '1.2.3',
      );
      final announcement = records.buildAnnouncement(<InternetAddress>[
        InternetAddress('192.168.40.7'),
      ]);

      final endpoints =
          DiscoveryBrowser.parseMdnsEndpoints(announcement, '192.168.40.7');
      expect(endpoints, hasLength(1));
      expect(endpoints.single.host, '192.168.40.7');
      expect(endpoints.single.port, 8082);
      expect(endpoints.single.source, 'mdns');
    });

    test('falls back to the sender address when no A record is present',
        () {
      final packet = DnsMessage.encode(
        flags: DnsMessage.responseFlags,
        answers: const <DnsRecord>[
          DnsRecord(
            name: '_ariami._tcp.local',
            type: DnsType.ptr,
            ttl: 4500,
            target: 'pi._ariami._tcp.local',
          ),
          DnsRecord(
            name: 'pi._ariami._tcp.local',
            type: DnsType.srv,
            ttl: 120,
            port: 8080,
            target: 'ariami-pi-8080.local',
          ),
        ],
      );

      final endpoints =
          DiscoveryBrowser.parseMdnsEndpoints(packet, '10.20.30.40');
      expect(endpoints, hasLength(1));
      expect(endpoints.single.host, '10.20.30.40');
      expect(endpoints.single.port, 8080);
    });

    test('accepts a direct SRV answer without the PTR record', () {
      final packet = DnsMessage.encode(
        flags: DnsMessage.responseFlags,
        answers: const <DnsRecord>[
          DnsRecord(
            name: 'den._ariami._tcp.local',
            type: DnsType.srv,
            ttl: 120,
            port: 8091,
            target: 'ariami-den-8091.local',
          ),
          DnsRecord(
            name: 'ariami-den-8091.local',
            type: DnsType.a,
            ttl: 120,
            address: '172.16.9.3',
          ),
        ],
      );

      final endpoints =
          DiscoveryBrowser.parseMdnsEndpoints(packet, '172.16.9.3');
      expect(endpoints, hasLength(1));
      expect(endpoints.single.host, '172.16.9.3');
      expect(endpoints.single.port, 8091);
    });

    test('ignores other services, queries, and junk', () {
      final otherService = DnsMessage.encode(
        flags: DnsMessage.responseFlags,
        answers: const <DnsRecord>[
          DnsRecord(
            name: '_googlecast._tcp.local',
            type: DnsType.ptr,
            ttl: 120,
            target: 'tv._googlecast._tcp.local',
          ),
          DnsRecord(
            name: 'tv._googlecast._tcp.local',
            type: DnsType.srv,
            ttl: 120,
            port: 8009,
            target: 'tv.local',
          ),
        ],
      );
      expect(
        DiscoveryBrowser.parseMdnsEndpoints(otherService, '1.2.3.4'),
        isEmpty,
      );

      final query = DnsMessage.encode(
        questions: const <DnsQuestion>[
          DnsQuestion(name: '_ariami._tcp.local', type: DnsType.ptr),
        ],
      );
      expect(DiscoveryBrowser.parseMdnsEndpoints(query, '1.2.3.4'), isEmpty);

      expect(
        DiscoveryBrowser.parseMdnsEndpoints(
            Uint8List.fromList(<int>[1, 2, 3]), '1.2.3.4'),
        isEmpty,
      );
    });
  });
}
