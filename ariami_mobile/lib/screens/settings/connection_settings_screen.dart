import '../../utils/responsive.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/server_info.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/theme_service.dart';
import '../../utils/server_disconnect.dart';
import '../../widgets/settings/connection_status_card.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

class RetryConnectionResult {
  const RetryConnectionResult({
    required this.restored,
    required this.didAuthFail,
    this.failureCode,
    this.failureMessage,
  });

  final bool restored;
  final bool didAuthFail;
  final String? failureCode;
  final String? failureMessage;

  factory RetryConnectionResult.fromConnectionService(
    ConnectionService connectionService, {
    required bool restored,
  }) {
    return RetryConnectionResult(
      restored: restored,
      didAuthFail: connectionService.didLastRestoreFailForAuth,
      failureCode: connectionService.lastRestoreFailureCode,
      failureMessage: connectionService.lastRestoreFailureMessage,
    );
  }
}

typedef RetryConnectionAttempt = Future<RetryConnectionResult> Function();

class ConnectionSettingsScreen extends StatefulWidget {
  const ConnectionSettingsScreen({
    super.key,
    this.retryConnectionAttempt,
  });

  final RetryConnectionAttempt? retryConnectionAttempt;

  @override
  State<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState extends State<ConnectionSettingsScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  late Stream<bool> _connectionStream;
  StreamSubscription<OfflineMode>? _offlineSubscription;
  bool _isOfflineModeEnabled = false;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _connectionStream = _connectionService.connectionStateStream;
    _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    _loadDeviceName();

    // Listen to offline state changes
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
        });
      }
    });
  }

  Future<void> _loadDeviceName() async {
    final deviceName = await _connectionService.getCurrentDeviceName();
    if (!mounted) return;
    setState(() {
      _deviceName = deviceName;
    });
  }

  @override
  void dispose() {
    _offlineSubscription?.cancel();
    super.dispose();
  }

  void _handleLogout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'LOG OUT',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of this account?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark
                ? Colors.grey[400]
                : colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark
                    ? Colors.grey[500]
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _logout();
            },
            child: Text(
              'LOG OUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final serverInfo = _connectionService.serverInfo;

    try {
      await _connectionService.logout();
      await ThemeService().setThemeSource(ThemeSource.systemNeutral);
      if (!mounted) return;

      if (serverInfo != null) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          '/auth/login',
          (route) => false,
          arguments: serverInfo,
        );
      } else {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _retryConnection() async {
    try {
      if (widget.retryConnectionAttempt != null) {
        await widget.retryConnectionAttempt!.call();
      } else {
        await _runDefaultRetryConnectionAttempt();
      }
    } catch (_) {
      // Retry failed silently.
    }
  }

  Future<RetryConnectionResult> _runDefaultRetryConnectionAttempt() async {
    final restored = await _connectionService.tryRestoreConnection();
    return RetryConnectionResult.fromConnectionService(
      _connectionService,
      restored: restored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ContentWidthLimiter(
          child: ListView(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerScrollBottomPadding(context) + 20,
        ),
        children: [
          StreamBuilder<ServerInfo?>(
            stream: _connectionService.serverInfoStream,
            initialData: _connectionService.serverInfo,
            builder: (context, serverSnapshot) {
              final serverInfo = serverSnapshot.data;

              return Column(
                children: [
                  if (_isOfflineModeEnabled) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: Color(0xFFFFB300), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You are offline. Disable Offline Mode in Settings to reconnect, or use Disconnect Server below to reset this device.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  StreamBuilder<bool>(
                    stream: _connectionStream,
                    initialData: _connectionService.isConnected,
                    builder: (context, snapshot) {
                      final isConnected = snapshot.data ?? false;

                      final ConnectionStatus status;
                      if (_isOfflineModeEnabled) {
                        status = ConnectionStatus.offline;
                      } else if (isConnected) {
                        status = ConnectionStatus.connected;
                      } else {
                        status = ConnectionStatus.offline;
                      }

                      return ConnectionStatusCard(
                        status: status,
                        serverInfo: serverInfo,
                        lastSyncTime: DateTime.now(),
                        onRetry: (isConnected || _isOfflineModeEnabled)
                            ? null
                            : _retryConnection,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_connectionService.username != null) ...[
                    SettingsSection(
                      title: 'Account',
                      tiles: [
                        SettingsTile(
                          icon: Icons.account_circle_rounded,
                          title: 'Username',
                          subtitle: _connectionService.username!,
                        ),
                        if ((_connectionService.userId ?? '').isNotEmpty)
                          SettingsTile(
                            icon: Icons.badge_rounded,
                            title: 'User ID',
                            subtitle: _connectionService.userId,
                          ),
                        SettingsTile(
                          icon: Icons.smartphone_rounded,
                          title: 'Device',
                          subtitle: _deviceName ?? 'Mobile Device',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (serverInfo != null && !_isOfflineModeEnabled) ...[
                    SettingsSection(
                      title: 'Server Information',
                      tiles: [
                        SettingsTile(
                          icon: Icons.dns_rounded,
                          title: 'Server Name',
                          subtitle: serverInfo.name,
                        ),
                        SettingsTile(
                          icon: serverInfo.isUsingLocalNetworkRoute
                              ? Icons.wifi_rounded
                              : Icons.vpn_lock_rounded,
                          title: 'Route',
                          subtitle: serverInfo.routeLabel,
                        ),
                        SettingsTile(
                          icon: Icons.lan_rounded,
                          title: 'Active Address',
                          subtitle: serverInfo.server,
                        ),
                        if (serverInfo.lanServer != null)
                          SettingsTile(
                            icon: Icons.home_work_rounded,
                            title: 'LAN Address',
                            subtitle: serverInfo.lanServer!,
                          ),
                        if (serverInfo.tailscaleServer != null)
                          SettingsTile(
                            icon: Icons.public_rounded,
                            title: 'Tailscale Address',
                            subtitle: serverInfo.tailscaleServer!,
                          ),
                        SettingsTile(
                          icon: Icons.tag_rounded,
                          title: 'Port',
                          subtitle: serverInfo.port.toString(),
                        ),
                        SettingsTile(
                          icon: Icons.info_rounded,
                          title: 'Version',
                          subtitle: serverInfo.version,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (!_isOfflineModeEnabled &&
                      _connectionService.username != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _handleLogout,
                          icon: const Icon(Icons.person_remove_alt_1_rounded,
                              size: 20),
                          label: const Text(
                            'Log Out',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: colorScheme.surface,
                            foregroundColor: colorScheme.onSurface,
                            side: BorderSide(
                              color:
                                  colorScheme.outline.withValues(alpha: 0.35),
                            ),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () => showDisconnectServerDialog(context),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: const Text(
                          'Disconnect Server',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        style: disconnectServerButtonStyle(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ],
      )),
    );
  }
}
