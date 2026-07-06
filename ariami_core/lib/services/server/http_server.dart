import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'package:ariami_core/services/server/connection_manager.dart';
import 'package:ariami_core/services/server/streaming_service.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/library/library_manager.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/auth/user_store.dart'
    show UserExistsException;
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/download_job_models.dart';
import 'package:ariami_core/models/user_activity_row.dart';
import 'package:ariami_core/services/discovery/discovery_responder.dart';
import 'package:ariami_core/services/server/stream_tracker.dart';
import 'package:ariami_core/services/server/download_job_service.dart';
import 'package:ariami_core/services/server/metrics_service.dart';
import 'package:ariami_core/services/server/network_endpoint_monitor.dart';
import 'package:ariami_core/services/server/server_port_policy.dart';
import 'package:ariami_core/services/server/v2_handlers.dart';
import 'package:ariami_core/services/connect/connect_hub.dart';
import 'package:ariami_core/app_version.dart';
import 'package:ariami_core/services/setup/music_folder_path_helper.dart';
import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/listening_stats_store.dart';
import 'package:ariami_core/models/pinned_item.dart';
import 'package:ariami_core/services/pins/pinned_item_store.dart';
import 'package:ariami_core/services/playlists/playlist_edit_store.dart';

part 'http_server_limiters.dart';
part 'http_server_parts/lifecycle_and_config_part.dart';
part 'http_server_parts/router_registration_part.dart';
part 'http_server_parts/middleware_and_metrics_part.dart';
part 'http_server_parts/setup_and_stats_handlers_part.dart';
part 'http_server_parts/auth_and_admin_handlers_part.dart';
part 'http_server_parts/connection_handlers_part.dart';
part 'http_server_parts/download_jobs_handlers_part.dart';
part 'http_server_parts/library_and_artwork_handlers_part.dart';
part 'http_server_parts/stream_and_download_handlers_part.dart';
part 'http_server_parts/websocket_and_static_part.dart';
part 'http_server_parts/listening_stats_handlers_part.dart';
part 'http_server_parts/pins_handlers_part.dart';
part 'http_server_parts/playlist_edits_handlers_part.dart';

/// HTTP server for Ariami desktop application (Singleton)
class AriamiHttpServer {
  // Singleton instance
  static final AriamiHttpServer _instance = AriamiHttpServer._internal();
  factory AriamiHttpServer() => _instance;
  AriamiHttpServer._internal() {
    _downloadLimiter = _WeightedFairDownloadLimiter(
      maxConcurrent: _maxConcurrentDownloads,
      maxQueue: _maxDownloadQueue,
      maxConcurrentPerUser: _maxConcurrentDownloadsPerUser,
      maxQueuePerUser: _maxDownloadQueuePerUser,
    );
  }

  HttpServer? _server;
  final ConnectionManager _connectionManager = ConnectionManager();
  final StreamingService _streamingService = StreamingService();
  final LibraryManager _libraryManager = LibraryManager();
  final AuthService _authService = AuthService();
  final StreamTracker _streamTracker = StreamTracker();
  TranscodingService? _transcodingService;
  ArtworkService? _artworkService;
  String? _tailscaleIp;
  String? _lanIp;
  String? _advertisedIp; // The IP to show in QR code (Tailscale or LAN IP)
  int _port = 8080;
  int? _attemptedPort;
  bool _portFallbackUsed = false;
  final List<WebSocketChannel> _webSocketClients = [];
  final Map<WebSocketChannel, String> _webSocketDeviceIds = {};
  final AriamiConnectHub _connectHub = AriamiConnectHub();

  /// Per-account listening statistics (event log + rollups). Initialized in
  /// [initializeAuth] next to the auth stores; stays open for the process
  /// lifetime so server restarts within one run don't churn the database.
  ListeningStatsStore? _listeningStatsStore;

  /// Account-scoped album/playlist shortcuts. This database is deliberately
  /// separate from the catalog so a library rescan cannot remove user data.
  PinnedItemStore? _pinnedItemStore;

  /// Account-scoped server playlist edits. This database is deliberately
  /// separate from the catalog so a library rescan cannot remove user data.
  PlaylistEditStore? _playlistEditStore;

  /// User profile pictures stored beside auth/account data.
  String? _userAvatarsDirectoryPath;

