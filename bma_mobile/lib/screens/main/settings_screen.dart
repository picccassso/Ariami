import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = 'Loading...';
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final ConnectionService _connectionService = ConnectionService();
  final StreamingStatsService _statsService = StreamingStatsService();
  bool _isOfflineModeEnabled = false;
  bool _isReconnecting = false;
  StreamSubscription<bool>? _offlineSubscription;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _initOfflineService();
  }

  @override
  void dispose() {
    _offlineSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initOfflineService() async {
    await _offlineService.initialize();
    setState(() {
      _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    });

    // Listen for offline state changes
    _offlineSubscription = _offlineService.offlineStateStream.listen((_) {
      setState(() {
        _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
      });
    });
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
      });
    } catch (e) {
      setState(() {
        _version = 'Unknown';
      });
    }
  }

  /// Handle offline mode toggle - attempts to reconnect when turning off
  Future<void> _handleOfflineModeToggle(bool enabled) async {
    if (enabled) {
      // Turning ON offline mode - just enable it
      await _offlineService.setOfflineMode(true);
      setState(() {
        _isOfflineModeEnabled = true;
      });
    } else {
      // Turning OFF offline mode - attempt to reconnect
      setState(() {
        _isReconnecting = true;
      });

      final restored = await _connectionService.tryRestoreConnection();

      if (restored) {
        // Connection restored - disable offline mode
        await _offlineService.setOfflineMode(false);
        setState(() {
          _isOfflineModeEnabled = false;
          _isReconnecting = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connected to server')),
          );
        }
      } else {
        // Reconnection failed - keep offline mode enabled
        setState(() {
          _isReconnecting = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot connect to server. Staying in offline mode.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Container(
        color: isDark ? Colors.black : Colors.grey[50],
        child: ListView(
          children: [
          // Connection section
          SettingsSection(
            title: 'Connection',
            tiles: [
              SettingsTile(
                icon: Icons.cloud_done,
                title: 'Connection Status',
                subtitle: 'View server connection details',
                onTap: () {
                  Navigator.of(context).pushNamed('/connection');
                },
              ),
              SettingsTile(
                icon: Icons.wifi_off,
                title: 'Offline Mode',
                subtitle: _isReconnecting
                    ? 'Reconnecting...'
                    : (_isOfflineModeEnabled
                        ? 'Only downloaded songs available'
                        : 'Stream music from server'),
                trailing: _isReconnecting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _isOfflineModeEnabled,
                        onChanged: (value) => _handleOfflineModeToggle(value),
                      ),
              ),
            ],
          ),

          // Downloads section
          SettingsSection(
            title: 'Downloads',
            tiles: [
              SettingsTile(
                icon: Icons.high_quality,
                title: 'Download Quality',
                subtitle: 'High - 320 kbps',
                onTap: () {
                  // TODO: Navigate to download quality settings (Task 8.3)
                  _showPlaceholder('Download Quality');
                },
              ),
              SettingsTile(
                icon: Icons.download,
                title: 'Manage Downloads',
                subtitle: 'View storage and downloaded songs',
                onTap: () {
                  Navigator.of(context).pushNamed('/downloads');
                },
              ),
            ],
          ),

          // Statistics section
          SettingsSection(
            title: 'Streaming Stats',
            tiles: [
              SettingsTile(
                icon: Icons.bar_chart,
                title: 'Listening Statistics',
                subtitle: 'View your listening habits',
                onTap: () {
                  Navigator.of(context).pushNamed('/stats');
                },
              ),
              SettingsTile(
                icon: Icons.refresh,
                title: 'Reset Statistics',
                subtitle: 'Clear all play counts and data',
                onTap: () {
                  _showResetStatsDialog();
                },
              ),
            ],
          ),

          // About section
          SettingsSection(
            title: 'About',
            tiles: [
              SettingsTile(
                icon: Icons.info,
                title: 'Version',
                subtitle: _version,
                onTap: () {
                  _showAboutDialog();
                },
              ),
              SettingsTile(
                icon: Icons.description,
                title: 'Licenses',
                subtitle: 'Third-party licenses',
                onTap: () {
                  showLicensePage(context: context);
                },
              ),
            ],
          ),

          const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showPlaceholder(String screen) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$screen - Coming soon')),
    );
  }

  void _showResetStatsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Statistics'),
        content: const Text(
          'This will clear all play counts and streaming data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _statsService.resetAllStats();
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Statistics reset')),
                );
              }
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About BMA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Basic Music App'),
            const SizedBox(height: 12),
            Text(
              'Version: $_version',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            const Text(
              'A music streaming application with offline support.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
