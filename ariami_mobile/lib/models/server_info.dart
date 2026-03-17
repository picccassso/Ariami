/// Server information model for connection
library;

class ServerInfo {
  final String server; // IP address
  final String? lanServer; // Local network IP address
  final String? tailscaleServer; // Remote Tailscale IP address
  final int port;
  final String name; // Server/computer name
  final String version;
  final bool authRequired; // Whether server requires authentication
  final bool legacyMode; // Whether server is in legacy mode (no users yet)
  final DownloadLimits downloadLimits;

  ServerInfo({
    required this.server,
    this.lanServer,
    this.tailscaleServer,
    required this.port,
    required this.name,
    required this.version,
    this.authRequired = false,
    this.legacyMode = true,
    this.downloadLimits = DownloadLimits.fallback,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final server = json['server'] as String;
    final lanServer = json['lanServer'] as String?;
    final explicitTailscaleServer = json['tailscaleServer'] as String?;
    final derivedTailscaleServer = explicitTailscaleServer ??
        ((lanServer != null && lanServer != server) ? server : null);

    return ServerInfo(
      server: server,
      lanServer: lanServer,
      tailscaleServer: derivedTailscaleServer,
      port: json['port'] as int,
      name: json['name'] as String,
      version: json['version'] as String,
      authRequired: json['authRequired'] as bool? ?? false,
      legacyMode: json['legacyMode'] as bool? ?? true,
      downloadLimits: DownloadLimits.fromJson(
        json['downloadLimits'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server': server,
      'lanServer': lanServer,
      'tailscaleServer': tailscaleServer,
      'port': port,
      'name': name,
      'version': version,
      'authRequired': authRequired,
      'legacyMode': legacyMode,
      'downloadLimits': downloadLimits.toJson(),
    };
  }

  /// Get the base URL for API requests
  String get baseUrl => 'http://$server:$port';

  /// Get the WebSocket URL
  String get wsUrl => 'ws://$server:$port';

  bool get hasLanEndpoint => lanServer != null && lanServer!.isNotEmpty;

  bool get hasTailscaleEndpoint =>
      tailscaleServer != null && tailscaleServer!.isNotEmpty;

  bool get isUsingLanRoute => hasLanEndpoint && lanServer == server;

  bool get isUsingLocalNetworkRoute => isUsingLanRoute || !hasTailscaleEndpoint;

  String get routeLabel =>
      isUsingLocalNetworkRoute ? 'Local Network' : 'Tailscale';

  ServerInfo withServer(String ip) {
    return ServerInfo(
      server: ip,
      lanServer: lanServer,
      tailscaleServer: tailscaleServer,
      port: port,
      name: name,
      version: version,
      authRequired: authRequired,
      legacyMode: legacyMode,
      downloadLimits: downloadLimits,
    );
  }

  ServerInfo copyWith({
    String? server,
    String? lanServer,
    String? tailscaleServer,
    int? port,
    String? name,
    String? version,
    bool? authRequired,
    bool? legacyMode,
    DownloadLimits? downloadLimits,
  }) {
    return ServerInfo(
      server: server ?? this.server,
      lanServer: lanServer ?? this.lanServer,
      tailscaleServer: tailscaleServer ?? this.tailscaleServer,
      port: port ?? this.port,
      name: name ?? this.name,
      version: version ?? this.version,
      authRequired: authRequired ?? this.authRequired,
      legacyMode: legacyMode ?? this.legacyMode,
      downloadLimits: downloadLimits ?? this.downloadLimits,
    );
  }

  @override
  String toString() {
    return 'ServerInfo(server: $server, lanServer: $lanServer, tailscaleServer: $tailscaleServer, port: $port, name: $name, version: $version, authRequired: $authRequired, legacyMode: $legacyMode, downloadLimits: $downloadLimits)';
  }
}

class DownloadLimits {
  static const DownloadLimits fallback = DownloadLimits(
    maxConcurrent: 4,
    maxQueue: 10000,
    maxConcurrentPerUser: 2,
    maxQueuePerUser: 10000,
  );

  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  const DownloadLimits({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });

  factory DownloadLimits.fromJson(Map<String, dynamic>? json) {
    if (json == null) return fallback;
    return DownloadLimits(
      maxConcurrent: json['maxConcurrent'] as int? ?? fallback.maxConcurrent,
      maxQueue: json['maxQueue'] as int? ?? fallback.maxQueue,
      maxConcurrentPerUser:
          json['maxConcurrentPerUser'] as int? ?? fallback.maxConcurrentPerUser,
      maxQueuePerUser:
          json['maxQueuePerUser'] as int? ?? fallback.maxQueuePerUser,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxConcurrent': maxConcurrent,
      'maxQueue': maxQueue,
      'maxConcurrentPerUser': maxConcurrentPerUser,
      'maxQueuePerUser': maxQueuePerUser,
    };
  }

  @override
  String toString() {
    return 'DownloadLimits(maxConcurrent: $maxConcurrent, maxQueue: $maxQueue, maxConcurrentPerUser: $maxConcurrentPerUser, maxQueuePerUser: $maxQueuePerUser)';
  }
}
