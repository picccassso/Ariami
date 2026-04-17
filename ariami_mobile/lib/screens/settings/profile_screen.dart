import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';
import 'appearance_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final StreamingStatsService _statsService = StreamingStatsService();

  StreamSubscription<OfflineMode>? _offlineSubscription;
  bool _isOfflineModeEnabled = false;
  bool _isLoadingProfile = true;
  bool _isLoggingOut = false;
  String? _profileError;

  String? _username;
  String? _userId;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    _username = _connectionService.username;
    _userId = _connectionService.userId;

    unawaited(_initializeOfflineMode());
    unawaited(_loadProfileSnapshot());

    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
      });
    });
  }

  @override
  void dispose() {
    _offlineSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeOfflineMode() async {
    await _offlineService.initialize();
    if (!mounted) return;
    setState(() {
      _isOfflineModeEnabled = _offlineService.isOfflineModeEnabled;
    });
  }

  Future<void> _loadProfileSnapshot() async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true;
        _profileError = null;
      });
    }

    String? username = _connectionService.username;
    String? userId = _connectionService.userId;
    String? deviceName;

    try {
      deviceName = await _connectionService.getCurrentDeviceName();

      final apiClient = _connectionService.apiClient;
      final token = _connectionService.sessionToken;
      if (apiClient != null && token != null) {
        final me = await apiClient.getCurrentUser(token);
        username = (me['username'] as String?) ?? username;
        userId = (me['userId'] as String?) ?? userId;

        final serverDeviceName = (me['deviceName'] as String?)?.trim();
        if (serverDeviceName != null && serverDeviceName.isNotEmpty) {
          deviceName = serverDeviceName;
        }
      }

      if (!mounted) return;
      setState(() {
        _username = username;
        _userId = userId;
        _deviceName = deviceName;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _username = username;
        _userId = userId;
        _deviceName = deviceName;
        _profileError = 'Could not refresh profile details.';
        _isLoadingProfile = false;
      });
    }
  }

  String _connectionStatusLabel() {
    if (_isOfflineModeEnabled) return 'Offline mode enabled';
    return _connectionService.isConnected ? 'Connected' : 'Disconnected';
  }

  IconData _connectionStatusIcon() {
    if (_isOfflineModeEnabled) return Icons.wifi_off_rounded;
    return _connectionService.isConnected
        ? Icons.cloud_done_rounded
        : Icons.cloud_off_rounded;
  }

  Future<void> _copyUserId(String userId) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User ID copied')),
    );
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final shouldLogout = await showDialog<bool>(
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
            onPressed: () => Navigator.of(context).pop(false),
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
            onPressed: () => Navigator.of(context).pop(true),
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

    if (shouldLogout != true) return;

    final serverInfo = _connectionService.serverInfo;

    setState(() {
      _isLoggingOut = true;
    });

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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error logging out: $e')),
      );
      setState(() {
        _isLoggingOut = false;
      });
    }
  }

  String _formatDurationShort(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    return '${duration.inMinutes}m';
  }

  Widget _buildHeader({required bool isDark, required String username}) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoadingProfile
                      ? 'Refreshing profile...'
                      : 'Your account hub',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSnapshotSection() {
    final userId = _userId;
    final serverInfo = _connectionService.serverInfo;

    return SettingsSection(
      title: 'Profile Snapshot',
      tiles: [
        SettingsTile(
          icon: Icons.account_circle_rounded,
          title: 'Username',
          subtitle:
              (_username?.trim().isNotEmpty ?? false) ? _username! : 'Guest',
        ),
        if (userId != null && userId.isNotEmpty)
          SettingsTile(
            icon: Icons.badge_rounded,
            title: 'User ID',
            subtitle: userId,
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copyUserId(userId),
              tooltip: 'Copy user ID',
            ),
          ),
        SettingsTile(
          icon: Icons.smartphone_rounded,
          title: 'Device',
          subtitle: _deviceName ?? 'Mobile Device',
        ),
        SettingsTile(
          icon: _connectionStatusIcon(),
          title: 'Connection',
          subtitle: _connectionStatusLabel(),
        ),
        if (!_isOfflineModeEnabled && serverInfo != null)
          SettingsTile(
            icon: serverInfo.isUsingLocalNetworkRoute
                ? Icons.wifi_rounded
                : Icons.vpn_lock_rounded,
            title: 'Route',
            subtitle: serverInfo.routeLabel,
          ),
      ],
    );
  }

  Widget _buildListeningSnapshotSection() {
    return ListenableBuilder(
      listenable: _statsService,
      builder: (context, _) {
        final totals = _statsService.getTotalStats();
        final avg = _statsService.getAverageDailyTime();
        final topSongs = _statsService.getTopSongs(limit: 1);
        final topArtists = _statsService.getTopArtists(limit: 1);

        final topSong = topSongs.isNotEmpty ? topSongs.first : null;
        final topArtist = topArtists.isNotEmpty ? topArtists.first : null;

        return SettingsSection(
          title: 'Listening Snapshot',
          tiles: [
            SettingsTile(
              icon: Icons.schedule_rounded,
              title: 'Total Playtime',
              subtitle: _formatDurationShort(totals.totalTimeStreamed),
            ),
            SettingsTile(
              icon: Icons.music_note_rounded,
              title: 'Songs Played',
              subtitle: totals.totalSongsPlayed.toString(),
            ),
            SettingsTile(
              icon: Icons.trending_up_rounded,
              title: 'Avg Daily Listening',
              subtitle: _formatDurationShort(avg.perCalendarDay),
            ),
            SettingsTile(
              icon: Icons.person_rounded,
              title: 'Top Artist',
              subtitle: topArtist == null
                  ? 'No listening data yet'
                  : '${topArtist.artistName} - ${topArtist.formattedTime}',
            ),
            SettingsTile(
              icon: Icons.audiotrack_rounded,
              title: 'Top Song',
              subtitle: topSong == null
                  ? 'No listening data yet'
                  : '${topSong.songTitle ?? 'Unknown Song'} - ${topSong.formattedTime}',
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActionsSection() {
    return SettingsSection(
      title: 'Quick Actions',
      tiles: [
        SettingsTile(
          icon: Icons.palette_rounded,
          title: 'Appearance',
          subtitle: 'Customize app colors and theme',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AppearanceSettingsScreen(),
            ),
          ),
        ),
        SettingsTile(
          icon: Icons.bar_chart_rounded,
          title: 'Listening Stats',
          subtitle: 'Open full listening insights',
          onTap: () => Navigator.of(context).pushNamed('/stats'),
        ),
        SettingsTile(
          icon: Icons.cloud_done_rounded,
          title: 'Connection Settings',
          subtitle: 'Manage connection, account and server',
          onTap: () => Navigator.of(context).pushNamed('/connection'),
        ),
        SettingsTile(
          icon: Icons.import_export_rounded,
          title: 'Import / Export',
          subtitle: 'Back up or restore playlists and stats',
          onTap: () => Navigator.of(context).pushNamed('/import-export'),
        ),
        SettingsTile(
          icon: Icons.logout_rounded,
          iconColor: const Color(0xFFFF4B4B),
          title: _isLoggingOut ? 'Logging Out...' : 'Log Out',
          subtitle: 'End this session on this device',
          onTap: _isLoggingOut ? null : _handleLogout,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final username =
        (_username?.trim().isNotEmpty ?? false) ? _username! : 'Guest';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _loadProfileSnapshot,
            tooltip: 'Refresh profile',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerAwareBottomPadding(context),
        ),
        children: [
          _buildHeader(isDark: isDark, username: username),
          if (_profileError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                _profileError!,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.orange[300] : const Color(0xFFB26A00),
                ),
              ),
            ),
          _buildProfileSnapshotSection(),
          _buildListeningSnapshotSection(),
          _buildQuickActionsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
