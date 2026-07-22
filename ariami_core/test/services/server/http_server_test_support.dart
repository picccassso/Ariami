import 'package:ariami_core/services/server/http_server.dart';

/// Starts [server] on an OS-assigned port and returns the actual bound port.
///
/// Binding port 0 directly avoids the race created by probing an ephemeral
/// port, releasing it, and asking the HTTP server to bind it later.
Future<int> startHttpTestServer(
  AriamiHttpServer server, {
  String advertisedIp = '127.0.0.1',
  String bindAddress = '127.0.0.1',
}) async {
  await server.start(
    advertisedIp: advertisedIp,
    bindAddress: bindAddress,
    port: 0,
  );
  return server.getServerInfo()['port'] as int;
}
