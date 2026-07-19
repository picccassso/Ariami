part of 'dashboard_screen.dart';

extension _DashboardRefresh on _DashboardScreenState {
  Future<void> _loadSetupCompleteStatus() async {
    try {
      final response = await _apiClient.get('/api/setup/status');
      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};
        final isComplete = data['isComplete'] as bool? ?? false;
        if (mounted) {
          _setDashboardState(() {
            _setupComplete = isComplete;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking setup status: $e');
    }
  }

  Future<void> _loadServerStats() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await _apiClient.get(
        '/api/stats?_=$timestamp',
        includeDeviceIdentity: true,
      );

      if (response.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(response.errorCode);
        return;
      }

      if (response.statusCode == 200) {
        final data = response.jsonBody ?? <String, dynamic>{};

        String? lan;
        String? ts;
        try {
          final infoResp =
              await _apiClient.get('/api/server-info', includeAuth: false);
          if (infoResp.statusCode == 200 && infoResp.jsonBody != null) {
            final j = infoResp.jsonBody!;
            lan = j['lanServer'] as String?;
            ts = j['tailscaleServer'] as String?;
          }
        } catch (_) {
          // Ignore; card falls back to descriptive text only.
        }

        if (mounted) {
          _setDashboardState(() {
            _songCount = data['songCount'] as int? ?? 0;
            _albumCount = data['albumCount'] as int? ?? 0;
            _connectedClients = data['connectedClients'] as int? ?? 0;
            _connectedUsers = data['connectedUsers'] as int? ?? 0;
            _activeSessions = data['activeSessions'] as int? ?? 0;
            _authRequired = data['authRequired'] as bool? ?? false;
            _isScanning = data['isScanning'] as bool? ?? false;
            _lastScanTime = data['lastScanTime'] as String?;
            _serverRunning = data['serverRunning'] as bool? ?? true;
            _dashboardLanServer = lan;
            _dashboardTailscaleServer = ts;
            _dashboardEndpointsUpdatedAt = DateTime.now();
            _isLoading = false;
          });
        }

        // Owner-gated panels: resolve the signed-in user's role once per
        // refresh and skip the admin requests entirely for non-admin
        // accounts — they can only ever answer 403.
        final isAdmin = await _authService.isCurrentUserAdmin();
        if (!mounted) return;
        _setDashboardState(() {
          _isAdmin = isAdmin;
        });

        if (isAdmin) {
          await _loadConnectedClients(showLoading: false);
          await _loadUserActivity(showLoading: false);
          await _loadRegisteredUsers(showLoading: false);
          await _loadTranscodeSlots(showLoading: false);
          await _loadUserPicker();
          await _loadPlaylistSuggestions();
        } else {
          _applyOwnerRequiredPanelState();
        }
      }
    } catch (e) {
      debugPrint('Error loading server stats: $e');
      if (mounted) {
        _setDashboardState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Marks every owner-gated panel with its "owner privileges required"
  /// state (the tabs render their sign-in-as-owner CTA from these flags)
  /// without issuing the requests a non-admin session can never pass.
  void _applyOwnerRequiredPanelState() {
    if (!mounted) return;
    _setDashboardState(() {
      _connectedClientRows = const <ConnectedClientRow>[];
      _connectedClientsOwnerForbidden = true;
      _connectedClientsError = _ownerClientsMessage;
      _isLoadingConnectedClients = false;
      _userActivityRows = const <UserActivityRow>[];
      _userActivityOwnerForbidden = true;
      _userActivityError = _ownerActivityMessage;
      _isLoadingUserActivity = false;
      _serverUserRows = const <ServerUserRow>[];
      _serverUsersOwnerForbidden = true;
      _serverUsersError = _ownerUsersMessage;
      _isLoadingServerUsers = false;
      _transcodeSlotsSnapshot = null;
      _transcodeSlotsError = null;
      _isLoadingTranscodeSlots = false;
      _userPickerEnabled = null;
      _playlistSuggestions = const <PlaylistSuggestion>[];
    });
  }

  /// Runs after [_loadServerStats] has resolved [_isAdmin]; non-admin
  /// sessions never reach the request.
  Future<void> _loadTranscodeSlots({required bool showLoading}) async {
    if (!mounted) return;

    _setDashboardState(() {
      if (showLoading) {
        _isLoadingTranscodeSlots = true;
      }
      if (!_isAdmin) {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = null;
        _isLoadingTranscodeSlots = false;
      }
    });

    if (!_isAdmin) {
      return;
    }

    try {
      final snapshot = await _apiClient.getTranscodeSlots();
      if (!mounted) return;
      _setDashboardState(() {
        _transcodeSlotsSnapshot = snapshot;
        _transcodeSlotsError = null;
        _isLoadingTranscodeSlots = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      if (!mounted) return;
      _setDashboardState(() {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = e.message;
        _isLoadingTranscodeSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _transcodeSlotsSnapshot = null;
        _transcodeSlotsError = 'Failed to load transcode slots.';
        _isLoadingTranscodeSlots = false;
      });
    }
  }

  /// Loads the sign-in account-picker setting. Runs after
  /// [_loadServerStats] has resolved [_isAdmin].
  Future<void> _loadUserPicker() async {
    if (!_isAdmin) {
      if (mounted && _userPickerEnabled != null) {
        _setDashboardState(() {
          _userPickerEnabled = null;
        });
      }
      return;
    }

    try {
      final enabled = await _apiClient.getUserPickerEnabled();
      if (!mounted) return;
      _setDashboardState(() {
        _userPickerEnabled = enabled;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      // Older servers don't have the endpoint; just hide the toggle.
      if (!mounted) return;
      _setDashboardState(() {
        _userPickerEnabled = null;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _userPickerEnabled = null;
      });
    }
  }

  Future<void> _toggleUserPicker(bool enabled) async {
    if (_isSavingUserPicker) return;
    _setDashboardState(() {
      _isSavingUserPicker = true;
    });

    try {
      final applied = await _apiClient.setUserPickerEnabled(enabled);
      if (!mounted) return;
      _setDashboardState(() {
        _userPickerEnabled = applied;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update the account picker setting.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isSavingUserPicker = false;
        });
      }
    }
  }

  Future<void> _promptEditTranscodeSlots() async {
    final snapshot = _transcodeSlotsSnapshot;
    if (snapshot == null || _isSavingTranscodeSlots) {
      return;
    }

    final result = await showTranscodeSlotsDialog(
      context,
      snapshot: snapshot,
    );
    if (result == null) {
      return;
    }

    _setDashboardState(() {
      _isSavingTranscodeSlots = true;
    });

    try {
      final updated = result.reset
          ? await _apiClient.setTranscodeSlots(reset: true)
          : await _apiClient.setTranscodeSlots(slots: result.slots);
      if (!mounted) return;
      _setDashboardState(() {
        _transcodeSlotsSnapshot = updated;
        _transcodeSlotsError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved. Restart the Ariami server for changes to take effect.',
          ),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(e.code);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save transcode slots.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isSavingTranscodeSlots = false;
        });
      }
    }
  }

  Future<void> _refreshServerAddresses() async {
    if (_isRefreshingAddresses) return;

    _setDashboardState(() {
      _isRefreshingAddresses = true;
    });

    try {
      final response = await _apiClient.post('/api/server-info/refresh');
      if (response.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(response.errorCode);
        return;
      }

      if (response.statusCode == 200 && response.jsonBody != null && mounted) {
        final data = response.jsonBody!;
        _setDashboardState(() {
          _dashboardLanServer = data['lanServer'] as String?;
          _dashboardTailscaleServer = data['tailscaleServer'] as String?;
          _dashboardEndpointsUpdatedAt = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing server addresses: $e');
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isRefreshingAddresses = false;
        });
      }
    }
  }

  String? _formatEndpointRefreshTime() {
    final value = _dashboardEndpointsUpdatedAt;
    if (value == null) return null;

    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 5) return 'just now';
    if (difference.inMinutes < 1) return '${difference.inSeconds}s ago';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'at $hour:$minute';
  }
}
