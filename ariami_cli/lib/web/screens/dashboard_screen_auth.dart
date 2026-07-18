part of 'dashboard_screen.dart';

extension _DashboardAuth on _DashboardScreenState {
  void _connectWebSocket() {
    _wsService.connect(
      onConnected: () {
        _loadServerStats();
      },
      deviceIdProvider: _authService.getOrCreateDeviceId,
      sessionTokenProvider: _authService.getSessionToken,
      onAuthRequired: () {
        _redirectToLogin();
      },
    );

    _wsSubscription = _wsService.messages.listen((message) {
      switch (message.type) {
        case WsMessageType.clientConnected:
          final clientMessage = ClientConnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.clientDisconnected:
          final clientMessage =
              ClientDisconnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.libraryUpdated:
        case WsMessageType.syncTokenAdvanced:
          _loadServerStats();
          break;
      }
    });
  }

  void _updateClientCount(int count) {
    if (mounted) {
      _setDashboardState(() {
        _connectedClients = count;
      });
    }
    unawaited(_loadConnectedClients(showLoading: false));
    unawaited(_loadUserActivity(showLoading: false));
    unawaited(_loadRegisteredUsers(showLoading: false));
  }

  Future<void> _redirectToLogin() async {
    if (!mounted) return;
    await _authService.clearSessionToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<bool> _redirectToLoginIfSessionCannotRecover(String? errorCode) async {
    final hasToken = await _authService.hasSessionToken();
    if (!hasToken || errorCode == AuthErrorCodes.sessionExpired) {
      await _redirectToLogin();
      return true;
    }
    return false;
  }

  Future<void> _switchToOwnerLogin() async {
    await _authService.clearSessionToken();
    if (!mounted) return;
    Navigator.pushNamed(context, '/login');
  }
}
