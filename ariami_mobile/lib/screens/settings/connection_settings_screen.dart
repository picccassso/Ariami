import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../widgets/settings/connection_status_card.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';

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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Server'),
        content: const Text(
          'Are you sure you want to disconnect from the server? You will need to scan the QR code again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _disconnect();
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.red),
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
        title: const Text('Connection Status'),
      ),
      body: Container(
        color: isDark ? Colors.black : Colors.grey[50],
        child: ListView(
          padding: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(),
          ),
          children: [
            // Offline Mode Banner
            if (_isOfflineModeEnabled) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Offline mode is enabled. Disable it in Settings to connect to the server.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[800],
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Server Information',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 0),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 1,
                    ),
                    bottom: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    _buildInfoTile(
                      'Server Name',
                      _connectionService.serverInfo!.name,
                      isDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 56.0),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color:
                            isDark ? Colors.grey[800] : Colors.grey[200],
                      ),
                    ),
                    _buildInfoTile(
                      'Address',
                      _connectionService.serverInfo!.server,
                      isDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 56.0),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color:
                            isDark ? Colors.grey[800] : Colors.grey[200],
                      ),
                    ),
                    _buildInfoTile(
                      'Port',
                      _connectionService.serverInfo!.port.toString(),
                      isDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 56.0),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color:
                            isDark ? Colors.grey[800] : Colors.grey[200],
                      ),
                    ),
                    _buildInfoTile(
                      'Version',
                      _connectionService.serverInfo!.version,
                      isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Disconnect Button (hide when offline mode is enabled)
            if (!_isOfflineModeEnabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton.icon(
                  onPressed: _handleDisconnect,
                  icon: const Icon(Icons.logout),
                  label: const Text('Disconnect Server'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
