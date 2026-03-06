import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/models/feature_flags.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_state_service.dart';
import 'scanning_screen.dart';

/// Global transcoding service instance for desktop app
TranscodingService? _transcodingService;

/// Global artwork service instance for desktop app (thumbnail generation)
ArtworkService? _artworkService;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _dashboardAdminDeviceId = 'desktop_dashboard_admin';
  static const String _dashboardAdminDeviceName = 'Ariami Desktop Dashboard';
  static const String _cliWebDashboardDeviceName = 'Ariami CLI Web Dashboard';
  static const String _clientTypeDashboard = 'dashboard';
  static const String _clientTypeUserDevice = 'user_device';
  static const String _clientTypeUnauthenticated = 'unauthenticated';

  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final DesktopStateService _stateService = DesktopStateService();

  // Method channel for macOS-specific features (dock icon, App Nap)
  static const _dockChannel = MethodChannel('ariami_desktop/dock');

  String? _musicFolderPath;
  String? _tailscaleIP;
  bool _isLoading = true;
  int _connectedClients = 0;
  bool _isLoadingConnectedRows = false;
  bool _isChangingPassword = false;
  String? _connectedRowsError;
  String? _adminSessionToken;
  List<_ConnectedClientRow> _connectedClientRows =
      const <_ConnectedClientRow>[];
  final Set<String> _kickingDeviceIds = <String>{};
  Timer? _connectedRowsRefreshTimer;
  Timer? _adminHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen for library scan completion
    _httpServer.libraryManager.addScanCompleteListener(_onLibraryScanComplete);
    // Listen for client connection changes
    _httpServer.connectionManager.addListener(_onClientConnectionChanged);
    _connectedRowsRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshConnectedClientRows(showLoading: false));
    });
    _adminHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_sendAdminHeartbeat());
    });
  }

  @override
  void dispose() {
    _httpServer.libraryManager
        .removeScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.removeListener(_onClientConnectionChanged);
    _connectedRowsRefreshTimer?.cancel();
    _adminHeartbeatTimer?.cancel();
    super.dispose();
  }

  void _onLibraryScanComplete() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onClientConnectionChanged() {
    if (mounted) {
      setState(() {
        _connectedClients = _httpServer.connectionManager.clientCount;
      });
    }
    unawaited(_refreshConnectedClientRows(showLoading: false));
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final featureFlags = _loadFeatureFlagsFromEnvironment();
    _validateFeatureFlagInvariantsOrThrow(featureFlags);

    // Load music folder path from shared preferences
    final prefs = await SharedPreferences.getInstance();
    _musicFolderPath = prefs.getString('music_folder_path');

    // Fix existing bad paths with /Volumes/Macintosh HD prefix
    if (_musicFolderPath != null &&
        _musicFolderPath!.startsWith('/Volumes/Macintosh HD')) {
      _musicFolderPath =
          _musicFolderPath!.replaceFirst('/Volumes/Macintosh HD', '');
      await prefs.setString('music_folder_path', _musicFolderPath!);
      print('[Dashboard] Fixed bad music folder path: $_musicFolderPath');
    }

    // Configure metadata cache for fast re-scans
    final appDir = await getApplicationSupportDirectory();
    final cachePath = p.join(appDir.path, 'metadata_cache.json');
    _httpServer.libraryManager.setCachePath(cachePath);

    if (featureFlags.enableV2Api &&
        _httpServer.libraryManager.createCatalogRepository() == null) {
      throw StateError(
        'Invalid startup configuration: enableV2Api=true requires catalog '
        'repository availability. Failed to initialize catalog at $cachePath.',
      );
    }

    _httpServer.setFeatureFlags(featureFlags);

    // Initialize transcoding service for quality-based streaming
    // Desktop settings - more resources available than Pi
    if (_transcodingService == null) {
      final transcodingCachePath = p.join(appDir.path, 'transcoded_cache');
      _transcodingService = TranscodingService(
        cacheDirectory: transcodingCachePath,
        maxCacheSizeMB: 4096, // 4GB cache limit for desktop
        maxConcurrency: 2, // Allow 2 concurrent transcodes
        maxDownloadConcurrency: 6, // Higher concurrency for downloads
      );
      _httpServer.setTranscodingService(_transcodingService!);
      print(
          '[Dashboard] Transcoding service initialized at: $transcodingCachePath');

      // Check FFmpeg availability
      _transcodingService!.isFFmpegAvailable().then((available) {
        if (!available) {
          print(
              '[Dashboard] Warning: FFmpeg not found - transcoding will be disabled');
        }
      });
    }

    // Initialize artwork service for thumbnail generation
    if (_artworkService == null) {
      final artworkCachePath = p.join(appDir.path, 'artwork_cache');
      _artworkService = ArtworkService(
        cacheDirectory: artworkCachePath,
        maxCacheSizeMB: 256, // 256MB cache limit for thumbnails
      );
      _httpServer.setArtworkService(_artworkService!);
      print('[Dashboard] Artwork service initialized at: $artworkCachePath');
    }

    // Get Tailscale IP and server status
    await _updateServerStatus();
    await _refreshConnectedClientRows(showLoading: true);

    setState(() {
      _isLoading = false;
    });

    // Auto-start server if not already running
    if (!_httpServer.isRunning) {
      await _autoStartServer();
    }
  }

  /// Automatically start server on app launch
  Future<void> _autoStartServer() async {
    final ip = await _tailscaleService.getTailscaleIp();
    if (ip == null) {
      print('[Dashboard] Auto-start skipped: Tailscale not connected');
      return;
    }

    try {
      print('[Dashboard] Auto-starting server on $ip:8080');
      await _initializeAuthIfNeeded();
      _httpServer.setDownloadLimits(
        maxConcurrent: Platform.isMacOS ? 30 : 10,
        maxQueue: Platform.isMacOS ? 400 : 120,
        maxConcurrentPerUser: Platform.isMacOS ? 10 : 3,
        maxQueuePerUser: Platform.isMacOS ? 200 : 50,
      );
      await _httpServer.start(advertisedIp: ip, port: 8080);

      // Prevent App Nap on macOS to keep server responsive when minimized
      if (Platform.isMacOS) {
        try {
          await _dockChannel.invokeMethod('preventAppNap');
          print('[Dashboard] App Nap prevention enabled');
        } catch (e) {
          print('[Dashboard] Failed to prevent App Nap: $e');
        }
      }

      if (mounted) {
        setState(() {});
      }
      await _refreshConnectedClientRows(showLoading: false);

      // Navigate to scanning screen if music folder is set and library is empty
      if (_musicFolderPath != null &&
          _musicFolderPath!.isNotEmpty &&
          _httpServer.libraryManager.library == null &&
          mounted) {
        print(
            '[Dashboard] Auto-navigating to scanning screen: $_musicFolderPath');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ScanningScreen(musicFolderPath: _musicFolderPath!),
          ),
        );
      }
    } catch (e) {
      print('[Dashboard] Auto-start server failed: $e');
    }
  }

  Future<void> _updateServerStatus() async {
    // Get Tailscale IP
    final ip = await _tailscaleService.getTailscaleIp();

    // Get connected clients count
    final clientCount = _httpServer.connectionManager.clientCount;

    setState(() {
      _tailscaleIP = ip;
      _connectedClients = clientCount;
    });
  }

  Future<Map<String, String>> _loadUsernameMap() async {
    try {
      final usersPath = await _stateService.getUsersFilePath();
      final usersFile = File(usersPath);
      if (!await usersFile.exists()) return const <String, String>{};

      final raw = await usersFile.readAsString();
      if (raw.trim().isEmpty) return const <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const <String, String>{};
      final users = decoded['users'];
      if (users is! List) return const <String, String>{};

      final map = <String, String>{};
      for (final userEntry in users) {
        if (userEntry is! Map) continue;
        final userId = userEntry['userId']?.toString();
        final username = userEntry['username']?.toString();
        if (userId == null || userId.isEmpty) continue;
        map[userId] =
            (username == null || username.isEmpty) ? 'Unknown User' : username;
      }
      return map;
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> _refreshConnectedClientRows({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingConnectedRows = true;
      });
    }

    try {
      final usernameById = await _loadUsernameMap();
      final clients = _httpServer.connectionManager.getConnectedClients();
      final rows = clients
          .map(
            (client) => _ConnectedClientRow(
              deviceId: client.deviceId,
              deviceName: client.deviceName,
              clientType: _resolveConnectedClientType(
                deviceId: client.deviceId,
                deviceName: client.deviceName,
                userId: client.userId,
              ),
              userId: client.userId,
              username: client.userId == null
                  ? null
                  : usernameById[client.userId!] ?? client.userId!,
              connectedAt: client.connectedAt,
              lastHeartbeat: client.lastHeartbeat,
            ),
          )
          .toList()
        ..sort((a, b) => b.lastHeartbeat.compareTo(a.lastHeartbeat));

      if (!mounted) return;
      setState(() {
        _connectedClientRows = rows;
        _connectedRowsError = null;
        _isLoadingConnectedRows = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connectedClientRows = const <_ConnectedClientRow>[];
        _connectedRowsError = 'Failed to load connected users/devices.';
        _isLoadingConnectedRows = false;
      });
    }
  }

  Uri _buildApiUri(
    String path, {
    bool includeDashboardDeviceIdentity = false,
  }) {
    final info = _httpServer.getServerInfo();
    final host = (info['server'] as String?) ?? '127.0.0.1';
    final port = info['port'] as int? ?? 8080;
    final uri = Uri.parse('http://$host:$port$path');
    if (!includeDashboardDeviceIdentity) {
      return uri;
    }

    final queryParams = <String, String>{...uri.queryParameters};
    queryParams.putIfAbsent('deviceId', () => _dashboardAdminDeviceId);
    queryParams.putIfAbsent('deviceName', () => _dashboardAdminDeviceName);
    return uri.replace(queryParameters: queryParams);
  }

  Future<_DashboardHttpResponse> _sendApiRequest({
    required String method,
    required String path,
    String? bearerToken,
    Map<String, dynamic>? body,
    bool includeDashboardDeviceIdentity = false,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        _buildApiUri(
          path,
          includeDashboardDeviceIdentity: includeDashboardDeviceIdentity,
        ),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      }
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();

      Map<String, dynamic>? jsonBody;
      if (responseBody.isNotEmpty) {
        try {
          final decoded = jsonDecode(responseBody);
          if (decoded is Map<String, dynamic>) {
            jsonBody = decoded;
          }
        } catch (_) {}
      }

      return _DashboardHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        jsonBody: jsonBody,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_AdminCredentials?> _promptAdminCredentials() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String? dialogError;

    final credentials = await showDialog<_AdminCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Admin Authentication'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final username = usernameController.text.trim();
                    final password = passwordController.text;
                    if (username.isEmpty || password.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Username and password are required.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _AdminCredentials(username: username, password: password),
                    );
                  },
                  child: const Text('Login'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    return credentials;
  }

  Future<String?> _ensureAdminSessionToken({bool forcePrompt = false}) async {
    if (!forcePrompt &&
        _adminSessionToken != null &&
        _adminSessionToken!.isNotEmpty) {
      return _adminSessionToken;
    }

    if (!_httpServer.isRunning) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server is not running')),
        );
      }
      return null;
    }

    final credentials = await _promptAdminCredentials();
    if (credentials == null) return null;

    try {
      final response = await _sendApiRequest(
        method: 'POST',
        path: '/api/auth/login',
        body: <String, dynamic>{
          'username': credentials.username,
          'password': credentials.password,
          'deviceId': _dashboardAdminDeviceId,
          'deviceName': _dashboardAdminDeviceName,
        },
      );

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Admin login failed'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return null;
      }

      final token = response.jsonBody?['sessionToken'] as String?;
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Admin login failed: missing session token'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return null;
      }

      _adminSessionToken = token;
      unawaited(_sendAdminHeartbeat());
      return token;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin login error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    }
  }

  Future<_DashboardHttpResponse?> _sendAdminRequest({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    var token = await _ensureAdminSessionToken();
    if (token == null) return null;

    var response = await _sendApiRequest(
      method: 'POST',
      path: path,
      bearerToken: token,
      body: body,
      includeDashboardDeviceIdentity: true,
    );

    if (response.statusCode == 401) {
      _adminSessionToken = null;
      token = await _ensureAdminSessionToken(forcePrompt: true);
      if (token == null) return null;
      response = await _sendApiRequest(
        method: 'POST',
        path: path,
        bearerToken: token,
        body: body,
        includeDashboardDeviceIdentity: true,
      );
    }

    return response;
  }

  Future<void> _sendAdminHeartbeat() async {
    if (!mounted || !_httpServer.isRunning) return;
    final token = _adminSessionToken;
    if (token == null || token.isEmpty) return;

    try {
      final response = await _sendApiRequest(
        method: 'GET',
        path: '/api/me',
        bearerToken: token,
        includeDashboardDeviceIdentity: true,
      );
      if (response.statusCode == 401) {
        _adminSessionToken = null;
        _httpServer.connectionManager.unregisterClient(_dashboardAdminDeviceId);
        await _refreshConnectedClientRows(showLoading: false);
        await _updateServerStatus();
      }
    } catch (_) {
      // Ignore transient heartbeat failures.
    }
  }

  Future<void> _kickClient(_ConnectedClientRow row) async {
    if (_kickingDeviceIds.contains(row.deviceId)) return;
    setState(() {
      _kickingDeviceIds.add(row.deviceId);
    });

    try {
      final response = await _sendAdminRequest(
        path: '/api/admin/kick-client',
        body: <String, dynamic>{'deviceId': row.deviceId},
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response.errorMessage ?? 'Failed to disconnect device'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected ${row.deviceName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshConnectedClientRows(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _kickingDeviceIds.remove(row.deviceId);
        });
      }
    }
  }

  Future<void> _promptChangePassword({String? initialUsername}) async {
    final usernameController = TextEditingController(text: initialUsername);
    final passwordController = TextEditingController();
    String? dialogError;

    final payload = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change User Password'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'New Password'),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final username = usernameController.text.trim();
                    final newPassword = passwordController.text;
                    if (username.isEmpty || newPassword.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Username and new password are required.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      <String, String>{
                        'username': username,
                        'newPassword': newPassword,
                      },
                    );
                  },
                  child: const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    if (payload == null) return;

    setState(() {
      _isChangingPassword = true;
    });

    try {
      final response = await _sendAdminRequest(
        path: '/api/admin/change-password',
        body: <String, dynamic>{
          'username': payload['username']!,
          'newPassword': payload['newPassword']!,
        },
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response.errorMessage ?? 'Failed to change password'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password updated for ${payload['username']}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshConnectedClientRows(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Widget _buildConnectedUsersTable() {
    if (_isLoadingConnectedRows) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_connectedRowsError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Text(
          _connectedRowsError!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (_connectedClientRows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: const Text(
          'No connected devices.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('User')),
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Connected')),
          DataColumn(label: Text('Last Heartbeat')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _connectedClientRows.map((row) {
          final isKicking = _kickingDeviceIds.contains(row.deviceId);
          final userLabel = row.username ?? row.userId ?? 'Unauthenticated';
          return DataRow(cells: [
            DataCell(Text(userLabel)),
            DataCell(Text(_formatConnectedDeviceLabel(row))),
            DataCell(Text(_formatDateTime(row.connectedAt))),
            DataCell(Text(_formatDateTime(row.lastHeartbeat))),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: isKicking ? null : () => _kickClient(row),
                    child: isKicking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kick'),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _isChangingPassword
                        ? null
                        : () => _promptChangePassword(
                              initialUsername: row.username,
                            ),
                    child: const Text('Change Password'),
                  ),
                ],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  AriamiFeatureFlags _loadFeatureFlagsFromEnvironment() {
    bool parseFlag(String key, {required bool defaultValue}) {
      final value = Platform.environment[key];
      if (value == null) return defaultValue;

      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'on';
    }

    return AriamiFeatureFlags(
      enableV2Api: parseFlag('ARIAMI_ENABLE_V2_API', defaultValue: true),
      enableCatalogWrite:
          parseFlag('ARIAMI_ENABLE_CATALOG_WRITE', defaultValue: false),
      enableCatalogRead:
          parseFlag('ARIAMI_ENABLE_CATALOG_READ', defaultValue: false),
      enableArtworkPrecompute:
          parseFlag('ARIAMI_ENABLE_ARTWORK_PRECOMPUTE', defaultValue: false),
      enableDownloadJobs:
          parseFlag('ARIAMI_ENABLE_DOWNLOAD_JOBS', defaultValue: true),
      enableApiScopedAuthForCliWeb: parseFlag(
        'ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB',
        defaultValue: true,
      ),
    );
  }

  void _validateFeatureFlagInvariantsOrThrow(AriamiFeatureFlags flags) {
    if (flags.enableDownloadJobs && !flags.enableV2Api) {
      throw StateError(
        'Invalid feature flag configuration: enableDownloadJobs=true '
        'requires enableV2Api=true.',
      );
    }
  }

  /// Initialize auth services for multi-user support (idempotent)
  Future<void> _initializeAuthIfNeeded() async {
    await _stateService.ensureAuthConfigDir();
    final usersFilePath = await _stateService.getUsersFilePath();
    final sessionsFilePath = await _stateService.getSessionsFilePath();
    await _httpServer.initializeAuth(
      usersFilePath: usersFilePath,
      sessionsFilePath: sessionsFilePath,
    );
  }

  Future<void> _rescanLibrary() async {
    if (_musicFolderPath == null || _musicFolderPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a music folder first'),
            duration: Duration(seconds: 3),
            // backgroundColor: Colors.transparent, // Let theme handle it
          ),
        );
      }
      return;
    }

    print('[Dashboard] Manual rescan triggered: $_musicFolderPath');

    // Navigate to scanning screen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ScanningScreen(musicFolderPath: _musicFolderPath!),
        ),
      );
    }
  }

  Future<void> _toggleServer() async {
    if (_httpServer.isRunning) {
      // Stop server
      await _httpServer.stop();
      _adminSessionToken = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Start server
      final ip = await _tailscaleService.getTailscaleIp();
      if (ip == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot start server: Tailscale not connected'),
              duration: Duration(seconds: 3),
              // backgroundColor: Colors.red, // Let theme handle it
            ),
          );
        }
        return;
      }

      try {
        // Start the HTTP server
        await _initializeAuthIfNeeded();
        _httpServer.setDownloadLimits(
          maxConcurrent: Platform.isMacOS ? 30 : 10,
          maxQueue: Platform.isMacOS ? 400 : 120,
          maxConcurrentPerUser: Platform.isMacOS ? 10 : 3,
          maxQueuePerUser: Platform.isMacOS ? 200 : 50,
        );
        await _httpServer.start(advertisedIp: ip, port: 8080);

        // Debug: Check music folder path
        print('[Dashboard] Music folder path: "$_musicFolderPath"');
        print('[Dashboard] Is null: ${_musicFolderPath == null}');
        print('[Dashboard] Is empty: ${_musicFolderPath?.isEmpty ?? true}');

        // Trigger library scan if music folder is set
        if (_musicFolderPath != null && _musicFolderPath!.isNotEmpty) {
          print('[Dashboard] Triggering library scan: $_musicFolderPath');
          // Scan in background, don't await
          _httpServer.libraryManager
              .scanMusicFolder(_musicFolderPath!)
              .then((_) {
            print('[Dashboard] Library scan completed');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Music library scan completed'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }).catchError((e) {
            print('[Dashboard] Library scan error: $e');
          });
        } else {
          print(
              '[Dashboard] ERROR: Music folder path not set! Cannot scan library.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Warning: Music folder not set'),
                duration: Duration(seconds: 3),
                // backgroundColor: Colors.orange, // Let theme handle it
              ),
            );
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Server started'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        await _refreshConnectedClientRows(showLoading: false);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start server: $e'),
              duration: const Duration(seconds: 3),
              // backgroundColor: Colors.red, // Let theme handle it
            ),
          );
        }
      }
    }

    await _updateServerStatus();
    await _refreshConnectedClientRows(showLoading: false);
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _resolveConnectedClientType({
    required String deviceId,
    required String deviceName,
    required String? userId,
  }) {
    if (_isDashboardControlClient(deviceId: deviceId, deviceName: deviceName)) {
      return _clientTypeDashboard;
    }
    if (userId == null) {
      return _clientTypeUnauthenticated;
    }
    return _clientTypeUserDevice;
  }

  bool _isDashboardControlClient({
    required String deviceId,
    required String deviceName,
  }) {
    return deviceId == _dashboardAdminDeviceId ||
        deviceName == _dashboardAdminDeviceName ||
        deviceName == _cliWebDashboardDeviceName;
  }

  String _formatConnectedDeviceLabel(_ConnectedClientRow row) {
    if (row.clientType == _clientTypeDashboard) {
      return '${row.deviceName} (Dashboard)';
    }
    return row.deviceName;
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    bool isActive = true,
  }) {
    // Redesigned to match Premium Dark aesthetic
    // No colored icons unless active (and then white/monochrome)
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary.withOpacity(0.1)
                    : theme.colorScheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w600, // Semi-bold for high contrast
                      color: isActive
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use simple B&W logic for server status button
    final isRunning = _httpServer.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server Status Section
                  const Text(
                    'Server Status',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status Cards
                  _buildInfoCard(
                    title: 'Status',
                    value: isRunning ? 'Active' : 'Stopped',
                    icon: isRunning
                        ? Icons.check_circle_rounded
                        : Icons.stop_circle_rounded,
                    isActive: isRunning,
                  ),
                  const SizedBox(height: 12),

                  if (isRunning) ...[
                    _buildInfoCard(
                      title: 'Connected Clients',
                      value: _connectedClients.toString(),
                      icon: Icons.devices_rounded,
                      isActive: _connectedClients > 0,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      title: 'Connected Users',
                      value: _httpServer.connectedUsers.toString(),
                      icon: Icons.people_rounded,
                      isActive: _httpServer.connectedUsers > 0,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      title: 'Active Sessions',
                      value: _httpServer.activeSessions.toString(),
                      icon: Icons.vpn_key_rounded,
                      isActive: _httpServer.activeSessions > 0,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Main Toggle Button
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _toggleServer,
                      icon: Icon(isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(isRunning ? 'Stop Server' : 'Start Server'),
                      style: ElevatedButton.styleFrom(
                        // Bigger button with status-specific styling
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        // Stop: Dark BG with Red Outline/Text. Start: White BG with Black Text.
                        backgroundColor:
                            isRunning ? const Color(0xFF141414) : Colors.white,
                        foregroundColor:
                            isRunning ? Colors.redAccent : Colors.black,
                        side: isRunning
                            ? const BorderSide(
                                color: Colors.redAccent, width: 2)
                            : null,
                        elevation: isRunning ? 0 : 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Auth Required Banner
                  if (_httpServer.authRequired)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded,
                              color: Colors.orange.shade300, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Authentication is enabled. Users must log in to access this server.',
                              style: TextStyle(
                                color: Colors.orange.shade200,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Configuration Section
                  const Text(
                    'Configuration',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Music Folder',
                    value: _musicFolderPath ?? 'Not configured',
                    icon: Icons.folder_rounded,
                    isActive: _musicFolderPath != null,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Tailscale IP',
                    value: _tailscaleIP ?? 'Not connected',
                    icon: Icons.cloud_done_rounded,
                    isActive: _tailscaleIP != null,
                  ),
                  const SizedBox(height: 32),

                  // Library Statistics
                  const Text(
                    'Library Statistics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    title: 'Albums',
                    value: _httpServer.libraryManager.library?.totalAlbums
                            .toString() ??
                        '0',
                    icon: Icons.album_rounded,
                    isActive:
                        (_httpServer.libraryManager.library?.totalAlbums ?? 0) >
                            0,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Songs',
                    value: _httpServer.libraryManager.library?.totalSongs
                            .toString() ??
                        '0',
                    icon: Icons.music_note_rounded,
                    isActive:
                        (_httpServer.libraryManager.library?.totalSongs ?? 0) >
                            0,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: 'Last Scan',
                    value: _httpServer.libraryManager.lastScanTime != null
                        ? _formatDateTime(
                            _httpServer.libraryManager.lastScanTime!)
                        : 'Never',
                    icon: Icons.access_time_rounded,
                    isActive: _httpServer.libraryManager.lastScanTime != null,
                  ),
                  const SizedBox(height: 32),

                  // Connected Users & Devices
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Connected Users & Devices',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isChangingPassword
                            ? null
                            : () => _promptChangePassword(),
                        icon: _isChangingPassword
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text('Change Password'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildConnectedUsersTable(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Quick Actions
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action Grid
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/folder-selection');
                          },
                          icon: const Icon(Icons.drive_file_move_rounded,
                              size: 20),
                          label: const Text('Change Folder'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF333333)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/connection');
                          },
                          icon: const Icon(Icons.qr_code_rounded, size: 20),
                          label: const Text('Show QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF333333)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _musicFolderPath != null &&
                              _musicFolderPath!.isNotEmpty
                          ? _rescanLibrary
                          : null,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Rescan Library'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF333333)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DashboardHttpResponse {
  const _DashboardHttpResponse({
    required this.statusCode,
    required this.body,
    this.jsonBody,
  });

  final int statusCode;
  final String body;
  final Map<String, dynamic>? jsonBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  String? get errorMessage {
    final error = jsonBody?['error'];
    if (error is Map<String, dynamic>) {
      return error['message'] as String?;
    }
    return null;
  }
}

class _AdminCredentials {
  const _AdminCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}

class _ConnectedClientRow {
  const _ConnectedClientRow({
    required this.deviceId,
    required this.deviceName,
    required this.clientType,
    required this.connectedAt,
    required this.lastHeartbeat,
    this.userId,
    this.username,
  });

  final String deviceId;
  final String deviceName;
  final String clientType;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;
  final String? userId;
  final String? username;
}
