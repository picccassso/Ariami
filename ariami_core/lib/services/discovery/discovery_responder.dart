import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'discovery_protocol.dart';
import 'dns_wire.dart';

/// Answers discovery traffic for a running Ariami server.
///
/// Runs two best-effort listeners:
///
/// 1. A UDP beacon on [DiscoveryProtocol.beaconPort]: replies unicast to
///    `ARIAMI_DISCOVER_V1` probes with the server's port/name/version.
///    Broadcast probes reach it on any subnet layout with zero
///    configuration.
/// 2. An mDNS advertiser on 5353: answers DNS-SD queries for
///    `_ariami._tcp.local`, which is what lets routers' mDNS reflectors
///    carry Ariami discovery across VLANs. The socket is opened with
///    address/port sharing so it coexists with avahi/Bonjour, and mDNS
///    multicast is delivered to every sharing socket.
///
/// Every failure here is logged and swallowed: discovery must never take
/// down or block the actual server. If 5353 can't be shared on some host,
/// the beacon still runs; if both fail, clients fall back to TCP scanning.
class DiscoveryResponder {
  DiscoveryResponder({int? beaconPort})
      : _beaconPort = beaconPort ?? DiscoveryProtocol.beaconPort;

  final int _beaconPort;

  RawDatagramSocket? _beaconSocket;
  RawDatagramSocket? _mdnsSocket;
  MdnsServiceRecords? _records;
  Timer? _reannounceTimer;

  int _httpPort = 0;
  String _serviceName = '';
  String _version = '';

  List<InternetAddress> _addressCache = const <InternetAddress>[];
  DateTime _addressCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _beaconSocket != null || _mdnsSocket != null;

  /// The port the beacon actually bound (for tests binding port 0).
  int? get boundBeaconPort => _beaconSocket?.port;

  Future<void> start({
    required int httpPort,
    required String serviceName,
    required String version,
  }) async {
    await stop();
    _httpPort = httpPort;
    _serviceName = serviceName;
    _version = version;
    _records = MdnsServiceRecords(
      httpPort: httpPort,
      serviceName: serviceName,
      version: version,
    );
    await _startBeacon();
    await _startMdns();
  }

  Future<void> stop() async {
    _reannounceTimer?.cancel();
    _reannounceTimer = null;

    final mdns = _mdnsSocket;
    final records = _records;
    if (mdns != null && records != null) {
      // RFC 6762 §10.1: goodbye packet (TTL 0) so caches drop us promptly.
      try {
        _sendMulticast(
          mdns,
          records.buildAnnouncement(_addressCache, ttl: 0),
        );
      } catch (_) {
        // The socket may already be unusable during shutdown.
      }
    }
    _mdnsSocket?.close();
    _mdnsSocket = null;
    _beaconSocket?.close();
    _beaconSocket = null;
    _records = null;
  }

  // ---------------------------------------------------------------------
  // UDP beacon
  // ---------------------------------------------------------------------

