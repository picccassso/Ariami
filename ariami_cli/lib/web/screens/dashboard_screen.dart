import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/websocket_models.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';
import '../utils/constants.dart';
import '../widgets/dashboard/auth_required_banner.dart';
import '../widgets/dashboard/change_password_dialog.dart';
import '../widgets/dashboard/connected_clients_section.dart';
import '../widgets/dashboard/library_stats_section.dart';
import '../widgets/dashboard/quick_actions_section.dart';
import '../widgets/dashboard/server_info_card.dart';
import '../widgets/dashboard/server_status_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
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
  bool _isChangingPassword = false;
  String? _connectedClientsError;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  final Set<String> _kickingDeviceIds = <String>{};

  Timer? _refreshTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadServerStats();

    // Periodic refresh to avoid stale UI if any WebSocket event is missed.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadServerStats();
    });

    _connectWebSocket();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
        await _redirectToLogin();
        return;
      }

      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};

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
            _isLoading = false;
          });
        }

        await _loadConnectedClients(showLoading: false);
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
  }

  Future<void> _redirectToLogin() async {
    if (!mounted) return;
    await _authService.clearSessionToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

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
        _isLoadingConnectedClients = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLogin();
        return;
      }

      if (!mounted) return;
      setState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsError = e.isForbidden
            ? 'Admin privileges required to view connected users and devices.'
            : e.message;
        _isLoadingConnectedClients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsError = 'Failed to load connected users and devices.';
        _isLoadingConnectedClients = false;
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
        await _redirectToLogin();
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
        await _redirectToLogin();
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
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : CustomScrollView(
                slivers: [
                  // Floating Header
                  SliverAppBar(
                    expandedHeight: 120,
                    floating: true,
                    pinned: true,
                    backgroundColor: AppTheme.pureBlack.withOpacity(0.8),
                    flexibleSpace: FlexibleSpaceBar(
                      centerTitle: true,
                      title: Text(
                        'DASHBOARD',
                        style: Theme.of(context).appBarTheme.titleTextStyle,
                      ),
                    ),
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
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ServerStatusCard(
                            serverRunning: _serverRunning,
                            isScanning: _isScanning,
                            pulseController: _pulseController,
                          ),
                          const SizedBox(height: 24),
                          if (_authRequired) const AuthRequiredBanner(),
                          LibraryStatsSection(
                            songCount: _songCount,
                            albumCount: _albumCount,
                            connectedClients: _connectedClients,
                            connectedUsers: _connectedUsers,
                            activeSessions: _activeSessions,
                            lastScanTimeFormatted: _formatLastScanTime(),
                          ),
                          const SizedBox(height: 48),
                          ConnectedClientsSection(
                            clients: _connectedClientRows,
                            isLoading: _isLoadingConnectedClients,
                            isChangingPassword: _isChangingPassword,
                            error: _connectedClientsError,
                            kickingDeviceIds: _kickingDeviceIds,
                            onKick: _kickClient,
                            onChangePassword: () => _promptChangePassword(),
                            onChangePasswordForUser: (username) =>
                                _promptChangePassword(
                                    initialUsername: username),
                            formatClientTime: _formatClientTime,
                            formatDeviceLabel: _formatDeviceLabel,
                          ),
                          const SizedBox(height: 48),
                          QuickActionsSection(
                            isScanning: _isScanning,
                            onRescanLibrary: _rescanLibrary,
                            onViewQRCode: _viewQRCode,
                          ),
                          const SizedBox(height: 56),
                          const ServerInfoCard(),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
