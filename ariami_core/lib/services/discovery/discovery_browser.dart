import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'discovery_protocol.dart';
import 'dns_wire.dart';

/// A server endpoint heard via the beacon or mDNS.
///
/// Candidates are unauthenticated hearsay from the network: callers must
/// verify each one over HTTP (`GET /api/server-info`) before showing it.
class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.host,
    required this.port,
    required this.source,
  });

  final String host;
  final int port;

  /// 'beacon' or 'mdns' — for logging only.
  final String source;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Actively listens for Ariami servers announcing themselves.
///
/// Complements (does not replace) TCP subnet scanning:
///
/// - UDP beacon probes are broadcast + multicast, so they reach every host
///   on the link regardless of subnet size — no /24 assumption — and the
///   replies are unicast, so hearing them needs no multicast lock on
///   Android.
/// - mDNS queries find servers across VLANs when the router runs an mDNS
///   reflector (UniFi, Avahi, OpenWrt). Queries set the QU (unicast
///   response) bit so replies arrive even where multicast reception is
///   unreliable.
///
/// TCP scanning remains the fallback for servers that can't hear UDP at
/// all — most notably Docker bridge networking, where published TCP ports
/// work but broadcast/multicast never reaches the container.
class DiscoveryBrowser {
  DiscoveryBrowser._();

  static const List<Duration> _probeSchedule = <Duration>[
    Duration.zero,
    Duration(milliseconds: 900),
    Duration(milliseconds: 2200),
  ];

  /// Probes the network and yields deduplicated candidate endpoints as they
  /// answer. The stream closes after [timeout]. Never throws: on hosts
  /// where sockets can't be opened it simply completes empty.
  static Stream<DiscoveredEndpoint> discover({
    Duration timeout = const Duration(seconds: 4),
    int beaconPort = DiscoveryProtocol.beaconPort,
  }) {
    final controller = StreamController<DiscoveredEndpoint>();
    final seen = <DiscoveredEndpoint>{};
    final timers = <Timer>[];
    RawDatagramSocket? beaconSocket;
    RawDatagramSocket? mdnsQuerySocket;
    RawDatagramSocket? mdnsListenSocket;
    var done = false;

    void emit(DiscoveredEndpoint endpoint) {
      if (done || !seen.add(endpoint)) return;
      controller.add(endpoint);
    }

    void cleanup() {
      if (done) return;
      done = true;
      for (final timer in timers) {
        timer.cancel();
      }
      beaconSocket?.close();
      mdnsQuerySocket?.close();
      mdnsListenSocket?.close();
    }

    Future<void> sendProbes() async {
      final beacon = beaconSocket;
      if (beacon != null) {
        final targets = <InternetAddress>[
          InternetAddress('255.255.255.255'),
          InternetAddress(DiscoveryProtocol.multicastGroup),
          // Directed /24 broadcasts: some APs filter the global broadcast
          // address but pass subnet-directed ones.
          ...await _directedBroadcastAddresses(),
        ];
        for (final target in targets) {
          try {
            beacon.send(DiscoveryProtocol.probePayload, target, beaconPort);
          } catch (_) {
            // Route/permission problems on one target don't matter.
          }
        }
      }

      final mdns = mdnsQuerySocket;
      if (mdns != null) {
        // A one-shot legacy query (RFC 6762 §6.7): sent from an ephemeral
        // port, so responders unicast the answer straight back to this
        // socket. That delivery is unambiguous — a reply to a shared 5353
        // port would reach only ONE of the sockets sharing it (likely the
        // system mDNS daemon, not us), and multicast responses need a
        // multicast lock on Android. The QU bit is set for responders
        // that check it rather than the source port.
        final query = DnsMessage.encode(
          questions: const <DnsQuestion>[
            DnsQuestion(
              name: DiscoveryProtocol.mdnsServiceType,
              type: DnsType.ptr,
              qclass: DnsClass.internet | DnsClass.topBit,
            ),
          ],
        );
        try {
          mdns.send(
            query,
            InternetAddress(DiscoveryProtocol.mdnsGroup),
            DiscoveryProtocol.mdnsPort,
          );
        } catch (_) {
          // No multicast route; the beacon and TCP scan still run.
        }
      }
    }

    Future<void> run() async {
      try {
        final socket =
            await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          final reply = DiscoveryProtocol.parseBeaconReply(datagram.data);
          if (reply == null) return;
          emit(DiscoveredEndpoint(
            host: datagram.address.address,
            port: reply.port,
            source: 'beacon',
          ));
          // Datagram sockets surface async send errors (ICMP unreachable,
          // close races) as stream errors; without a handler they'd crash
          // the app as unhandled async errors.
        }, onError: (Object _, StackTrace __) {});
        beaconSocket = socket;
      } catch (_) {
        // No UDP at all; mDNS may still work below.
      }