  Future<void> _startBeacon() async {
    try {
      final socket = await _bindShared(InternetAddress.anyIPv4, _beaconPort);
      await _joinGroup(socket, InternetAddress(DiscoveryProtocol.multicastGroup));
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        if (!DiscoveryProtocol.isProbe(datagram.data)) return;
        try {
          socket.send(
            DiscoveryProtocol.encodeBeaconReply(
              port: _httpPort,
              name: _serviceName,
              version: _version,
            ),
            datagram.address,
            datagram.port,
          );
        } catch (_) {
          // Unreachable prober; nothing to do.
        }
        // Datagram sockets surface async send errors (ICMP unreachable,
        // close races) as stream errors; without a handler they'd crash
        // the server as unhandled async errors.
      }, onError: (Object _, StackTrace __) {});
      _beaconSocket = socket;
      print('[Discovery] Beacon responder listening on UDP ${socket.port}');
    } catch (e) {
      print('[Discovery] Beacon responder unavailable: $e');
    }
  }

  // ---------------------------------------------------------------------
  // mDNS advertising
  // ---------------------------------------------------------------------

  Future<void> _startMdns() async {
    try {
      final socket = await _bindShared(
        InternetAddress.anyIPv4,
        DiscoveryProtocol.mdnsPort,
      );
      await _joinGroup(socket, InternetAddress(DiscoveryProtocol.mdnsGroup));
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        unawaited(_answerMdns(datagram));
      }, onError: (Object _, StackTrace __) {});
      _mdnsSocket = socket;
      print('[Discovery] mDNS advertising ${_records!.instanceName}');

      // RFC 6762 §8.3: announce unsolicited on startup, twice, 1s apart.
      unawaited(_announce());
      _reannounceTimer = Timer(const Duration(seconds: 1), () {
        unawaited(_announce());
      });
    } catch (e) {
      print('[Discovery] mDNS advertising unavailable: $e');
    }
  }

  Future<void> _announce() async {
    final socket = _mdnsSocket;
    final records = _records;
    if (socket == null || records == null) return;
    final addresses = await _localAddresses();
    if (addresses.isEmpty) return;
    try {
      _sendMulticast(socket, records.buildAnnouncement(addresses));
    } catch (e) {
      print('[Discovery] mDNS announce failed: $e');
    }
  }

  Future<void> _answerMdns(Datagram datagram) async {
    final socket = _mdnsSocket;
    final records = _records;
    if (socket == null || records == null) return;
    try {
      final query = DnsMessage.parse(datagram.data);
      if (query == null || query.isResponse || query.questions.isEmpty) {
        return;
      }
      if (!query.questions.any(records.matchesQuestion)) return;

      final addresses = await _localAddresses();

      // Legacy queriers (source port != 5353) and QU questions get a
      // unicast reply; everyone else the standard multicast response.
      final legacy = datagram.port != DiscoveryProtocol.mdnsPort;
      final wantsUnicast = legacy ||
          query.questions.any(
            (q) => q.unicastResponse && records.matchesQuestion(q),
          );
      final response = records.buildResponse(
        query,
        addresses,
        id: legacy ? query.id : 0,
      );
      if (response == null) return;
      if (wantsUnicast) {
        socket.send(response, datagram.address, datagram.port);
      } else {
        _sendMulticast(socket, response);
      }
    } catch (_) {
      // Malformed or hostile packet; ignore.
    }
  }

  void _sendMulticast(RawDatagramSocket socket, Uint8List packet) {
    socket.send(
      packet,
      InternetAddress(DiscoveryProtocol.mdnsGroup),
      DiscoveryProtocol.mdnsPort,
    );
  }

  // ---------------------------------------------------------------------
  // Socket plumbing
  // ---------------------------------------------------------------------

  /// Binds with address/port sharing so we can coexist with a system mDNS
  /// responder (avahi, Bonjour) or a second Ariami server on the host.
  /// reusePort is unsupported on Windows, so fall back without it.
  static Future<RawDatagramSocket> _bindShared(
    InternetAddress address,
    int port,
  ) async {
    try {
      return await RawDatagramSocket.bind(
        address,
        port,
        reuseAddress: true,
        reusePort: true,
      );
    } catch (_) {
      return RawDatagramSocket.bind(address, port, reuseAddress: true);
    }
  }

  /// Joins [group] on every IPv4 interface, falling back to a default join.
  /// Per-interface joins matter on multi-homed hosts (Docker bridges,
  /// Tailscale) where the default route would pick the wrong interface.
  static Future<void> _joinGroup(
    RawDatagramSocket socket,
    InternetAddress group,
  ) async {
    var joined = false;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        try {
          socket.joinMulticast(group, interface);
          joined = true;
        } catch (_) {
          // Interface without multicast support; skip it.
        }
      }
    } catch (_) {
      // Interface enumeration can fail in sandboxes; use the default join.
    }
    if (!joined) {
      try {
        socket.joinMulticast(group);
      } catch (_) {
        // Broadcast probes still reach the socket without a group join.
      }
    }
  }

  /// All non-loopback IPv4 addresses, cached briefly — mDNS query bursts
  /// shouldn't hammer interface enumeration.
  Future<List<InternetAddress>> _localAddresses() async {
    final now = DateTime.now();
    if (now.difference(_addressCacheAt) < const Duration(seconds: 10) &&
        _addressCache.isNotEmpty) {
      return _addressCache;
    }
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      _addressCache = <InternetAddress>[
        for (final interface in interfaces) ...interface.addresses,
      ];
      _addressCacheAt = now;
    } catch (_) {
      // Keep whatever we had.
    }
    return _addressCache;
  }
}

/// The DNS-SD record set for one advertised Ariami server, and the logic
/// for answering queries about it. Pure (no sockets) so it is unit-testable.
class MdnsServiceRecords {
  MdnsServiceRecords({
    required this.httpPort,
    required String serviceName,
    required this.version,
  })  : displayName = serviceName,
        instanceName = '${_instanceLabel(serviceName, httpPort)}.'
            '${DiscoveryProtocol.mdnsServiceType}',
        hostTarget =
            'ariami-${_sanitizeLabel(serviceName).toLowerCase()}-$httpPort.local';

  final int httpPort;
  final String version;
  final String displayName;

  /// `<instance>._ariami._tcp.local`.
  final String instanceName;

  /// The SRV target host name. Deliberately NOT `<hostname>.local`: the
  /// system mDNS responder owns that name, and advertising competing A
  /// records for it would trigger avahi/Bonjour conflict handling (which
  /// renames the machine). A made-up name is ours alone.
  final String hostTarget;

  static const String _serviceEnumerationName = '_services._dns-sd._udp.local';

  /// Shared-record TTL (PTR): 75 minutes per DNS-SD convention.
  static const int _sharedTtl = 4500;

