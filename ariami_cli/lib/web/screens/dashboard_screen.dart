import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/host_controls.dart';
import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';
import '../utils/constants.dart';
import '../widgets/dashboard/change_music_folder_dialog.dart';
import '../widgets/dashboard/dashboard_activity_tab.dart';
import '../widgets/dashboard/dashboard_header.dart';
import '../widgets/dashboard/dashboard_overview_tab.dart';
import '../widgets/dashboard/dashboard_server_tab.dart';
import '../widgets/dashboard/dashboard_users_tab.dart';
import '../widgets/dashboard/change_password_dialog.dart';
import '../widgets/dashboard/create_user_dialog.dart';
import '../widgets/dashboard/delete_user_dialog.dart';
import '../widgets/dashboard/reset_ariami_dialog.dart';
import '../widgets/dashboard/server_reset_complete_panel.dart';
import '../widgets/dashboard/transcode_slots_dialog.dart';
import '../widgets/dashboard/spotify_import_dialog.dart';
import '../widgets/dashboard/spotify_remove_dialog.dart';
import '../services/spotify_import_service.dart';

part 'dashboard_screen_auth.dart';
part 'dashboard_screen_host.dart';
part 'dashboard_screen_library.dart';
part 'dashboard_screen_refresh.dart';
part 'dashboard_screen_users.dart';

const String _dashboardDeviceName = 'Ariami CLI Web Dashboard';
const String _desktopDashboardDeviceName = 'Ariami Desktop Dashboard';
const String _clientTypeDashboard = 'dashboard';
const String _ownerClientsMessage =
    'Owner privileges required to view connected users and devices.';
const String _ownerActivityMessage =
    'Owner privileges required to view user activity.';
const String _ownerUsersMessage =
    'Owner privileges required to manage registered users.';

