import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connected_client_row.dart';
import '../models/server_user_row.dart';
import '../services/dashboard_admin_api_service.dart';
import '../services/desktop_state_service.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_transcode_slots_service.dart';
import '../services/server_initialization_service.dart';
import '../widgets/admin_credentials_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/dashboard/dashboard_activity_tab.dart';
import '../widgets/dashboard/dashboard_overview_tab.dart';
import '../widgets/dashboard/dashboard_server_tab.dart';
import '../widgets/dashboard/dashboard_users_tab.dart';
import '../widgets/transcode_slots_dialog.dart';
import 'owner_setup_screen.dart';
import 'scanning_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final DesktopStateService _stateService = DesktopStateService();
  final ServerInitializationService _serverInit = ServerInitializationService();
  final DesktopTranscodeSlotsService _transcodeSlotsService =
      DesktopTranscodeSlotsService();

  static const _dockChannel = MethodChannel('ariami_desktop/dock');

  late final DashboardAdminApiService _adminApi;

  String? _musicFolderPath;
  String? _tailscaleIP;
  String? _lanIP;
  String? _ownerUsername;
  bool _isLoading = true;
  bool _isRefreshingAddresses = false;
  bool _hasOwnerAccount = false;
  int _connectedClients = 0;
  bool _isLoadingConnectedRows = false;
  bool _isLoadingServerUsers = false;
  bool _isCreatingUser = false;
  bool _isChangingPassword = false;
  String? _connectedRowsError;
  String? _serverUsersError;
  String? _userActivityError;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  List<ServerUserRow> _serverUserRows = const <ServerUserRow>[];
  List<UserActivityRow> _userActivityRows = const <UserActivityRow>[];
  bool _isLoadingUserActivity = false;
  final Set<String> _kickingDeviceIds = <String>{};
  final Set<String> _deletingUserIds = <String>{};
  Timer? _connectedRowsRefreshTimer;
  Timer? _userActivityRefreshTimer;
  Timer? _adminHeartbeatTimer;
  DateTime? _addressesUpdatedAt;
  TranscodeSlotsSnapshot? _transcodeSlotsSnapshot;
  bool _isSavingTranscodeSlots = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _adminApi = DashboardAdminApiService(
      httpServer: _httpServer,
      promptCredentials: () =>
          showAdminCredentialsDialog(context, ownerUsername: _ownerUsername),
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
        await _refreshServerUsers(showLoading: false);
        await _refreshUserActivity(showLoading: false);
        await _updateServerStatus();
      },
    );

    _loadData();
    _httpServer.libraryManager.addScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.addListener(_onClientConnectionChanged);
    _httpServer.onEndpointsChanged.listen((_) {
      unawaited(_updateServerStatus());
    });
    _connectedRowsRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshConnectedClientRows(showLoading: false));
      unawaited(_refreshServerUsers(showLoading: false));
      if (!_httpServer.isRunning) {
        unawaited(_autoStartServer());
      }
      unawaited(_updateServerStatus());
    });
    _userActivityRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshUserActivity(showLoading: false));
    });
    _adminHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_adminApi.sendAdminHeartbeat());
    });
  }

  void _cancelRefreshTimers() {
    _connectedRowsRefreshTimer?.cancel();
    _userActivityRefreshTimer?.cancel();
    _adminHeartbeatTimer?.cancel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _httpServer.libraryManager
        .removeScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.removeListener(_onClientConnectionChanged);
    _cancelRefreshTimers();
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
    unawaited(_refreshServerUsers(showLoading: false));
    unawaited(_refreshUserActivity(showLoading: false));
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    await _serverInit.configureLibraryCacheAndFeatureFlags(_httpServer);
    await _serverInit.ensureTranscodingAndArtworkServices(_httpServer);
    ServerInitializationService.configureNetworkDiscovery(
      _httpServer,
      _tailscaleService,
    );

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
    await _refreshOwnerState();
    await _refreshConnectedClientRows(showLoading: true);
    await _refreshServerUsers(showLoading: true);
    await _refreshUserActivity(showLoading: true);

    _transcodeSlotsSnapshot = await _transcodeSlotsService.getSnapshot();

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
      print('[Dashboard] Auto-starting server on $advertisedIp');
      await ServerInitializationService.initializeAuth(
          _httpServer, _stateService);
      await ServerInitializationService.applyDesktopDownloadLimits(_httpServer);
      final startResult = await ServerInitializationService.startListeningServer(
        httpServer: _httpServer,
        stateService: _stateService,
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
      );
      print('[Dashboard] Server listening on port ${startResult.port}');
      if (startResult.fallbackMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(startResult.fallbackMessage!),
            duration: const Duration(seconds: 5),
          ),
        );
      }

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
      await _refreshOwnerState();
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);

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
    final serverInfo = _httpServer.getServerInfo();
    final clientCount = _httpServer.connectionManager.clientCount;

    if (!mounted) return;
    setState(() {
      _tailscaleIP = serverInfo['tailscaleServer'] as String?;
      _lanIP = serverInfo['lanServer'] as String?;
      _connectedClients = clientCount;
      _addressesUpdatedAt = DateTime.now();
    });
  }

  String _formatAddressRefreshTime() {
    final value = _addressesUpdatedAt;
    if (value == null) {
      return 'Addresses have not been refreshed yet.';
    }

    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 5) {
      return 'Addresses updated just now.';
    }
    if (difference.inMinutes < 1) {
      return 'Addresses updated ${difference.inSeconds}s ago.';
    }
    if (difference.inHours < 1) {
      return 'Addresses updated ${difference.inMinutes}m ago.';
    }

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'Addresses updated at $hour:$minute.';
  }

  Future<void> _refreshServerAddresses() async {
    if (_isRefreshingAddresses) return;

    if (!_httpServer.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start the server before refreshing addresses.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isRefreshingAddresses = true;
    });

    try {
      final serverInfo = await _httpServer.refreshAdvertisedEndpoints();
      if (!mounted) return;
      setState(() {
        _tailscaleIP = serverInfo['tailscaleServer'] as String?;
        _lanIP = serverInfo['lanServer'] as String?;
        _connectedClients = _httpServer.connectionManager.clientCount;
        _addressesUpdatedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server addresses refreshed.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh addresses: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAddresses = false;
        });
      }
    }
  }

  Future<void> _refreshOwnerState() async {
    final hasOwner = await _stateService.hasOwnerAccount();
    final ownerUsername =
        hasOwner ? await _stateService.getOwnerUsername() : null;
    if (!mounted) return;
    setState(() {
      _hasOwnerAccount = hasOwner;
      _ownerUsername = ownerUsername;
    });
  }

  Future<void> _openOwnerSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OwnerSetupScreen(isOnboarding: false),
      ),
    );
    await _refreshOwnerState();
    await _updateServerStatus();
    await _refreshServerUsers(showLoading: true);
    await _refreshUserActivity(showLoading: true);
  }

  Future<List<_StoredDashboardUser>> _loadStoredUsers() async {
    final usersPath = await _stateService.getUsersFilePath();
    final usersFile = File(usersPath);
    if (!await usersFile.exists()) return const <_StoredDashboardUser>[];

    final raw = await usersFile.readAsString();
    if (raw.trim().isEmpty) return const <_StoredDashboardUser>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const <_StoredDashboardUser>[];
    final users = decoded['users'];
    if (users is! List) return const <_StoredDashboardUser>[];

    final parsed = <_StoredDashboardUser>[];
    for (final userEntry in users) {
      if (userEntry is! Map) continue;
      final userId = userEntry['userId']?.toString().trim();
      if (userId == null || userId.isEmpty) continue;

      final username = userEntry['username']?.toString().trim();
      final createdAtRaw = userEntry['createdAt']?.toString() ?? '';
      parsed.add(
        _StoredDashboardUser(
          userId: userId,
          username: (username == null || username.isEmpty)
              ? 'Unknown User'
              : username,
          createdAt: DateTime.tryParse(createdAtRaw),
          createdAtRaw: createdAtRaw,
        ),
      );
    }

    parsed.sort((a, b) {
      final createdCompare = a.createdAtRaw.compareTo(b.createdAtRaw);
      if (createdCompare != 0) return createdCompare;
      return a.userId.compareTo(b.userId);
    });
    return parsed;
  }

  Future<Map<String, String>> _loadUsernameMap() async {
    try {
      final users = await _loadStoredUsers();
      return <String, String>{
        for (final user in users) user.userId: user.username,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> _refreshServerUsers({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingServerUsers = true;
      });
    }

    try {
      final users = await _loadStoredUsers();
      final connectedDeviceCountByUserId = <String, int>{};
      for (final client
          in _httpServer.connectionManager.getConnectedClients()) {
        final userId = client.userId;
        if (userId == null || userId.isEmpty) continue;
        if (ConnectedClientFormatting.isDashboardControlClient(
          deviceId: client.deviceId,
          deviceName: client.deviceName,
        )) {
          continue;
        }
        connectedDeviceCountByUserId[userId] =
            (connectedDeviceCountByUserId[userId] ?? 0) + 1;
      }

      final adminUserId = users.isEmpty ? null : users.first.userId;
      final rows = users
          .map(
            (user) => ServerUserRow(
              userId: user.userId,
              username: user.username,
              createdAt: user.createdAt,
              isAdmin: adminUserId == user.userId,
              connectedDeviceCount:
                  connectedDeviceCountByUserId[user.userId] ?? 0,
            ),
          )
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _serverUserRows = rows;
        _serverUsersError = null;
        _isLoadingServerUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverUserRows = const <ServerUserRow>[];
        _serverUsersError = 'Failed to load registered users.';
        _isLoadingServerUsers = false;
      });
    }
  }

  Future<void> _refreshUserActivity({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingUserActivity = true;
      });
    }

    if (!_httpServer.isRunning) {
      if (!mounted) return;
      setState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityError = null;
        _isLoadingUserActivity = false;
      });
      return;
    }

    try {
      final rows = _httpServer.getActiveUserActivityRows();
      if (!mounted) return;
      setState(() {
        _userActivityRows = rows;
        _userActivityError = null;
        _isLoadingUserActivity = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityError =
            'Failed to load active download/transcode activity.';
        _isLoadingUserActivity = false;
      });
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
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to manage connected devices.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

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
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _kickingDeviceIds.remove(row.deviceId);
        });
      }
    }
  }

  Future<void> _promptCreateUser() async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set up the Owner account first to add users.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? dialogError;

    final payload = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create User'),
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
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                      ),
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
                    final confirmPassword = confirmPasswordController.text;
                    if (username.isEmpty || password.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Username and password are required.';
                      });
                      return;
                    }
                    if (password != confirmPassword) {
                      setDialogState(() {
                        dialogError = 'Passwords do not match.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop({
                      'username': username,
                      'password': password,
                    });
                  },
                  child: const Text('Create User'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    if (payload == null) return;

    setState(() {
      _isCreatingUser = true;
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/create-user',
        body: payload,
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Failed to create user'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created user ${payload['username']}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingUser = false;
        });
      }
    }
  }

  Future<void> _promptChangePassword({String? initialUsername}) async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to change passwords.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

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
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<bool> _confirmDeleteUser(ServerUserRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete User'),
          content: Text(
            'Delete "${row.username}" from this server?\n\n'
            'If they are currently logged in (including on mobile), '
            'their session will be logged out immediately.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete User'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _deleteUser(ServerUserRow row) async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to manage users.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    if (_deletingUserIds.contains(row.userId)) return;
    final confirmed = await _confirmDeleteUser(row);
    if (!confirmed) return;

    setState(() {
      _deletingUserIds.add(row.userId);
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/delete-user',
        body: <String, dynamic>{'userId': row.userId},
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Failed to delete user'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (row.isAdmin) {
        _adminApi.clearAdminSessionToken();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted user ${row.username}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await _refreshOwnerState();
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        setState(() {
          _deletingUserIds.remove(row.userId);
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

  Future<void> _promptEditTranscodeSlots() async {
    final snapshot = _transcodeSlotsSnapshot;
    if (snapshot == null || _isSavingTranscodeSlots) {
      return;
    }

    final result = await showTranscodeSlotsDialog(
      context,
      snapshot: snapshot,
    );
    if (result == null) {
      return;
    }

    setState(() {
      _isSavingTranscodeSlots = true;
    });

    try {
      final updated = result.reset
          ? await _transcodeSlotsService.setOverride(null)
          : await _transcodeSlotsService.setOverride(result.slots);

      if (!mounted) return;

      setState(() {
        _transcodeSlotsSnapshot = updated;
      });

      await _restartServerForTranscodeSlotsChange();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transcode slots updated to ${updated.effective}.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update transcode slots: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingTranscodeSlots = false;
        });
      }
    }
  }

  Future<void> _restartServerForTranscodeSlotsChange() async {
    final wasRunning = _httpServer.isRunning;
    if (wasRunning) {
      await _httpServer.stop();
      _adminApi.clearAdminSessionToken();
    }

    await _serverInit.recreateTranscodingService(_httpServer);

    if (!wasRunning) {
      return;
    }

    final tailscaleIp = await _tailscaleService.getTailscaleIp();
    final lanIp = await _tailscaleService.getLanIp();
    final advertisedIp = tailscaleIp ?? lanIp;
    if (advertisedIp == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Settings saved, but the server could not be restarted '
              'because no network address is available.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    await ServerInitializationService.initializeAuth(
        _httpServer, _stateService);
    await ServerInitializationService.applyDesktopDownloadLimits(_httpServer);
    final startResult = await ServerInitializationService.startListeningServer(
      httpServer: _httpServer,
      stateService: _stateService,
      advertisedIp: advertisedIp,
      tailscaleIp: tailscaleIp,
      lanIp: lanIp,
    );

    if (startResult.fallbackMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(startResult.fallbackMessage!),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    if (mounted) {
      setState(() {});
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
        final startResult =
            await ServerInitializationService.startListeningServer(
          httpServer: _httpServer,
          stateService: _stateService,
          advertisedIp: advertisedIp,
          tailscaleIp: tailscaleIp,
          lanIp: lanIp,
        );
        if (startResult.fallbackMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(startResult.fallbackMessage!),
              duration: const Duration(seconds: 5),
            ),
          );
        }

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
        await _refreshServerUsers(showLoading: false);
        await _refreshUserActivity(showLoading: false);
        await _refreshOwnerState();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is PortBindingException
                    ? e.toString()
                    : 'Failed to start server: $e',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }

    await _updateServerStatus();
    await _refreshOwnerState();
    await _refreshConnectedClientRows(showLoading: false);
    await _refreshServerUsers(showLoading: false);
    await _refreshUserActivity(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Activity'),
            Tab(text: 'Users'),
            Tab(text: 'Server'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : TabBarView(
              controller: _tabController,
              children: [
                DashboardOverviewTab(
                  httpServer: _httpServer,
                  connectedClients: _connectedClients,
                  hasOwnerAccount: _hasOwnerAccount,
                  onToggleServer: _toggleServer,
                  onOpenOwnerSetup: _openOwnerSetup,
                ),
                DashboardActivityTab(
                  isLoadingUserActivity: _isLoadingUserActivity,
                  userActivityError: _userActivityError,
                  userActivityRows: _userActivityRows,
                  isLoadingConnectedRows: _isLoadingConnectedRows,
                  connectedRowsError: _connectedRowsError,
                  connectedClientRows: _connectedClientRows,
                  hasOwnerAccount: _hasOwnerAccount,
                  kickingDeviceIds: _kickingDeviceIds,
                  onKick: _kickClient,
                  onOpenOwnerSetup: _openOwnerSetup,
                ),
                DashboardUsersTab(
                  isLoadingServerUsers: _isLoadingServerUsers,
                  serverUsersError: _serverUsersError,
                  serverUserRows: _serverUserRows,
                  hasOwnerAccount: _hasOwnerAccount,
                  isCreatingUser: _isCreatingUser,
                  isChangingPassword: _isChangingPassword,
                  deletingUserIds: _deletingUserIds,
                  onCreateUser: _promptCreateUser,
                  onChangePassword: (row) => _promptChangePassword(
                    initialUsername: row.username,
                  ),
                  onDeleteUser: _deleteUser,
                  onOpenOwnerSetup: _openOwnerSetup,
                ),
                DashboardServerTab(
                  musicFolderPath: _musicFolderPath,
                  transcodeSlotsSnapshot: _transcodeSlotsSnapshot,
                  isSavingTranscodeSlots: _isSavingTranscodeSlots,
                  lanIP: _lanIP,
                  tailscaleIP: _tailscaleIP,
                  addressRefreshTimeLabel: _formatAddressRefreshTime(),
                  isRefreshingAddresses: _isRefreshingAddresses,
                  onEditTranscodeSlots: _promptEditTranscodeSlots,
                  onRefreshAddresses: _refreshServerAddresses,
                  onChangeFolder: () {
                    Navigator.pushNamed(context, '/folder-selection');
                  },
                  onShowQr: () {
                    Navigator.pushNamed(context, '/connection');
                  },
                  onRescanLibrary: _musicFolderPath != null &&
                          _musicFolderPath!.isNotEmpty
                      ? _rescanLibrary
                      : null,
                ),
              ],
            ),
    );
  }
}

class _StoredDashboardUser {
  const _StoredDashboardUser({
    required this.userId,
    required this.username,
    required this.createdAt,
    required this.createdAtRaw,
  });

  final String userId;
  final String username;
  final DateTime? createdAt;
  final String createdAtRaw;
}
