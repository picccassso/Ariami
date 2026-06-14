import 'dart:async';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connected_client_row.dart';
import '../models/server_user_row.dart';
import '../services/dashboard_admin_api_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/desktop_reset_service.dart';
import '../services/desktop_server_lifecycle_service.dart';
import '../services/desktop_state_service.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_transcode_slots_service.dart';
import '../services/server_initialization_service.dart';
import '../services/system_tray_service.dart';
import '../widgets/admin_credentials_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/create_user_dialog.dart';
import '../widgets/dashboard/dashboard_content.dart';
import '../widgets/delete_user_dialog.dart';
import '../widgets/reset_ariami_dialog.dart';
import '../widgets/transcode_slots_dialog.dart';
import 'owner_setup_screen.dart';
import 'scanning_screen.dart';

part 'dashboard/dashboard_refresh_actions.dart';
part 'dashboard/dashboard_server_actions.dart';
part 'dashboard/dashboard_user_actions.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final DesktopStateService _stateService = DesktopStateService();
  final ServerInitializationService _serverInit = ServerInitializationService();
  final DesktopTranscodeSlotsService _transcodeSlotsService =
      DesktopTranscodeSlotsService();

  static const _dockChannel = MethodChannel('ariami_desktop/dock');

  late final DashboardAdminApiService _adminApi;
  late final DashboardDataService _dashboardData;
  late final DesktopServerLifecycleService _serverLifecycle;

  String? _musicFolderPath;
  String? _tailscaleIP;
  String? _lanIP;
  String? _ownerUsername;
  bool _isLoading = true;
  bool _isRefreshingAddresses = false;
  bool _hasOwnerAccount = false;
  int _connectedClients = 0;
  bool _isLoadingConnectedRows = false;
  bool _isLoadingServerUsers = false;
  bool _isCreatingUser = false;
  bool _isChangingPassword = false;
  String? _connectedRowsError;
  String? _serverUsersError;
  String? _userActivityError;
  List<ConnectedClientRow> _connectedClientRows = const <ConnectedClientRow>[];
  List<ServerUserRow> _serverUserRows = const <ServerUserRow>[];
  List<UserActivityRow> _userActivityRows = const <UserActivityRow>[];
  bool _isLoadingUserActivity = false;
  final Set<String> _kickingDeviceIds = <String>{};
  final Set<String> _deletingUserIds = <String>{};
  Timer? _connectedRowsRefreshTimer;
  Timer? _userActivityRefreshTimer;
  Timer? _adminHeartbeatTimer;
  DateTime? _addressesUpdatedAt;
  TranscodeSlotsSnapshot? _transcodeSlotsSnapshot;
  bool _isSavingTranscodeSlots = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _dashboardData = DashboardDataService(
      httpServer: _httpServer,
      stateService: _stateService,
    );
    _serverLifecycle = DesktopServerLifecycleService(
      httpServer: _httpServer,
      stateService: _stateService,
      tailscaleService: _tailscaleService,
    );
    _adminApi = DashboardAdminApiService(
      httpServer: _httpServer,
      promptCredentials: () =>
          showAdminCredentialsDialog(context, ownerUsername: _ownerUsername),
      showMessage: (message, {bool isError = false}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.redAccent : null,
          ),
        );
      },
      isMounted: () => mounted,
      onSessionInvalidated: () async {
        await _refreshConnectedClientRows(showLoading: false);
        await _refreshServerUsers(showLoading: false);
        await _refreshUserActivity(showLoading: false);
        await _updateServerStatus();
      },
    );

    _loadData();
    _httpServer.libraryManager.addScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.addListener(_onClientConnectionChanged);
    _httpServer.onEndpointsChanged.listen((_) {
      unawaited(_updateServerStatus());
    });
    _connectedRowsRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshConnectedClientRows(showLoading: false));
      unawaited(_refreshServerUsers(showLoading: false));
      if (!_httpServer.isRunning) {
        unawaited(_autoStartServer());
      }
      unawaited(_updateServerStatus());
    });
    _userActivityRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshUserActivity(showLoading: false));
    });
    _adminHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_adminApi.sendAdminHeartbeat());
    });
  }

  void _cancelRefreshTimers() {
    _connectedRowsRefreshTimer?.cancel();
    _userActivityRefreshTimer?.cancel();
    _adminHeartbeatTimer?.cancel();
  }

  void _setDashboardState(VoidCallback update) {
    setState(update);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _httpServer.libraryManager
        .removeScanCompleteListener(_onLibraryScanComplete);
    _httpServer.connectionManager.removeListener(_onClientConnectionChanged);
    _cancelRefreshTimers();
    super.dispose();
  }

  void _onLibraryScanComplete() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onClientConnectionChanged() {
    if (mounted) {
      setState(() {
        _connectedClients = _httpServer.connectionManager.clientCount;
      });
    }
    unawaited(_refreshConnectedClientRows(showLoading: false));
    unawaited(_refreshServerUsers(showLoading: false));
    unawaited(_refreshUserActivity(showLoading: false));
  }

  @override
  Widget build(BuildContext context) {
    return DashboardContent(
      tabController: _tabController,
      isLoading: _isLoading,
      httpServer: _httpServer,
      connectedClients: _connectedClients,
      hasOwnerAccount: _hasOwnerAccount,
      isLoadingUserActivity: _isLoadingUserActivity,
      userActivityError: _userActivityError,
      userActivityRows: _userActivityRows,
      isLoadingConnectedRows: _isLoadingConnectedRows,
      connectedRowsError: _connectedRowsError,
      connectedClientRows: _connectedClientRows,
      kickingDeviceIds: _kickingDeviceIds,
      isLoadingServerUsers: _isLoadingServerUsers,
      serverUsersError: _serverUsersError,
      serverUserRows: _serverUserRows,
      isCreatingUser: _isCreatingUser,
      isChangingPassword: _isChangingPassword,
      deletingUserIds: _deletingUserIds,
      musicFolderPath: _musicFolderPath,
      transcodeSlotsSnapshot: _transcodeSlotsSnapshot,
      isSavingTranscodeSlots: _isSavingTranscodeSlots,
      lanIP: _lanIP,
      tailscaleIP: _tailscaleIP,
      addressRefreshTimeLabel: _formatAddressRefreshTime(),
      isRefreshingAddresses: _isRefreshingAddresses,
      onToggleServer: _toggleServer,
      onOpenOwnerSetup: _openOwnerSetup,
      onKick: _kickClient,
      onCreateUser: _promptCreateUser,
      onChangePassword: (row) => _promptChangePassword(
        initialUsername: row.username,
      ),
      onDeleteUser: _deleteUser,
      onEditTranscodeSlots: _promptEditTranscodeSlots,
      onRefreshAddresses: _refreshServerAddresses,
      onChangeFolder: () {
        Navigator.pushNamed(context, '/folder-selection');
      },
      onShowQr: () {
        Navigator.pushNamed(context, '/connection');
      },
      onRescanLibrary: _musicFolderPath != null && _musicFolderPath!.isNotEmpty
          ? _rescanLibrary
          : null,
      onResetAriami: _resetAriami,
    );
  }
}
