import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/websocket_models.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';
import '../utils/constants.dart';

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
              backgroundColor: AppTheme.surfaceBlack,
              title: const Text(
                'Change User Password',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
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
                        dialogError = 'Username and new password are required.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      <String, String>{
                        'username': username,
                        'newPassword': password,
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

  Widget _buildConnectedClientsSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CONNECTED USERS & DEVICES',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed:
                    _isChangingPassword ? null : () => _promptChangePassword(),
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
                label: const Text('CHANGE PASSWORD'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingConnectedClients)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_connectedClientsError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                _connectedClientsError!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            )
          else if (_connectedClientRows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No connected devices.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(label: Text('USER')),
                  DataColumn(label: Text('DEVICE')),
                  DataColumn(label: Text('CONNECTED')),
                  DataColumn(label: Text('LAST HEARTBEAT')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: _connectedClientRows.map((client) {
                  final isKicking = _kickingDeviceIds.contains(client.deviceId);
                  final userLabel =
                      client.username ?? client.userId ?? 'Unauthenticated';
                  return DataRow(
                    cells: [
                      DataCell(Text(userLabel)),
                      DataCell(Text(_formatDeviceLabel(client))),
                      DataCell(Text(_formatClientTime(client.connectedAt))),
                      DataCell(Text(_formatClientTime(client.lastHeartbeat))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed:
                                  isKicking ? null : () => _kickClient(client),
                              child: isKicking
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Kick'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _isChangingPassword
                                  ? null
                                  : () => _promptChangePassword(
                                      initialUsername: client.username),
                              child: const Text('Change Password'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
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
                          // Server Status Card (Glassmorphism)
                          Container(
                            decoration: AppTheme.glassDecoration,
                            padding: const EdgeInsets.all(24.0),
                            child: Row(
                              children: [
                                FadeTransition(
                                  opacity: _pulseController,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: _serverRunning
                                          ? Colors.white
                                          : Colors.redAccent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_serverRunning
                                                  ? Colors.white
                                                  : Colors.redAccent)
                                              .withOpacity(0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'SERVER STATUS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textSecondary,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _serverRunning
                                          ? 'ACTIVE & STREAMING'
                                          : 'SERVER STOPPED',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: _serverRunning
                                            ? Colors.white
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                if (_isScanning)
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'SCANNING...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Auth Required Banner
                          if (_authRequired)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.orange.withOpacity(0.3)),
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

                          // Library Statistics Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'LIBRARY STATISTICS',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'LAST SCAN: ${_formatLastScanTime().toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Stats Grid
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 900 ? 3 : 1,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 2.2,
                            children: [
                              _buildStatCard(
                                icon: Icons.music_note_rounded,
                                count: '$_songCount',
                                label: 'SONGS FOUND',
                              ),
                              _buildStatCard(
                                icon: Icons.album_rounded,
                                count: '$_albumCount',
                                label: 'ALBUMS INDEXED',
                              ),
                              _buildStatCard(
                                icon: Icons.devices_rounded,
                                count: '$_connectedClients',
                                label: 'ACTIVE CLIENTS',
                              ),
                              _buildStatCard(
                                icon: Icons.people_rounded,
                                count: '$_connectedUsers',
                                label: 'CONNECTED USERS',
                              ),
                              _buildStatCard(
                                icon: Icons.vpn_key_rounded,
                                count: '$_activeSessions',
                                label: 'ACTIVE SESSIONS',
                              ),
                            ],
                          ),
                          const SizedBox(height: 48),

                          _buildConnectedClientsSection(),
                          const SizedBox(height: 48),

                          // Actions Header
                          const Text(
                            'QUICK ACTIONS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _isScanning ? null : _rescanLibrary,
                                  icon: _isScanning
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black),
                                        )
                                      : const Icon(Icons.refresh_rounded),
                                  label: Text(_isScanning
                                      ? 'SCANNING...'
                                      : 'RESCAN LIBRARY'),
                                ),
                              ),
                              SizedBox(
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _viewQRCode,
                                  icon: const Icon(Icons.qr_code_2_rounded),
                                  label: const Text('SHOW QR CODE'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.surfaceBlack,
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: AppTheme.borderGrey),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 56),

                          // Info Card
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceBlack,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.borderGrey),
                            ),
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        size: 24, color: Colors.white),
                                    const SizedBox(width: 16),
                                    Text(
                                      'SERVER INFO',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'The Ariami server is broadcasting securely. Mobile clients can connect via your local network or Tailscale address.',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.textSecondary,
                                      height: 1.6),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'For the best experience, ensure your mobile device is on the same network or has Tailscale enabled.',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.textSecondary,
                                      height: 1.6),
                                ),
                              ],
                            ),
                          ),
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

  Widget _buildStatCard({
    required IconData icon,
    required String count,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
