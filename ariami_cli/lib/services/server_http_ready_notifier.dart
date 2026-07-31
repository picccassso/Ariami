/// Invokes [onHttpServerReady] once the HTTP server is listening.
///
/// [port] is the port to send users to, which is the bound port unless a
/// container publishes the server on a different one.
Future<void> notifyHttpServerReady(
  Future<void> Function(int port)? onHttpServerReady,
  int port,
) async {
  if (onHttpServerReady != null) {
    await onHttpServerReady(port);
  }
}
