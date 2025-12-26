/// Server information model for connection
library;

class ServerInfo {
  final String server; // IP address
  final int port;
  final String name; // Server/computer name
  final String version;

  ServerInfo({
    required this.server,
    required this.port,
    required this.name,
    required this.version,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      server: json['server'] as String,
      port: json['port'] as int,
      name: json['name'] as String,
      version: json['version'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server': server,
      'port': port,
      'name': name,
      'version': version,
    };
  }

  /// Get the base URL for API requests
  String get baseUrl => 'http://$server:$port';

  /// Get the WebSocket URL
  String get wsUrl => 'ws://$server:$port';

  @override
  String toString() {
    return 'ServerInfo(server: $server, port: $port, name: $name, version: $version)';
  }
}
