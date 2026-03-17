import '../../../models/server_info.dart';
import '../api_client.dart';
import '../endpoint_resolver.dart';

/// Manages server configuration and metadata.
///
/// Handles:
/// - Current server info tracking
/// - Server info hydration from API
/// - Endpoint resolution (LAN/Tailscale)
/// - Download limits application
class ServerInfoManager {
  final EndpointResolver _endpointResolver;

  ServerInfo? _serverInfo;

  /// Creates a ServerInfoManager.
  ///
  /// [endpointResolver] is used for LAN/Tailscale endpoint resolution.
  ServerInfoManager({
    EndpointResolver? endpointResolver,
  }) : _endpointResolver = endpointResolver ?? EndpointResolver();

  /// Current server information
  ServerInfo? get serverInfo => _serverInfo;

  /// Whether we have server info (even if not currently connected)
  bool get hasServerInfo => _serverInfo != null;

  /// Get the endpoint resolver for advanced use cases
  EndpointResolver get endpointResolver => _endpointResolver;

  /// Set the server info
  void setServerInfo(ServerInfo? serverInfo) {
    _serverInfo = serverInfo;
  }

  /// Update just the server IP (used during endpoint switches)
  void updateServerIp(String newIp) {
    final current = _serverInfo;
    if (current != null && current.server != newIp) {
      _serverInfo = current.withServer(newIp);
    }
  }

  /// Resolve the preferred server endpoint (LAN vs Tailscale).
  ///
  /// Configures the endpoint resolver and returns server info with
  /// the resolved IP address.
  Future<ServerInfo> resolvePreferredServerInfo(ServerInfo serverInfo) async {
    final primaryIp = serverInfo.tailscaleServer ?? serverInfo.server;
    _endpointResolver.configure(
      primaryIp: primaryIp,
      lanIp: serverInfo.lanServer,
      port: serverInfo.port,
      activeIp: serverInfo.server,
    );
    final resolvedIp = await _endpointResolver.resolve();
    if (resolvedIp == serverInfo.server) {
      return serverInfo;
    }
    return serverInfo.withServer(resolvedIp);
  }

  /// Hydrate server info metadata from the API.
  ///
  /// Fetches fresh server info from the API and merges it with
  /// the existing server info. This updates fields like version,
  /// authRequired, downloadLimits, etc.
  Future<ServerInfo> hydrateServerInfoMetadata(
    ApiClient apiClient,
    ServerInfo serverInfo,
  ) async {
    try {
      final fetched = await apiClient.getServerInfo();
      final merged = serverInfo.copyWith(
        server: serverInfo.server,
        lanServer: fetched.lanServer ?? serverInfo.lanServer,
        tailscaleServer: fetched.tailscaleServer ?? serverInfo.tailscaleServer,
        port: fetched.port,
        name: fetched.name,
        version: fetched.version,
        authRequired: fetched.authRequired,
        legacyMode: fetched.legacyMode,
        downloadLimits: fetched.downloadLimits,
      );
      // Only update if something changed
      if (_hasServerInfoChanged(merged, serverInfo)) {
        _serverInfo = merged;
      }
      return merged;
    } catch (e) {
      // Return original server info on failure
      return serverInfo;
    }
  }

  /// Compare two ServerInfo objects for equality.
  bool _hasServerInfoChanged(ServerInfo a, ServerInfo b) {
    return a.server != b.server ||
        a.lanServer != b.lanServer ||
        a.tailscaleServer != b.tailscaleServer ||
        a.port != b.port ||
        a.name != b.name ||
        a.version != b.version ||
        a.authRequired != b.authRequired ||
        a.legacyMode != b.legacyMode;
  }
}

/// Extension on ServerInfo for copyWith functionality
extension ServerInfoCopyWith on ServerInfo {
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
}
