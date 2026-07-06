import 'dart:convert';
import 'dart:typed_data';

/// Wire-level constants and payload helpers for Ariami server discovery.
///
/// Two cooperating mechanisms share this file:
///
/// 1. A UDP beacon: clients broadcast/multicast [probePayload] to
///    [beaconPort]; every running server replies unicast — straight back to
///    the probe's source address — with a small JSON payload describing
///    itself. Because the reply is unicast, clients hear it without needing
///    an Android multicast lock, and because the probe is a broadcast it
///    reaches every host on the link regardless of subnet mask (no /24
///    guessing).
/// 2. mDNS/DNS-SD: servers advertise the [mdnsServiceType] service so
///    clients — and the mDNS reflectors many routers provide (Avahi,
///    UniFi, OpenWrt) — can find them across VLAN boundaries without any
///    scanning.
///
/// Both sides of both mechanisms live in ariami_core so every server host
/// (CLI, desktop) and every client app speak exactly the same dialect.
class DiscoveryProtocol {
  DiscoveryProtocol._();

  /// UDP port the server-side beacon responder listens on.
  static const int beaconPort = 45420;

  /// Multicast group probed alongside the plain broadcast, for networks
  /// where 255.255.255.255 broadcasts are filtered.
  static const String multicastGroup = '239.255.90.90';

  /// Datagram a client sends to ask servers to identify themselves.
  static const String probeMessage = 'ARIAMI_DISCOVER_V1';

  /// DNS-SD service type advertised over mDNS.
  static const String mdnsServiceType = '_ariami._tcp.local';

  /// The mDNS multicast group and port (RFC 6762).
  static const String mdnsGroup = '224.0.0.251';
  static const int mdnsPort = 5353;

  static final Uint8List probePayload =
      Uint8List.fromList(utf8.encode(probeMessage));

  /// Whether [datagram] is a discovery probe from a client.
  static bool isProbe(List<int> datagram) {
    if (datagram.length != probePayload.length) return false;
    for (var i = 0; i < datagram.length; i++) {
      if (datagram[i] != probePayload[i]) return false;
    }
    return true;
  }

  /// Encodes the server's answer to a probe.
  static Uint8List encodeBeaconReply({
    required int port,
    required String name,
    required String version,
  }) {
    return Uint8List.fromList(utf8.encode(jsonEncode(<String, dynamic>{
      'ariami': 'server',
      'port': port,
      'name': name,
      'version': version,
    })));
  }

  /// Decodes a beacon reply, or null when [datagram] is not one.
  static BeaconReply? parseBeaconReply(List<int> datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['ariami'] != 'server') return null;
      final port = decoded['port'];
      if (port is! int || port <= 0 || port > 65535) return null;
      return BeaconReply(
        port: port,
        name: decoded['name'] as String? ?? 'Ariami Server',
        version: decoded['version'] as String? ?? 'unknown',
      );
    } catch (_) {
      return null;
    }
  }
}

/// A server's answer to a discovery probe. The host is not part of the
/// payload — it is the datagram's source address.
class BeaconReply {
  const BeaconReply({
    required this.port,
    required this.name,
    required this.version,
  });

  final int port;
  final String name;
  final String version;
}
