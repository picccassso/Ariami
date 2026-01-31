import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../widgets/settings/connection_status_card.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

class ConnectionSettingsScreen extends StatefulWidget {
  const ConnectionSettingsScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _connectionStream = _connectionService.connectionStateStream;
    _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    
    // Listen to offline state changes
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
        });
      }
    });
  }

  @override
  void dispose() {
    _offlineSubscription?.cancel();
    super.dispose();
  }

  void _handleDisconnect() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        title: Text(
          'DISCONNECT SERVER',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'Are you sure you want to disconnect? You will need to scan the QR code again to reconnect.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _disconnect();
            },
            child: const Text(
              'DISCONNECT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: Color(0xFFFF4B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    try {
      await _connectionService.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected from server')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error disconnecting: $e')),
        );
      }
    }
  }

  Future<void> _retryConnection() async {
    try {
      final restored = await _connectionService.tryRestoreConnection();
      if (mounted) {
        if (restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection restored')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to restore connection')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CONNECTION'),
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerAwareBottomPadding() + 20,
        ),
        children: [
          // Offline Mode Banner
          if (_isOfflineModeEnabled) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFB300).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Color(0xFFFFB300), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Offline mode is enabled. Disable it in Settings to connect to the server.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFFFB300).withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Connection Status Card
          StreamBuilder<bool>(
            stream: _connectionStream,
            initialData: _connectionService.isConnected,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              
              // Offline mode takes priority
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
                serverInfo: _connectionService.serverInfo,
                lastSyncTime: DateTime.now(),
                onRetry: (isConnected || _isOfflineModeEnabled) ? null : _retryConnection,
              );
            },
          ),
          const SizedBox(height: 24),

          // Server Information Section (hide when offline mode is enabled)
          if (_connectionService.serverInfo != null && !_isOfflineModeEnabled) ...[
            SettingsSection(
              title: 'Server Information',
              tiles: [
                SettingsTile(
                  icon: Icons.dns_rounded,
                  title: 'Server Name',
                  subtitle: _connectionService.serverInfo!.name,
                ),
                SettingsTile(
                  icon: Icons.lan_rounded,
                  title: 'Address',
                  subtitle: _connectionService.serverInfo!.server,
                ),
                SettingsTile(
                  icon: Icons.tag_rounded,
                  title: 'Port',
                  subtitle: _connectionService.serverInfo!.port.toString(),
                ),
                SettingsTile(
                  icon: Icons.info_rounded,
                  title: 'Version',
                  subtitle: _connectionService.serverInfo!.version,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Disconnect Button (hide when offline mode is enabled)
          if (!_isOfflineModeEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _handleDisconnect,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Disconnect Server',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: const Color(0xFFFF4B4B),
                    elevation: 0,
                    shape: const StadiumBorder(),
                    side: BorderSide(color: const Color(0xFFFF4B4B).withOpacity(0.2)),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