      void listenForMdns(RawDatagramSocket socket) {
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          for (final endpoint
              in parseMdnsEndpoints(datagram.data, datagram.address.address)) {
            emit(endpoint);
          }
        }, onError: (Object _, StackTrace __) {});
      }

      // Queries go out from (and replies come back to) an ephemeral port.
      try {
        final socket =
            await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        listenForMdns(socket);
        mdnsQuerySocket = socket;
      } catch (_) {
        // mDNS unavailable; the beacon may still have bound above.
      }

      // Additionally share 5353 where the platform allows, to overhear
      // multicast responses and gratuitous announcements. Best-effort —
      // the query socket above is the reliable path.
      try {
        final socket = await _bindSharedMdnsListener();
        listenForMdns(socket);
        mdnsListenSocket = socket;
      } catch (_) {
        // Couldn't share 5353 (or join the group); fine.
      }

      if (done) {
        // Cancelled while the binds were in flight.
        beaconSocket?.close();
        mdnsQuerySocket?.close();
        mdnsListenSocket?.close();
        return;
      }

      for (final delay in _probeSchedule) {
        if (delay == Duration.zero) {
          unawaited(sendProbes());
        } else {
          timers.add(Timer(delay, () => unawaited(sendProbes())));
        }
      }

      timers.add(Timer(timeout, () {
        cleanup();
        unawaited(controller.close());
      }));
    }

    controller.onListen = () => unawaited(run());
    controller.onCancel = cleanup;
    return controller.stream;
  }

  /// Extracts Ariami endpoints from one mDNS packet sent by
  /// [senderAddress]. Returns an empty list for anything that isn't an
  /// Ariami DNS-SD response (which is most 5353 traffic). Public and pure
  /// for testability.
  static List<DiscoveredEndpoint> parseMdnsEndpoints(
    Uint8List packet,
    String senderAddress,
  ) {
    final message = DnsMessage.parse(packet);
    if (message == null || !message.isResponse) {
      return const <DiscoveredEndpoint>[];
    }

    // Instance names of the Ariami service seen in this packet: from PTR
    // answers, plus any SRV that itself belongs to the service (direct
    // SRV answers arrive without the PTR).
    final instances = <String>{};
    for (final record in message.records) {
      if (record.type == DnsType.ptr &&
          dnsNamesEqual(record.name, DiscoveryProtocol.mdnsServiceType) &&
          record.target != null) {
        instances.add(record.target!.toLowerCase());
      }
      if (record.type == DnsType.srv &&
          record.name
              .toLowerCase()
              .endsWith('.${DiscoveryProtocol.mdnsServiceType}')) {
        instances.add(record.name.toLowerCase());
      }
    }
    if (instances.isEmpty) return const <DiscoveredEndpoint>[];

    final aRecordsByName = <String, List<String>>{};
    for (final record in message.records) {
      if (record.type == DnsType.a && record.address != null) {
        aRecordsByName
            .putIfAbsent(record.name.toLowerCase(), () => <String>[])
            .add(record.address!);
      }
    }

    final endpoints = <DiscoveredEndpoint>[];
    for (final record in message.records) {
      if (record.type != DnsType.srv) continue;
      if (!instances.contains(record.name.toLowerCase())) continue;
      if (record.port <= 0) continue;
      final target = record.target?.toLowerCase();
      final hosts = (target != null ? aRecordsByName[target] : null) ??
          // No A record in the packet: the responder itself is our best
          // guess (usually right for reflected packets too; when it is
          // wrong, HTTP verification fails and the candidate is dropped).
          <String>[senderAddress];
      for (final host in hosts) {
        endpoints.add(
          DiscoveredEndpoint(host: host, port: record.port, source: 'mdns'),
        );
      }
    }
    return endpoints;
  }

  /// The passive 5353 listener: shares the port with the system mDNS
  /// daemon and joins the group. Throws when the platform refuses; callers
  /// treat that as "no passive listening" and rely on the query socket.
  static Future<RawDatagramSocket> _bindSharedMdnsListener() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      DiscoveryProtocol.mdnsPort,
      reuseAddress: true,
      reusePort: true,
    );
    try {
      socket.joinMulticast(InternetAddress(DiscoveryProtocol.mdnsGroup));
    } catch (_) {
      // Join can fail (e.g. Android without a multicast lock); the socket
      // still hears whatever the OS delivers to the shared port.
    }
    return socket;
  }

  /// x.y.z.255 for every local IPv4, assuming /24 — a probe target, not a
  /// scan range, so the guess being wrong for wider subnets is harmless
  /// (the global broadcast and multicast probes cover those).
  static Future<List<InternetAddress>> _directedBroadcastAddresses() async {
    final result = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          final lastDot = ip.lastIndexOf('.');
          if (lastDot < 0) continue;
          result.add(InternetAddress('${ip.substring(0, lastDot)}.255'));
        }
      }
    } catch (_) {
      // Enumeration failure just means fewer probe targets.
    }
    return result;
  }
}
