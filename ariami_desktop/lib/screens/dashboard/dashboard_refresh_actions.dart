part of '../dashboard_screen.dart';

extension _DashboardRefreshActions on _DashboardScreenState {
  Future<void> _updateServerStatus() async {
    final serverInfo = _httpServer.getServerInfo();
    final clientCount = _httpServer.connectionManager.clientCount;

    if (!mounted) return;
    _setDashboardState(() {
      _tailscaleIP = serverInfo['tailscaleServer'] as String?;
      _lanIP = serverInfo['lanServer'] as String?;
      _connectedClients = clientCount;
      _addressesUpdatedAt = DateTime.now();
    });
  }

  Future<void> _refreshOwnerState() async {
    final hasOwner = await _stateService.hasOwnerAccount();
    final ownerUsername =
        hasOwner ? await _stateService.getOwnerUsername() : null;
    if (!mounted) return;
    _setDashboardState(() {
      _hasOwnerAccount = hasOwner;
      _ownerUsername = ownerUsername;
    });
  }

  Future<void> _openOwnerSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OwnerSetupScreen(isOnboarding: false),
      ),
    );
    await _refreshOwnerState();
    await _updateServerStatus();
    await _refreshServerUsers(showLoading: true);
    await _refreshUserActivity(showLoading: true);
  }

  Future<void> _refreshServerUsers({required bool showLoading}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingServerUsers = true;
      });
    }

    try {
      final rows = await _dashboardData.loadServerUsers();

      if (!mounted) return;
      _setDashboardState(() {
        _serverUserRows = rows;
        _serverUsersError = null;
        _isLoadingServerUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _serverUserRows = const <ServerUserRow>[];
        _serverUsersError = 'Failed to load registered users.';
        _isLoadingServerUsers = false;
      });
    }
  }

  Future<void> _refreshUserActivity({required bool showLoading}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingUserActivity = true;
      });
    }

    try {
      final rows = _dashboardData.loadUserActivity();
      if (!mounted) return;
      _setDashboardState(() {
        _userActivityRows = rows;
        _userActivityError = null;
        _isLoadingUserActivity = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityError =
            'Failed to load active download/transcode activity.';
        _isLoadingUserActivity = false;
      });
    }
  }

  Future<void> _refreshConnectedClientRows({required bool showLoading}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingConnectedRows = true;
      });
    }

    try {
      final rows = await _dashboardData.loadConnectedClients();

      if (!mounted) return;
      _setDashboardState(() {
        _connectedClientRows = rows;
        _connectedRowsError = null;
        _isLoadingConnectedRows = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedRowsError = 'Failed to load connected users/devices.';
        _isLoadingConnectedRows = false;
      });
    }
  }
}
