import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connected_client_row.dart';
import '../services/dashboard_admin_api_service.dart';
import '../services/desktop_state_service.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/server_initialization_service.dart';
import '../utils/date_formatter.dart';
import '../widgets/admin_credentials_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/connected_users_table.dart';
import '../widgets/info_card.dart';
import 'scanning_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final DesktopStateService _stateService = DesktopStateService();
  final ServerInitializationService _serverInit = ServerInitializationService();

  static const _dockChannel = MethodChannel('ariami_desktop/dock');

  late final DashboardAdminApiService _adminApi;

  String? _musicFolderPath;
  String? _tailscaleIP;
  bool _isLoading = true;
  int _connectedClients = 0;
  bool _isLoadingConnectedRows = false;
  bool _isChangingPassword = false;
  String? _connectedRowsError;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  final Set<String> _kickingDeviceIds = <String>{};
  Timer? _connectedRowsRefreshTimer;
  Timer? _adminHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    _adminApi = DashboardAdminApiService(
      httpServer: _httpServer,
      promptCredentials: () => showAdminCredentialsDialog(context),
      showMessage: (message, {bool isError = false}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.redAccent : null,
          ),
        );
      },
      isMounted: () => mounted,
      onSessionInvalidated: () async {
        await _refreshConnectedClientRows(showLoading: false);
        await _updateServerStatus();
      },
    );

    _loadData();
    _httpServer.libraryManager.addScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.addListener(_onClientConnectionChanged);
    _connectedRowsRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshConnectedClientRows(showLoading: false));
    });
    _adminHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_adminApi.sendAdminHeartbeat());
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

    await _serverInit.configureLibraryCacheAndFeatureFlags(_httpServer);
    await _serverInit.ensureTranscodingAndArtworkServices(_httpServer);

    final prefs = await SharedPreferences.getInstance();
    _musicFolderPath = prefs.getString('music_folder_path');

    if (_musicFolderPath != null &&
        _musicFolderPath!.startsWith('/Volumes/Macintosh HD')) {
      _musicFolderPath =
          _musicFolderPath!.replaceFirst('/Volumes/Macintosh HD', '');
      await prefs.setString('music_folder_path', _musicFolderPath!);
      print('[Dashboard] Fixed bad music folder path: $_musicFolderPath');
    }

    await _updateServerStatus();
    await _refreshConnectedClientRows(showLoading: true);

    setState(() {
      _isLoading = false;
    });

    if (!_httpServer.isRunning) {
      await _autoStartServer();
    }
  }

  Future<void> _autoStartServer() async {
    final tailscaleIp = await _tailscaleService.getTailscaleIp();
    final lanIp = await _tailscaleService.getLanIp();
    final advertisedIp = tailscaleIp ?? lanIp;

    if (advertisedIp == null) {
      print('[Dashboard] Auto-start skipped: no network address available');
      return;
    }

    try {
      print('[Dashboard] Auto-starting server on $advertisedIp:8080');
      await ServerInitializationService.initializeAuth(
          _httpServer, _stateService);
      await ServerInitializationService.applyDesktopDownloadLimits(_httpServer);
      await _httpServer.start(
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
        port: 8080,
      );

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
    final ip = await _tailscaleService.getTailscaleIp();
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
            (client) => ConnectedClientRow(
              deviceId: client.deviceId,
              deviceName: client.deviceName,
              clientType: ConnectedClientFormatting.resolveConnectedClientType(
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
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedRowsError = 'Failed to load connected users/devices.';
        _isLoadingConnectedRows = false;
      });
    }
  }

  Future<void> _kickClient(ConnectedClientRow row) async {
    if (_kickingDeviceIds.contains(row.deviceId)) return;
    setState(() {
      _kickingDeviceIds.add(row.deviceId);
    });

    try {
      final response = await _adminApi.sendAdminRequest(
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
    final payload = await showChangePasswordDialog(
      context,
      initialUsername: initialUsername,
    );
    if (payload == null) return;

    setState(() {
      _isChangingPassword = true;
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/change-password',
        body: <String, dynamic>{
          'username': payload.username,
          'newPassword': payload.newPassword,
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
            content: Text('Password updated for ${payload.username}'),
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

  Future<void> _rescanLibrary() async {
    if (_musicFolderPath == null || _musicFolderPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a music folder first'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    print('[Dashboard] Manual rescan triggered: $_musicFolderPath');

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
      await _httpServer.stop();
      _adminApi.clearAdminSessionToken();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      final tailscaleIp = await _tailscaleService.getTailscaleIp();
      final lanIp = await _tailscaleService.getLanIp();
      final advertisedIp = tailscaleIp ?? lanIp;
      if (advertisedIp == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Cannot start server: no network address available'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      try {
        await ServerInitializationService.initializeAuth(
            _httpServer, _stateService);
        await ServerInitializationService.applyDesktopDownloadLimits(
            _httpServer);
        await _httpServer.start(
          advertisedIp: advertisedIp,
          tailscaleIp: tailscaleIp,
          lanIp: lanIp,
          port: 8080,
        );

        print('[Dashboard] Music folder path: "$_musicFolderPath"');
        print('[Dashboard] Is null: ${_musicFolderPath == null}');
        print('[Dashboard] Is empty: ${_musicFolderPath?.isEmpty ?? true}');

        if (_musicFolderPath != null && _musicFolderPath!.isNotEmpty) {
          print('[Dashboard] Triggering library scan: $_musicFolderPath');
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
            ),
          );
        }
      }
    }

    await _updateServerStatus();
    await _refreshConnectedClientRows(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'Server Status',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoCard(
                    title: 'Status',
                    value: isRunning ? 'Active' : 'Stopped',
                    icon: isRunning
                        ? Icons.check_circle_rounded
                        : Icons.stop_circle_rounded,
                    isActive: isRunning,
                  ),
                  const SizedBox(height: 12),
                  if (isRunning) ...[
                    InfoCard(
                      title: 'Connected Clients',
                      value: _connectedClients.toString(),
                      icon: Icons.devices_rounded,
                      isActive: _connectedClients > 0,
                    ),
                    const SizedBox(height: 12),
                    InfoCard(
                      title: 'Connected Users',
                      value: _httpServer.connectedUsers.toString(),
                      icon: Icons.people_rounded,
                      isActive: _httpServer.connectedUsers > 0,
                    ),
                    const SizedBox(height: 12),
                    InfoCard(
                      title: 'Active Sessions',
                      value: _httpServer.activeSessions.toString(),
                      icon: Icons.vpn_key_rounded,
                      isActive: _httpServer.activeSessions > 0,
                    ),
                    const SizedBox(height: 12),
                  ],
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
                        padding: const EdgeInsets.symmetric(vertical: 20),
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
                  const Text(
                    'Configuration',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoCard(
                    title: 'Music Folder',
                    value: _musicFolderPath ?? 'Not configured',
                    icon: Icons.folder_rounded,
                    isActive: _musicFolderPath != null,
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Tailscale IP',
                    value: _tailscaleIP ?? 'Not connected',
                    icon: Icons.cloud_done_rounded,
                    isActive: _tailscaleIP != null,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Library Statistics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InfoCard(
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
                  InfoCard(
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
                  InfoCard(
                    title: 'Last Scan',
                    value: _httpServer.libraryManager.lastScanTime != null
                        ? formatDashboardDateTime(
                            _httpServer.libraryManager.lastScanTime!)
                        : 'Never',
                    icon: Icons.access_time_rounded,
                    isActive: _httpServer.libraryManager.lastScanTime != null,
                  ),
                  const SizedBox(height: 32),
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
                      child: ConnectedUsersTable(
                        isLoading: _isLoadingConnectedRows,
                        errorMessage: _connectedRowsError,
                        rows: _connectedClientRows,
                        kickingDeviceIds: _kickingDeviceIds,
                        isChangingPassword: _isChangingPassword,
                        onKick: _kickClient,
                        onChangePassword: (row) => _promptChangePassword(
                          initialUsername: row.username,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
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
