import '../../utils/responsive.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/profile_image_service.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../services/theme_service.dart';
import '../../utils/server_disconnect.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/settings_tile.dart';
import 'appearance_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _AvatarAction { choose, remove }

class _ProfileScreenState extends State<ProfileScreen> {
  static const int _maxAvatarBytes = 5 * 1024 * 1024;

  final ConnectionService _connectionService = ConnectionService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final StreamingStatsService _statsService = StreamingStatsService();

  StreamSubscription<OfflineMode>? _offlineSubscription;
  bool _isOfflineModeEnabled = false;
  bool _isLoadingProfile = true;
  bool _isLoggingOut = false;
  bool _isAvatarLoading = false;
  bool _isAvatarUpdating = false;
  String? _profileError;

  String? _username;
  String? _userId;
  String? _deviceName;
  bool _hasAvatar = false;
  int? _avatarUpdatedAt;
  Uint8List? _avatarBytes;

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
    var hasAvatar = _hasAvatar;
    int? avatarUpdatedAt = _avatarUpdatedAt;
    Uint8List? avatarBytes = _avatarBytes;

    try {
      deviceName = await _connectionService.getCurrentDeviceName();

      final apiClient = _connectionService.apiClient;
      final token = _connectionService.sessionToken;
      if (apiClient != null && token != null) {
        final me = await apiClient.getCurrentUser(token);
        username = (me['username'] as String?) ?? username;
        userId = (me['userId'] as String?) ?? userId;
        hasAvatar = me['hasAvatar'] == true;
        avatarUpdatedAt = (me['avatarUpdatedAt'] as num?)?.toInt();

        if (hasAvatar) {
          final shouldFetchAvatar =
              avatarBytes == null || avatarUpdatedAt != _avatarUpdatedAt;
          if (shouldFetchAvatar) {
            if (mounted) {
              setState(() {
                _isAvatarLoading = true;
              });
            }
            avatarBytes = await apiClient.getCurrentUserAvatar(token);
            hasAvatar = avatarBytes != null;
            if (!hasAvatar) {
              avatarUpdatedAt = null;
            }
            if (avatarBytes != null) {
              unawaited(_mirrorAvatarLocally(avatarBytes));
            }
          }
        } else {
          avatarBytes = null;
          avatarUpdatedAt = null;
          unawaited(_mirrorAvatarLocally(null));
        }

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
        _hasAvatar = hasAvatar;
        _avatarUpdatedAt = avatarUpdatedAt;
        _avatarBytes = avatarBytes;
        _isAvatarLoading = false;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _username = username;
        _userId = userId;
        _deviceName = deviceName;
        _isAvatarLoading = false;
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
        navigateToWelcomeScreen(context);
      }
    } catch (e) {
      if (!mounted) return;
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
    final colorScheme = Theme.of(context).colorScheme;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          _buildProfileAvatar(
            colorScheme: colorScheme,
            initial: initial,
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
                    color: colorScheme.onSurface,
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
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar({
    required ColorScheme colorScheme,
    required String initial,
  }) {
    final imageProvider =
        _avatarBytes == null ? null : MemoryImage(_avatarBytes!);
    final isBusy = _isAvatarLoading || _isAvatarUpdating;

    return Semantics(
      button: true,
      label: _hasAvatar ? 'Change profile photo' : 'Add profile photo',
      child: InkWell(
        onTap: isBusy ? null : _showAvatarActions,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: imageProvider,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: imageProvider == null
                      ? Text(
                          initial,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        )
                      : null,
                ),
              ),
              if (isBusy)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    _hasAvatar
                        ? Icons.edit_rounded
                        : Icons.add_photo_alternate_rounded,
                    color: colorScheme.onPrimary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAvatarActions() async {
    if (_isAvatarUpdating) return;

    final action = await showAriamiSheet<_AvatarAction>(
      context: context,
      header: const AriamiSheetHeader(
        title: 'Profile photo',
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: const Text('Choose photo'),
          onTap: () => Navigator.of(context).pop(_AvatarAction.choose),
        ),
        if (_hasAvatar)
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Remove photo',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
          ),
      ],
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _AvatarAction.choose:
        await _handleChooseAvatar();
        break;
      case _AvatarAction.remove:
        await _handleRemoveAvatar();
        break;
    }
  }

  Future<void> _handleChooseAvatar() async {
    final apiClient = _connectionService.apiClient;
    final token = _connectionService.sessionToken;
    if (apiClient == null || token == null) {
      _showProfileSnackBar('Connect to Ariami to update your photo.');
      return;
    }

    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.image,
      );
    } catch (_) {
      if (!mounted) return;
      _showProfileSnackBar('Could not open the photo picker.');
      return;
    }

