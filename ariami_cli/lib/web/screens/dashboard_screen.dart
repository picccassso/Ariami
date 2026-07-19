import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';
import '../utils/constants.dart';
import '../widgets/dashboard/dashboard_activity_tab.dart';
import '../widgets/dashboard/dashboard_overview_tab.dart';
import '../widgets/dashboard/dashboard_server_tab.dart';
import '../widgets/dashboard/dashboard_users_tab.dart';
import '../widgets/dashboard/change_password_dialog.dart';
import '../widgets/dashboard/create_user_dialog.dart';
import '../widgets/dashboard/delete_user_dialog.dart';
import '../widgets/dashboard/transcode_slots_dialog.dart';

part 'dashboard_screen_auth.dart';
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

  /// null until loaded (or when not admin); the Users tab hides the toggle
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
    _tabController = TabController(length: 4, vsync: this);
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_setupComplete,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : Column(
                  children: [
                    AppBar(
                      backgroundColor:
                          AppTheme.pureBlack.withValues(alpha: 0.8),
                      automaticallyImplyLeading: false,
                      title: Text(
                        'Dashboard',
                        style: Theme.of(context).appBarTheme.titleTextStyle,
                      ),
                      centerTitle: true,
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
                      bottom: TabBar(
                        controller: _tabController,
                        indicatorColor: Colors.white,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppTheme.textSecondary,
                        dividerColor: Colors.transparent,
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'Activity'),
                          Tab(text: 'Users'),
                          Tab(text: 'Server'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
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
                            onViewQRCode: _viewQRCode,
                          ),
                          DashboardActivityTab(
                            userActivityRows: _userActivityRows,
                            isLoadingUserActivity: _isLoadingUserActivity,
                            userActivityError: _userActivityError,
                            userActivityOwnerForbidden:
                                _userActivityOwnerForbidden,
                            onSignInAsOwner: _userActivityOwnerForbidden
                                ? _switchToOwnerLogin
                                : null,
                            connectedClientRows: _connectedClientRows,
                            isLoadingConnectedClients:
                                _isLoadingConnectedClients,
                            isChangingPassword: _isChangingPassword,
                            connectedClientsError: _connectedClientsError,
                            connectedClientsOwnerForbidden:
                                _connectedClientsOwnerForbidden,
                            kickingDeviceIds: _kickingDeviceIds,
                            onKick: _kickClient,
                            onChangePassword: () => _promptChangePassword(),
                            onChangePasswordForUser: (username) =>
                                _promptChangePassword(
                                    initialUsername: username),
                            formatClientTime: _formatClientTime,
                            formatDeviceLabel: _formatDeviceLabel,
                          ),
                          DashboardUsersTab(
                            rows: _serverUserRows,
                            isLoading: _isLoadingServerUsers,
                            error: _serverUsersError,
                            showOwnerSignInCta: _serverUsersOwnerForbidden,
                            onSignInAsOwner: _serverUsersOwnerForbidden
                                ? _switchToOwnerLogin
                                : null,
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