const List<String> _dashboardTabs = ['Overview', 'Activity', 'Accounts', 'Server'];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
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
  bool _isRefreshingStats = false;
  bool _isLoadingConnectedClients = false;
  bool _isLoadingUserActivity = true;
  bool _isLoadingServerUsers = true;
  bool _isCreatingUser = false;
  bool _isChangingPassword = false;
  bool _isAdmin = false;
  bool _isLoadingTranscodeSlots = false;
  bool _isSavingTranscodeSlots = false;
  String? _transcodeSlotsError;
  TranscodeSlotsSnapshot? _transcodeSlotsSnapshot;

  /// Name shown in the header's account menu.
  String? _currentUsername;

  /// Machine-level settings. Null when this host does not offer them.
  HostControlsSnapshot? _hostControls;
  bool _isLoadingHostControls = false;
  bool _isSavingAutostart = false;

  /// Set once a reset succeeds; the dashboard is replaced by an explanation
  /// because the server stops itself immediately afterwards.
  HostResetOutcome? _resetOutcome;

  /// Null while unknown (not loaded yet, or the request failed).
  SpotifyImportStatus? _spotifyImportStatus;

  /// null until loaded (or when not admin); the Accounts tab hides the toggle
  /// while unknown.
  bool? _userPickerEnabled;
  bool _isSavingUserPicker = false;
  String? _connectedClientsError;
  String? _userActivityError;
  String? _serverUsersError;
  bool _connectedClientsOwnerForbidden = false;
  bool _userActivityOwnerForbidden = false;
  bool _serverUsersOwnerForbidden = false;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  List<UserActivityRow> _userActivityRows = const <UserActivityRow>[];
  List<ServerUserRow> _serverUserRows = const <ServerUserRow>[];
  List<PlaylistSuggestion> _playlistSuggestions = const <PlaylistSuggestion>[];
  final Set<String> _decidingSuggestionPaths = <String>{};
  final Set<String> _kickingDeviceIds = <String>{};
  final Set<String> _deletingUserIds = <String>{};

  String? _dashboardLanServer;
  String? _dashboardTailscaleServer;
  DateTime? _dashboardEndpointsUpdatedAt;
  bool _isRefreshingAddresses = false;
  bool _setupComplete = false;

  Timer? _refreshTimer;
  Timer? _userActivityRefreshTimer;
  late AnimationController _pulseController;
  late TabController _tabController;

  void _setDashboardState(VoidCallback update) => setState(update);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _dashboardTabs.length, vsync: this);
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
      // Owner-gated endpoint: a non-admin session can only ever answer 403.
      if (!_isAdmin) return;
      unawaited(_loadUserActivity(showLoading: false));
    });

    _connectWebSocket();
    unawaited(_loadSetupCompleteStatus());
    unawaited(_loadSpotifyImportStatus());
    unawaited(_loadSignedInUser());
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

  Future<void> _manualRefresh() async {
    _setDashboardState(() => _isRefreshingStats = true);
    await _loadServerStats();
    if (!mounted) return;
    _setDashboardState(() => _isRefreshingStats = false);
  }

  @override
  Widget build(BuildContext context) {
    final resetOutcome = _resetOutcome;
    if (resetOutcome != null) {
      return Scaffold(
        body: ServerResetCompletePanel(outcome: resetOutcome),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: !_setupComplete,
      child: Scaffold(
        backgroundColor: AppTheme.pureBlack,
        appBar: DashboardHeader(
          tabController: _tabController,
          tabs: _dashboardTabs,
          username: _currentUsername,
          isRefreshing: _isRefreshingStats,
          onRefresh: _manualRefresh,
          onShowQrCode: _viewQRCode,
          onSignOut: _signOut,
        ),
        body: TabBarView(
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
              playlistSuggestions: _playlistSuggestions,
              decidingSuggestionPaths: _decidingSuggestionPaths,
              onImportSuggestion: _importPlaylistSuggestion,
              onIgnoreSuggestion: _ignorePlaylistSuggestion,
              onRescanLibrary: _rescanLibrary,
              onImportSpotifyStats: _showSpotifyImport,
              onRemoveSpotifyStats: _showSpotifyRemove,
              spotifyImportStatus: _spotifyImportStatus,
              lanServer: _dashboardLanServer,
              tailscaleServer: _dashboardTailscaleServer,
            ),
            DashboardActivityTab(
              userActivityRows: _userActivityRows,
              isLoadingUserActivity: _isLoadingUserActivity,
              userActivityError: _userActivityError,
              userActivityOwnerForbidden: _userActivityOwnerForbidden,
              onSignInAsOwner:
                  _userActivityOwnerForbidden ? _switchToOwnerLogin : null,
              connectedClientRows: _connectedClientRows,
              isLoadingConnectedClients: _isLoadingConnectedClients,
              isChangingPassword: _isChangingPassword,
              connectedClientsError: _connectedClientsError,
              connectedClientsOwnerForbidden: _connectedClientsOwnerForbidden,
              kickingDeviceIds: _kickingDeviceIds,
              onKick: _kickClient,
              onChangePassword: () => _promptChangePassword(),
              onChangePasswordForUser: (username) =>
                  _promptChangePassword(initialUsername: username),
              formatClientTime: _formatClientTime,
              formatDeviceLabel: _formatDeviceLabel,
            ),
            DashboardUsersTab(
              rows: _serverUserRows,
              isLoading: _isLoadingServerUsers,
              error: _serverUsersError,
              showOwnerSignInCta: _serverUsersOwnerForbidden,
              onSignInAsOwner:
                  _serverUsersOwnerForbidden ? _switchToOwnerLogin : null,
              isCreatingUser: _isCreatingUser,
              isChangingPassword: _isChangingPassword,
              deletingUserIds: _deletingUserIds,
              onCreateUser: _promptCreateUser,
              onChangePassword: (row) => _promptChangePassword(
                initialUsername: row.username,
              ),
              onDeleteUser: _deleteUser,
              userPickerEnabled: _userPickerEnabled,
              isSavingUserPicker: _isSavingUserPicker,
              onToggleUserPicker: _toggleUserPicker,
            ),
            DashboardServerTab(
              lanServer: _dashboardLanServer,
              tailscaleServer: _dashboardTailscaleServer,
              lastUpdatedLabel: _formatEndpointRefreshTime(),
              isRefreshingAddresses: _isRefreshingAddresses,
              onRefreshAddresses: _refreshServerAddresses,
              isAdmin: _isAdmin,
              apiClient: _apiClient,
              transcodeSlotsSnapshot: _transcodeSlotsSnapshot,
              isLoadingTranscodeSlots: _isLoadingTranscodeSlots,
              isSavingTranscodeSlots: _isSavingTranscodeSlots,
              transcodeSlotsError: _transcodeSlotsError,
              onEditTranscodeSlots: _promptEditTranscodeSlots,
              hostControls: _hostControls,
              isLoadingHostControls: _isLoadingHostControls,
              isSavingAutostart: _isSavingAutostart,
              onToggleAutostart: _toggleAutostart,
              onChangeMusicFolder: _changeMusicFolder,
              isScanning: _isScanning,
              onShowQrCode: _viewQRCode,
              onRescanLibrary: _rescanLibrary,
              onResetAriami: _promptResetAriami,
            ),
          ],
        ),
      ),
    );
  }
}