    if (!mounted || file == null) return;

    if (file.size > _maxAvatarBytes) {
      _showProfileSnackBar('Choose an image under 5 MB.');
      return;
    }

    final bytes = await _readPickedFileBytes(file);
    if (!mounted || bytes == null) {
      _showProfileSnackBar('Could not read that photo.');
      return;
    }

    if (bytes.lengthInBytes > _maxAvatarBytes) {
      _showProfileSnackBar('Choose an image under 5 MB.');
      return;
    }

    final contentType = _detectAvatarContentType(
      bytes,
      file.name.isNotEmpty ? file.name : file.path,
    );
    if (contentType == null) {
      _showProfileSnackBar('Choose a JPG or PNG image.');
      return;
    }

    setState(() {
      _isAvatarUpdating = true;
    });

    try {
      final response = await apiClient.uploadCurrentUserAvatar(
        token,
        bytes: bytes,
        contentType: contentType,
      );
      Uint8List? freshBytes;
      try {
        freshBytes = await apiClient.getCurrentUserAvatar(token);
      } catch (_) {
        freshBytes = null;
      }
      if (!mounted) return;

      setState(() {
        _hasAvatar = true;
        _avatarBytes = freshBytes ?? bytes;
        _avatarUpdatedAt = (response['avatarUpdatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        _isAvatarUpdating = false;
        _profileError = null;
      });
      unawaited(_mirrorAvatarLocally(freshBytes ?? bytes));
      _showProfileSnackBar('Profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAvatarUpdating = false;
      });
      _showProfileSnackBar(_friendlyAvatarError(
        e,
        fallback: 'Could not update your profile photo.',
      ));
    }
  }

  Future<void> _handleRemoveAvatar() async {
    final apiClient = _connectionService.apiClient;
    final token = _connectionService.sessionToken;
    if (apiClient == null || token == null) {
      _showProfileSnackBar('Connect to Ariami to remove your photo.');
      return;
    }

    setState(() {
      _isAvatarUpdating = true;
    });

    try {
      await apiClient.deleteCurrentUserAvatar(token);
      if (!mounted) return;
      setState(() {
        _hasAvatar = false;
        _avatarUpdatedAt = null;
        _avatarBytes = null;
        _isAvatarUpdating = false;
        _profileError = null;
      });
      unawaited(_mirrorAvatarLocally(null));
      _showProfileSnackBar('Profile photo removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAvatarUpdating = false;
      });
      _showProfileSnackBar(_friendlyAvatarError(
        e,
        fallback: 'Could not remove your profile photo.',
      ));
    }
  }

  /// Keeps the legacy local profile photo (shown in the Settings header via
  /// [ProfileImageService]) in step with the account's server-side avatar.
  Future<void> _mirrorAvatarLocally(Uint8List? bytes) async {
    try {
      final service = ProfileImageService();
      if (bytes == null) {
        await service.removeImage();
      } else {
        final extension = _hasPngSignature(bytes) ? 'png' : 'jpg';
        await service.setImageBytes(bytes, extension: extension);
      }
    } catch (_) {
      // The mirror is cosmetic; never let it break the avatar flow.
    }
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String? _detectAvatarContentType(Uint8List bytes, String? fileName) {
    if (_hasJpegSignature(bytes)) return 'image/jpeg';
    if (_hasPngSignature(bytes)) return 'image/png';

    final extension = _fileExtension(fileName);
    if (extension == 'jpg' || extension == 'jpeg') return 'image/jpeg';
    if (extension == 'png') return 'image/png';
    return null;
  }

  bool _hasJpegSignature(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  bool _hasPngSignature(Uint8List bytes) {
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < pngSignature.length) return false;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) return false;
    }
    return true;
  }

  String? _fileExtension(String? fileName) {
    if (fileName == null) return null;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _friendlyAvatarError(Object error, {required String fallback}) {
    if (error is ApiException) {
      final message = error.message.toLowerCase();
      if (error.code == ApiErrorCodes.invalidRequest) {
        return 'Choose a JPG or PNG image.';
      }
      if (message.contains('large') || message.contains('size')) {
        return 'Choose an image under 5 MB.';
      }
      if (error.message.trim().isNotEmpty) {
        return error.message;
      }
    }
    return fallback;
  }

  void _showProfileSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
              subtitle: _formatDurationShort(avg.perActiveDay),
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
      body: ContentWidthLimiter(
          child: ListView(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerScrollBottomPadding(context),
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
      )),
    );
  }
}
