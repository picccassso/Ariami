/// Invokes [onHttpServerReady] after the HTTP server has bound [port].
Future<void> notifyHttpServerReady(
  Future<void> Function(int port)? onHttpServerReady,
  int port,
) async {
  if (onHttpServerReady != null) {
    await onHttpServerReady(port);
  }
}
