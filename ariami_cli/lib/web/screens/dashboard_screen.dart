import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';
import '../utils/constants.dart';
import '../widgets/dashboard/dashboard_activity_tab.dart';
import '../widgets/dashboard/dashboard_overview_tab.dart';
import '../widgets/dashboard/dashboard_server_tab.dart';
import '../widgets/dashboard/change_password_dialog.dart';
import '../widgets/dashboard/transcode_slots_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  static const String _dashboardDeviceName = 'Ariami CLI Web Dashboard';
  static const String _desktopDashboardDeviceName = 'Ariami Desktop Dashboard';
  static const String _clientTypeDashboard = 'dashboard';

  final WebSetupService _setupService = WebSetupService();
  final WebAuthService _authService = WebAuthService();
  final WebWebSocketService _wsService = WebWebSocketService();
  late final WebApiClient _apiClient = WebApiClient(
    tokenProvider: _authService.getSessionToken,
    deviceIdProvider: _authService.getOrCreateDeviceId,
    deviceName: _dashboardDeviceName,
  );
  StreamSubscription<WsMessage>? _wsSubscription;

  bool _serverRunning = true;
  int _songCount = 0;
  int _albumCount = 0;
  int _connectedClients = 0;
  int _connectedUsers = 0;
  int _activeSessions = 0;
  bool _authRequired = false;
  bool _isScanning = false;
  String? _lastScanTime;
  bool _isLoading = true;
  bool _isLoadingConnectedClients = false;
  bool _isLoadingUserActivity = true;
  bool _isChangingPassword = false;
  bool _isAdmin = false;
  bool _isLoadingTranscodeSlots = false;
  bool _isSavingTranscodeSlots = false;
  String? _transcodeSlotsError;
  TranscodeSlotsSnapshot? _transcodeSlotsSnapshot;
  String? _connectedClientsError;
  String? _userActivityError;
  bool _connectedClientsOwnerForbidden = false;
  bool _userActivityOwnerForbidden = false;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  List<UserActivityRow> _userActivityRows = const <UserActivityRow>[];
  final Set<String> _kickingDeviceIds = <String>{};

  String? _dashboardLanServer;
  String? _dashboardTailscaleServer;
  DateTime? _dashboardEndpointsUpdatedAt;
  bool _isRefreshingAddresses = false;

  Timer? _refreshTimer;
  Timer? _userActivityRefreshTimer;
  late AnimationController _pulseController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadServerStats();

    // Periodic refresh to avoid stale UI if any WebSocket event is missed.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadServerStats();
    });
    _userActivityRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_loadUserActivity(showLoading: false));
    });

    _connectWebSocket();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    _userActivityRefreshTimer?.cancel();
    _wsSubscription?.cancel();
    _wsService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadServerStats() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await _apiClient.get(
        '/api/stats?_=$timestamp',
        includeDeviceIdentity: true,
      );

      if (response.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(response.errorCode);
        return;
      }

      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};

        String? lan;
        String? ts;
        try {
          final infoResp =
              await _apiClient.get('/api/server-info', includeAuth: false);
          if (infoResp.statusCode == 200 && infoResp.jsonBody != null) {
            final j = infoResp.jsonBody!;
            lan = j['lanServer'] as String?;
            ts = j['tailscaleServer'] as String?;
          }
        } catch (_) {
          // Ignore; card falls back to descriptive text only.
        }

        if (mounted) {
          setState(() {
            _songCount = data['songCount'] as int? ?? 0;
            _albumCount = data['albumCount'] as int? ?? 0;
            _connectedClients = data['connectedClients'] as int? ?? 0;
            _connectedUsers = data['connectedUsers'] as int? ?? 0;
            _activeSessions = data['activeSessions'] as int? ?? 0;
            _authRequired = data['authRequired'] as bool? ?? false;
            _isScanning = data['isScanning'] as bool? ?? false;
            _lastScanTime = data['lastScanTime'] as String?;
            _serverRunning = data['serverRunning'] as bool? ?? true;
            _dashboardLanServer = lan;
            _dashboardTailscaleServer = ts;
            _dashboardEndpointsUpdatedAt = DateTime.now();
            _isLoading = false;
          });
        }

        await _loadConnectedClients(showLoading: false);
        await _loadUserActivity(showLoading: false);
        await _loadTranscodeSlots(showLoading: false);
      }
    } catch (e) {
      debugPrint('Error loading server stats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTranscodeSlots({required bool showLoading}) async {
    final isAdmin = await _authService.isCurrentUserAdmin();
    if (!mounted) return;

    setState(() {
      _isAdmin = isAdmin;
      if (showLoading) {
        _isLoadingTranscodeSlots = true;
      }
      if (!isAdmin) {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = null;
        _isLoadingTranscodeSlots = false;
      }
    });

    if (!isAdmin) {
      return;
    }

    try {
      final snapshot = await _apiClient.getTranscodeSlots();
      if (!mounted) return;
      setState(() {
        _transcodeSlotsSnapshot = snapshot;
        _transcodeSlotsError = null;
        _isLoadingTranscodeSlots = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      if (!mounted) return;
      setState(() {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = e.message;
        _isLoadingTranscodeSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = 'Failed to load transcode slots.';
        _isLoadingTranscodeSlots = false;
      });
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
          ? await _apiClient.setTranscodeSlots(reset: true)
          : await _apiClient.setTranscodeSlots(slots: result.slots);
      if (!mounted) return;
      setState(() {
        _transcodeSlotsSnapshot = updated;
        _transcodeSlotsError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved. Restart the Ariami server for changes to take effect.',
          ),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save transcode slots.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
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

  Future<void> _refreshServerAddresses() async {
    if (_isRefreshingAddresses) return;

    setState(() {
      _isRefreshingAddresses = true;
    });

    try {
      final response = await _apiClient.post('/api/server-info/refresh');
      if (response.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(response.errorCode);
        return;
      }

      if (response.statusCode == 200 && response.jsonBody != null && mounted) {
        final data = response.jsonBody!;
        setState(() {
          _dashboardLanServer = data['lanServer'] as String?;
          _dashboardTailscaleServer = data['tailscaleServer'] as String?;
          _dashboardEndpointsUpdatedAt = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing server addresses: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAddresses = false;
        });
      }
    }
  }

  void _connectWebSocket() {
    _wsService.connect(
      onConnected: () {
        _loadServerStats();
      },
      deviceIdProvider: _authService.getOrCreateDeviceId,
      sessionTokenProvider: _authService.getSessionToken,
      onAuthRequired: () {
        _redirectToLogin();
      },
    );

    _wsSubscription = _wsService.messages.listen((message) {
      switch (message.type) {
        case WsMessageType.clientConnected:
          final clientMessage = ClientConnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.clientDisconnected:
          final clientMessage =
              ClientDisconnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.libraryUpdated:
        case WsMessageType.syncTokenAdvanced:
          _loadServerStats();
          break;
      }
    });
  }

  void _updateClientCount(int count) {
    if (mounted) {
      setState(() {
        _connectedClients = count;
      });
    }
    unawaited(_loadConnectedClients(showLoading: false));
    unawaited(_loadUserActivity(showLoading: false));
  }

  Future<void> _redirectToLogin() async {
    if (!mounted) return;
    await _authService.clearSessionToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<bool> _redirectToLoginIfSessionCannotRecover(String? errorCode) async {
    final hasToken = await _authService.hasSessionToken();
    if (!hasToken || errorCode == AuthErrorCodes.sessionExpired) {
      await _redirectToLogin();
      return true;
    }
    return false;
  }

  Future<void> _switchToOwnerLogin() async {
    await _authService.clearSessionToken();
    if (!mounted) return;
    Navigator.pushNamed(context, '/login');
  }

  static const String _ownerClientsMessage =
      'Owner privileges required to view connected users and devices.';
  static const String _ownerActivityMessage =
      'Owner privileges required to view user activity.';

  Future<void> _rescanLibrary() async {
    try {
      final success = await _setupService.startScan();

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Library rescan started'),
            backgroundColor: AppTheme.surfaceBlack,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadServerStats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start library rescan'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting rescan: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _viewQRCode() async {
    Navigator.pushNamed(context, '/qr-code');
  }

  String _formatLastScanTime() {
    if (_lastScanTime == null) return 'Never';

    try {
      final scanTime = DateTime.parse(_lastScanTime!);
      final now = DateTime.now();
      final difference = now.difference(scanTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _loadConnectedClients({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingConnectedClients = true;
      });
    }

    try {
      final clients = await _apiClient.getConnectedClients();
      clients.sort((a, b) {
        final left = a.lastHeartbeat ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.lastHeartbeat ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });

      if (!mounted) return;
      setState(() {
        _connectedClientRows = clients;
        _connectedClientsError = null;
        _connectedClientsOwnerForbidden = false;
        _isLoadingConnectedClients = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }

      if (!mounted) return;
      setState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsOwnerForbidden = e.isForbidden;
        _connectedClientsError =
            e.isForbidden ? _ownerClientsMessage : e.message;
        _isLoadingConnectedClients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsError = 'Failed to load connected users and devices.';
        _connectedClientsOwnerForbidden = false;
        _isLoadingConnectedClients = false;
      });
    }
  }

  Future<void> _loadUserActivity({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingUserActivity = true;
      });
    }

    try {
      final rows = await _apiClient.getUserActivity();
      if (!mounted) return;
      setState(() {
        _userActivityRows = rows;
        _userActivityError = null;
        _userActivityOwnerForbidden = false;
        _isLoadingUserActivity = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }

      if (!mounted) return;
      setState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityOwnerForbidden = e.isForbidden;
        _userActivityError = e.isForbidden ? _ownerActivityMessage : e.message;
        _isLoadingUserActivity = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityError = 'Failed to load active user activity.';
        _userActivityOwnerForbidden = false;
        _isLoadingUserActivity = false;
      });
    }
  }

  String _formatClientTime(DateTime? value) {
    if (value == null) return '—';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  bool _isDashboardControlClient(ConnectedClientRow client) {
    if (client.clientType == _clientTypeDashboard) {
      return true;
    }

    // Backward compatibility when older servers do not provide clientType.
    return client.deviceName == _dashboardDeviceName ||
        client.deviceName == _desktopDashboardDeviceName;
  }

  String _formatDeviceLabel(ConnectedClientRow client) {
    if (_isDashboardControlClient(client)) {
      return '${client.deviceName} (Dashboard)';
    }
    return client.deviceName;
  }

  Future<void> _kickClient(ConnectedClientRow client) async {
    if (_kickingDeviceIds.contains(client.deviceId)) return;
    setState(() {
      _kickingDeviceIds.add(client.deviceId);
    });

    try {
      await _apiClient.kickClient(client.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Disconnected ${client.deviceName}${client.username == null ? '' : ' (${client.username})'}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadServerStats();
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to disconnect selected device.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _kickingDeviceIds.remove(client.deviceId);
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
      await _apiClient.changePassword(
        username: payload['username']!,
        newPassword: payload['newPassword']!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password updated for ${payload['username']}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadServerStats();
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to change password.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : Column(
                children: [
                  AppBar(
                    backgroundColor: AppTheme.pureBlack.withValues(alpha: 0.8),
                    title: Text(
                      'DASHBOARD',
                      style: Theme.of(context).appBarTheme.titleTextStyle,
                    ),
                    centerTitle: true,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _loadServerStats,
                        tooltip: 'Refresh Stats',
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_2_rounded),
                        onPressed: _viewQRCode,
                        tooltip: 'Show QR Code',
                      ),
                      const SizedBox(width: 8),
                    ],
                    bottom: TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.white,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTheme.textSecondary,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                      tabs: const [
                        Tab(text: 'OVERVIEW'),
                        Tab(text: 'ACTIVITY'),
                        Tab(text: 'SERVER'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        DashboardOverviewTab(
                          serverRunning: _serverRunning,
                          isScanning: _isScanning,
                          pulseController: _pulseController,
                          authRequired: _authRequired,
                          songCount: _songCount,
                          albumCount: _albumCount,
                          connectedClients: _connectedClients,
                          connectedUsers: _connectedUsers,
                          activeSessions: _activeSessions,
                          lastScanTimeFormatted: _formatLastScanTime(),
                          onRescanLibrary: _rescanLibrary,
                          onViewQRCode: _viewQRCode,
                        ),
                        DashboardActivityTab(
                          userActivityRows: _userActivityRows,
                          isLoadingUserActivity: _isLoadingUserActivity,
                          userActivityError: _userActivityError,
                          userActivityOwnerForbidden:
                              _userActivityOwnerForbidden,
                          onSignInAsOwner: _userActivityOwnerForbidden
                              ? _switchToOwnerLogin
                              : null,
                          connectedClientRows: _connectedClientRows,
                          isLoadingConnectedClients: _isLoadingConnectedClients,
                          isChangingPassword: _isChangingPassword,
                          connectedClientsError: _connectedClientsError,
                          connectedClientsOwnerForbidden:
                              _connectedClientsOwnerForbidden,
                          kickingDeviceIds: _kickingDeviceIds,
                          onKick: _kickClient,
                          onChangePassword: () => _promptChangePassword(),
                          onChangePasswordForUser: (username) =>
                              _promptChangePassword(initialUsername: username),
                          formatClientTime: _formatClientTime,
                          formatDeviceLabel: _formatDeviceLabel,
                        ),
                        DashboardServerTab(
                          lanServer: _dashboardLanServer,
                          tailscaleServer: _dashboardTailscaleServer,
                          lastUpdatedLabel: _formatEndpointRefreshTime(),
                          isRefreshingAddresses: _isRefreshingAddresses,
                          onRefreshAddresses: _refreshServerAddresses,
                          isAdmin: _isAdmin,
                          transcodeSlotsSnapshot: _transcodeSlotsSnapshot,
                          isLoadingTranscodeSlots: _isLoadingTranscodeSlots,
                          isSavingTranscodeSlots: _isSavingTranscodeSlots,
                          transcodeSlotsError: _transcodeSlotsError,
                          onEditTranscodeSlots: _promptEditTranscodeSlots,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String? _formatEndpointRefreshTime() {
    final value = _dashboardEndpointsUpdatedAt;
    if (value == null) return null;

    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 5) return 'just now';
    if (difference.inMinutes < 1) return '${difference.inSeconds}s ago';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'at $hour:$minute';
  }
}