  /// Host-specific record TTL (SRV/TXT/A): 2 minutes, so address changes
  /// (DHCP renumbering) age out quickly.
  static const int _uniqueTtl = 120;

  static String _instanceLabel(String serviceName, int port) {
    final base = _sanitizeLabel(serviceName);
    // Two servers on one machine (different ports) need distinct instances.
    return port == 8080 ? base : '$base-$port';
  }

  static String _sanitizeLabel(String value) {
    var label = value
        .replaceAll(RegExp(r'\.local\.?$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (label.isEmpty) label = 'Ariami-Server';
    if (label.length > 48) label = label.substring(0, 48);
    return label;
  }

  bool matchesQuestion(DnsQuestion question) {
    switch (question.type) {
      case DnsType.ptr:
        return dnsNamesEqual(question.name, DiscoveryProtocol.mdnsServiceType) ||
            dnsNamesEqual(question.name, _serviceEnumerationName);
      case DnsType.srv:
      case DnsType.txt:
        return dnsNamesEqual(question.name, instanceName);
      case DnsType.a:
        return dnsNamesEqual(question.name, hostTarget);
      case DnsType.any:
        return dnsNamesEqual(question.name, DiscoveryProtocol.mdnsServiceType) ||
            dnsNamesEqual(question.name, _serviceEnumerationName) ||
            dnsNamesEqual(question.name, instanceName) ||
            dnsNamesEqual(question.name, hostTarget);
      default:
        return false;
    }
  }

  DnsRecord _ptrRecord({int? ttl}) => DnsRecord(
        name: DiscoveryProtocol.mdnsServiceType,
        type: DnsType.ptr,
        ttl: ttl ?? _sharedTtl,
        target: instanceName,
      );

  DnsRecord _srvRecord({int? ttl}) => DnsRecord(
        name: instanceName,
        type: DnsType.srv,
        ttl: ttl ?? _uniqueTtl,
        cacheFlush: true,
        port: httpPort,
        target: hostTarget,
      );

  DnsRecord _txtRecord({int? ttl}) => DnsRecord(
        name: instanceName,
        type: DnsType.txt,
        ttl: ttl ?? _sharedTtl,
        cacheFlush: true,
        txt: <String>['version=$version', 'name=$displayName'],
      );

  List<DnsRecord> _aRecords(List<InternetAddress> addresses, {int? ttl}) =>
      <DnsRecord>[
        for (final address in addresses)
          if (address.type == InternetAddressType.IPv4)
            DnsRecord(
              name: hostTarget,
              type: DnsType.a,
              ttl: ttl ?? _uniqueTtl,
              cacheFlush: true,
              address: address.address,
            ),
      ];

  /// Builds the response to [query], or null when no question matches.
  Uint8List? buildResponse(
    DnsMessage query,
    List<InternetAddress> addresses, {
    int id = 0,
  }) {
    final answers = <DnsRecord>[];
    final additionals = <DnsRecord>[];

    for (final question in query.questions) {
      if (!matchesQuestion(question)) continue;
      final wantsAll = question.type == DnsType.any;

      if (dnsNamesEqual(question.name, _serviceEnumerationName)) {
        answers.add(DnsRecord(
          name: _serviceEnumerationName,
          type: DnsType.ptr,
          ttl: _sharedTtl,
          target: DiscoveryProtocol.mdnsServiceType,
        ));
        continue;
      }
      if (dnsNamesEqual(question.name, DiscoveryProtocol.mdnsServiceType)) {
        answers.add(_ptrRecord());
        // RFC 6763 §12.1: hand the browser everything it needs up front.
        additionals
          ..add(_srvRecord())
          ..add(_txtRecord())
          ..addAll(_aRecords(addresses));
        continue;
      }
      if (dnsNamesEqual(question.name, instanceName)) {
        if (wantsAll || question.type == DnsType.srv) {
          answers.add(_srvRecord());
          additionals.addAll(_aRecords(addresses));
        }
        if (wantsAll || question.type == DnsType.txt) {
          answers.add(_txtRecord());
        }
        continue;
      }
      if (dnsNamesEqual(question.name, hostTarget)) {
        answers.addAll(_aRecords(addresses));
      }
    }

    if (answers.isEmpty) return null;
    return DnsMessage.encode(
      id: id,
      flags: DnsMessage.responseFlags,
      answers: answers,
      additionals: additionals,
    );
  }

  /// The unsolicited startup announcement (or, with [ttl] 0, the goodbye).
  Uint8List buildAnnouncement(List<InternetAddress> addresses, {int? ttl}) {
    return DnsMessage.encode(
      flags: DnsMessage.responseFlags,
      answers: <DnsRecord>[
        _ptrRecord(ttl: ttl),
        _srvRecord(ttl: ttl),
        _txtRecord(ttl: ttl),
        ..._aRecords(addresses, ttl: ttl),
      ],
    );
  }
}
