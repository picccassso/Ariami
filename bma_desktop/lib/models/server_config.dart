class ServerConfig {
  static const int port = 8080;
  static const String apiVersion = "1.0.0";
  static const int maxConnections = 10;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration clientTimeout = Duration(minutes: 5);
}
