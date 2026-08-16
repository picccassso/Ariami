part of 'dashboard_screen.dart';

/// Machine-level settings and the destructive actions that go with them:
/// music folder, start at boot, reset, and signing out of the dashboard.
extension _DashboardHost on _DashboardScreenState {
  /// Snackbar helper so every dashboard message looks the same.
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppTheme.danger : AppTheme.surfaceRaised,
          duration: Duration(seconds: isError ? 6 : 4),
        ),
      );
  }

  Future<void> _loadSignedInUser() async {
    try {
      final response = await _authService.me();
      if (!mounted || !response.isSuccess) return;
      _setDashboardState(() {
        _currentUsername = response.jsonBody?['username'] as String?;
      });
    } catch (_) {
      // The header falls back to a generic account label.
    }
  }

  /// Loads music folder / autostart / reset support. A `NOT_CONFIGURED`
  /// answer means this host does not offer them, so the Server tab hides
  /// those rows rather than showing controls that cannot work.
  Future<void> _loadHostControls() async {
    // Overlapping refreshes (timer, WebSocket reconnect, manual) mean this
    // can resume after the dashboard is gone; setState would then null-check
    // on a disposed element.
    if (!_isAdmin || !mounted) return;

    _setDashboardState(() => _isLoadingHostControls = true);
    try {
      final snapshot = await _apiClient.getHostControls();
      if (!mounted) return;
      _setDashboardState(() {
        _hostControls = snapshot;
        _isLoadingHostControls = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _hostControls = null;
        _isLoadingHostControls = false;
      });
    }
  }

  Future<void> _toggleAutostart(bool enabled) async {
    if (!mounted) return;
    _setDashboardState(() => _isSavingAutostart = true);
    try {
      final snapshot = await _apiClient.setAutostartEnabled(enabled);
      if (!mounted) return;
      _setDashboardState(() {
        _hostControls = snapshot;
        _isSavingAutostart = false;
      });
      _showMessage(
        snapshot.autostartEnabled
            ? 'Ariami will start when this machine boots.'
            : 'Ariami will no longer start at boot.',
      );
    } catch (e) {
      if (!mounted) return;
      _setDashboardState(() => _isSavingAutostart = false);
      _showMessage(
        e is WebApiException && e.response.errorMessage != null
            ? e.response.errorMessage!
            : 'Could not change the start-at-boot setting.',
        isError: true,
      );
    }
  }

  Future<void> _changeMusicFolder() async {
    final newPath = await showDialog<String>(
      context: context,
      builder: (context) => ChangeMusicFolderDialog(
        setupService: _setupService,
        currentPath: _hostControls?.musicFolderPath,
      ),
    );
    if (newPath == null || !mounted) return;

    _showMessage('Music folder set to $newPath. Rescanning…');
    await _loadHostControls();
    await _rescanLibrary();
  }

  Future<void> _promptResetAriami() async {
    final choice = await showDialog<ResetChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ResetAriamiDialog(),
    );
    if (choice == null || !mounted) return;

    try {
      final outcome = await _apiClient.resetHost(
        factory: choice == ResetChoice.factory,
      );
      if (!mounted) return;

      // The server stops itself right after answering, so park the dashboard
      // on a page that explains that rather than letting it poll a dead API.
      _refreshTimer?.cancel();
      _userActivityRefreshTimer?.cancel();
      _wsSubscription?.cancel();
      await _authService.clearSessionToken();
      if (!mounted) return;

      _setDashboardState(() => _resetOutcome = outcome);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e is WebApiException && e.response.errorMessage != null
            ? e.response.errorMessage!
            : 'Could not reset this server.',
        isError: true,
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.logout();
    } catch (_) {
      // The token is cleared locally either way; a failed round trip must
      // not strand someone in a session they asked to leave.
      await _authService.clearSessionToken();
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }
}
