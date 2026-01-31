import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
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
  StreamSubscription<OfflineMode>? _offlineSubscription;

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
    // Read current value immediately (in case service is already initialized)
    // This prevents the switch from animating on page load
    setState(() {
      _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    });

    await _offlineService.initialize();

    if (mounted) {
      setState(() {
        _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
      });
    }

    // Listen for offline state changes
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
        });
      }
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

  /// Get subtitle text based on current offline mode state
  String _getOfflineModeSubtitle() {
    final mode = _offlineService.offlineMode;
    switch (mode) {
      case OfflineMode.online:
        return 'Connected to server';
      case OfflineMode.manualOffline:
        return 'Manually disconnected';
      case OfflineMode.autoOffline:
        return 'Connection lost - will auto-reconnect';
    }
  }

  /// Handle offline mode toggle - attempts to reconnect when turning off
  Future<void> _handleOfflineModeToggle(bool enabled) async {
    if (enabled) {
      // Turning ON offline mode - set manual offline mode FIRST, then disconnect
      // Order is critical: setManualOfflineMode must be called before disconnect
      // to prevent race condition where connectionStateStream listener fires
      await _offlineService.setManualOfflineMode(true);
      await _connectionService.disconnect(isManual: true);
      setState(() {
        _isOfflineModeEnabled = true;
      });
    } else {
      // Turning OFF offline mode - disable manual offline and attempt to reconnect
      setState(() {
        _isReconnecting = true;
      });

      await _offlineService.setManualOfflineMode(false);
      final restored = await _connectionService.tryRestoreConnection();

      if (restored) {
        // Connection restored
        setState(() {
          _isOfflineModeEnabled = false;
          _isReconnecting = false;
        });
      } else {
        // Reconnection failed - put back into manual offline mode
        await _offlineService.setManualOfflineMode(true);
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
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('SETTINGS'),
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
          bottom: getMiniPlayerAwareBottomPadding(),
        ),
        children: [
          // Connection section
          SettingsSection(
            title: 'CONNECTION',
            tiles: [
              SettingsTile(
                icon: Icons.cloud_done_rounded,
                title: 'Connection Status',
                subtitle: 'View server connection details',
                onTap: () {
                  Navigator.of(context).pushNamed('/connection');
                },
              ),
              SettingsTile(
                icon: Icons.wifi_off_rounded,
                title: 'Offline Mode',
                subtitle: _isReconnecting
                    ? 'Reconnecting...'
                    : _getOfflineModeSubtitle(),
                trailing: _isReconnecting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _isOfflineModeEnabled,
                        activeThumbColor: isDark ? Colors.white : Colors.black,
                        activeTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
                        inactiveThumbColor: isDark ? Colors.grey[600] : Colors.grey[400],
                        inactiveTrackColor: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
                        onChanged: (value) => _handleOfflineModeToggle(value),
                      ),
              ),
            ],
          ),

          // Downloads section
          SettingsSection(
            title: 'DOWNLOADS',
            tiles: [
              SettingsTile(
                icon: Icons.download_rounded,
                title: 'Manage Downloads',
                subtitle: 'View storage and downloaded songs',
                onTap: () {
                  Navigator.of(context).pushNamed('/downloads');
                },
              ),
              SettingsTile(
                icon: Icons.high_quality_rounded,
                title: 'Streaming Quality',
                subtitle: 'Configure audio quality settings',
                onTap: () {
                  Navigator.of(context).pushNamed('/quality');
                },
              ),
              SettingsTile(
                icon: Icons.import_export_rounded,
                title: 'Import / Export',
                subtitle: 'Import or Export Stats & Playlists',
                onTap: () {
                  Navigator.of(context).pushNamed('/import-export');
                },
              ),
            ],
          ),

          // Statistics section
          SettingsSection(
            title: 'STREAMING STATS',
            tiles: [
              SettingsTile(
                icon: Icons.bar_chart_rounded,
                title: 'Listening Statistics',
                subtitle: 'View your listening habits',
                onTap: () {
                  Navigator.of(context).pushNamed('/stats');
                },
              ),
              SettingsTile(
                icon: Icons.refresh_rounded,
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
            title: 'ABOUT',
            tiles: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                subtitle: _version,
                onTap: () {
                  _showAboutDialog();
                },
              ),
              SettingsTile(
                icon: Icons.description_outlined,
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
    );
  }

  void _showResetStatsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        title: Text(
          'RESET STATS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'This will clear all play counts and streaming data. This action cannot be undone.',
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
              'RESET',
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

  void _showAboutDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        title: Text(
          'ABOUT ARIAMI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ARIAMI MUSIC STREAMING',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'VERSION: $_version',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A music streaming application with offline support.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(
              'CLOSE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