  // Download concurrency controls (multi-user fairness)
  static const int _defaultMaxConcurrentDownloads = 4;
  static const int _defaultMaxDownloadQueue = 10000;
  static const int _defaultMaxConcurrentDownloadsPerUser = 2;
  static const int _defaultMaxDownloadQueuePerUser = 10000;
  static const int _defaultMaxDownloadJobQueuePerUser = 10000;
  int _maxConcurrentDownloads = _defaultMaxConcurrentDownloads;
  int _maxDownloadQueue = _defaultMaxDownloadQueue;
  int _maxConcurrentDownloadsPerUser = _defaultMaxConcurrentDownloadsPerUser;
  int _maxDownloadQueuePerUser = _defaultMaxDownloadQueuePerUser;
  late _WeightedFairDownloadLimiter _downloadLimiter;
  final Map<String, int> _inFlightDownloadTranscodesByUser = <String, int>{};

  // Artwork request quotas (only enforced for server-managed artwork resizing).
  static const int _defaultMaxConcurrentArtworkPerUser = 2;
  static const int _defaultMaxArtworkQueuePerUser = 8;
  final Map<String, _SimpleLimiter> _artworkUserLimiters = {};
  static const int _defaultRetryAfterSeconds = 5;
  static const String _desktopDashboardAdminDeviceId =
      'desktop_dashboard_admin';
  static const String _desktopDashboardAdminDeviceName =
      'Ariami Desktop Dashboard';
  static const String _cliWebDashboardDeviceName = 'Ariami CLI Web Dashboard';
  static const String _clientTypeDashboard = 'dashboard';
  static const String _clientTypeUserDevice = 'user_device';
  static const String _clientTypeUnauthenticated = 'unauthenticated';
  bool _libraryListenersRegistered = false;
  void Function()? _scanCompleteListener;
  void Function()? _durationsReadyListener;

  // Store music folder path (set from desktop state)
  String? _musicFolderPath;

  // Auth flags for server info (multi-user support)
  bool _authRequired = false;
  bool _legacyMode = true;
  AriamiFeatureFlags _featureFlags = const AriamiFeatureFlags();
  final AriamiMetricsService _metricsService = AriamiMetricsService();
  final Map<String, _AuthEndpointRateLimitTracker> _authEndpointAttempts =
      <String, _AuthEndpointRateLimitTracker>{};
  final Map<String, DateTime> _registrationTokens = <String, DateTime>{};
  int _lastBroadcastSyncToken = 0;
  final Random _secureRandom = Random.secure();
  static const Duration _registrationTokenTtl = Duration(minutes: 10);

  // Store web assets path for serving static files
  String? _webAssetsPath;

  // Callback for getting Tailscale status (optional, for CLI use)
  Future<Map<String, dynamic>> Function()? _tailscaleStatusCallback;

  // Network endpoint discovery and change notifications
  Future<NetworkEndpoints> Function()? _endpointDiscoveryCallback;
  NetworkEndpointMonitor? _endpointMonitor;

  // Answers LAN discovery probes (UDP beacon + mDNS) while the server runs,
  // so client apps find this server without scanning. Best-effort:
  // its failures never affect the HTTP server. Hosts may opt out before
  // start() via [setDiscoveryResponderEnabled].
  final DiscoveryResponder _discoveryResponder = DiscoveryResponder();
  bool _discoveryResponderEnabled = true;
  final StreamController<Map<String, dynamic>> _endpointsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Callbacks for setup operations (optional, for CLI use)
  Future<String?> Function()? _getConfiguredMusicFolderPathCallback;
  Future<bool> Function(String path)? _setMusicFolderCallback;
  Future<bool> Function()? _startScanCallback;
  Future<Map<String, dynamic>> Function()? _getScanStatusCallback;
  Future<bool> Function()? _markSetupCompleteCallback;
  Future<bool> Function()? _getSetupStatusCallback;
  Future<Map<String, dynamic>> Function()? _transitionToBackgroundCallback;

  // Callbacks for transcode slot configuration (optional, for CLI use)
  Future<TranscodeSlotsSnapshot> Function()? _getTranscodeSlotsSnapshotCallback;
  Future<TranscodeSlotsSnapshot> Function(int? slots)?
      _setTranscodeSlotsOverrideCallback;

  String _generateRegistrationTokenValue() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      final byte = _secureRandom.nextInt(256);
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Generate a short, human-typeable invite code (canonical form: uppercase,
  /// no separators). Uses an unambiguous alphabet (no 0/1/I/L/O/U) so it can be
  /// read aloud or relayed without confusion. Displayed grouped (e.g. XXXX-XXXX)
  /// by clients, but stored/validated in this canonical form.
  String _generateInviteCodeValue() {
    const alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(alphabet[_secureRandom.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}
