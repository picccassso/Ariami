part of 'dashboard_screen.dart';

extension _DashboardUsers on _DashboardScreenState {
  Future<void> _loadConnectedClients({bool showLoading = true}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingConnectedClients = true;
      });
    }

    try {
      final clients = await _apiClient.getConnectedClients();
      clients.sort((a, b) {
        final left = a.lastHeartbeat ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.lastHeartbeat ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });

      if (!mounted) return;
      _setDashboardState(() {
        _connectedClientRows = clients;
        _connectedClientsError = null;
        _connectedClientsOwnerForbidden = false;
        _isLoadingConnectedClients = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }

      if (!mounted) return;
      _setDashboardState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsOwnerForbidden = e.isForbidden;
        _connectedClientsError =
            e.isForbidden ? _ownerClientsMessage : e.message;
        _isLoadingConnectedClients = false;
      });
    } catch (e) {
      if (!mounted) return;
      _setDashboardState(() {
        _connectedClientRows = const <ConnectedClientRow>[];
        _connectedClientsError = 'Failed to load connected users and devices.';
        _connectedClientsOwnerForbidden = false;
        _isLoadingConnectedClients = false;
      });
    }
  }

  Future<void> _loadUserActivity({bool showLoading = true}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingUserActivity = true;
      });
    }

    try {
      final rows = await _apiClient.getUserActivity();
      if (!mounted) return;
      _setDashboardState(() {
        _userActivityRows = rows;
        _userActivityError = null;
        _userActivityOwnerForbidden = false;
        _isLoadingUserActivity = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }

      if (!mounted) return;
      _setDashboardState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityOwnerForbidden = e.isForbidden;
        _userActivityError = e.isForbidden ? _ownerActivityMessage : e.message;
        _isLoadingUserActivity = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _userActivityRows = const <UserActivityRow>[];
        _userActivityError = 'Failed to load active user activity.';
        _userActivityOwnerForbidden = false;
        _isLoadingUserActivity = false;
      });
    }
  }

  Future<void> _loadRegisteredUsers({bool showLoading = true}) async {
    if (showLoading && mounted) {
      _setDashboardState(() {
        _isLoadingServerUsers = true;
      });
    }

    try {
      final rows = await _apiClient.getRegisteredUsers();
      if (!mounted) return;
      _setDashboardState(() {
        _serverUserRows = rows;
        _serverUsersError = null;
        _serverUsersOwnerForbidden = false;
        _isLoadingServerUsers = false;
      });
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
      }

      if (!mounted) return;
      _setDashboardState(() {
        _serverUserRows = const <ServerUserRow>[];
        _serverUsersOwnerForbidden = e.isForbidden;
        _serverUsersError = e.isForbidden ? _ownerUsersMessage : e.message;
        _isLoadingServerUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setDashboardState(() {
        _serverUserRows = const <ServerUserRow>[];
        _serverUsersError = 'Failed to load registered users.';
        _serverUsersOwnerForbidden = false;
        _isLoadingServerUsers = false;
      });
    }
  }

  String _formatClientTime(DateTime? value) {
    if (value == null) return '—';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  bool _isDashboardControlClient(ConnectedClientRow client) {
    if (client.clientType == _clientTypeDashboard) {
      return true;
    }

    // Backward compatibility when older servers do not provide clientType.
    return client.deviceName == _dashboardDeviceName ||
        client.deviceName == _desktopDashboardDeviceName;
  }

  String _formatDeviceLabel(ConnectedClientRow client) {
    if (_isDashboardControlClient(client)) {
      return '${client.deviceName} (Dashboard)';
    }
    return client.deviceName;
  }

  Future<void> _kickClient(ConnectedClientRow client) async {
    if (_kickingDeviceIds.contains(client.deviceId)) return;
    _setDashboardState(() {
      _kickingDeviceIds.add(client.deviceId);
    });

    try {
      await _apiClient.kickClient(client.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Disconnected ${client.deviceName}${client.username == null ? '' : ' (${client.username})'}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadServerStats();
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
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
          content: Text('Failed to disconnect selected device.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _kickingDeviceIds.remove(client.deviceId);
        });
      }
    }
  }

  Future<void> _promptChangePassword({String? initialUsername}) async {
    final payload = await showChangePasswordDialog(
      context,
      initialUsername: initialUsername,
    );

    if (payload == null) return;

    _setDashboardState(() {
      _isChangingPassword = true;
    });

    try {
      await _apiClient.changePassword(
        username: payload['username']!,
        newPassword: payload['newPassword']!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password updated for ${payload['username']}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadServerStats();
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
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
          content: Text('Failed to change password.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _promptCreateUser() async {
    final payload = await showCreateUserDialog(context);
    if (payload == null) return;

    _setDashboardState(() {
      _isCreatingUser = true;
    });

    try {
      await _apiClient.createUser(
        username: payload.username,
        password: payload.password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created user ${payload.username}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRegisteredUsers(showLoading: false);
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
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
          content: Text('Failed to create user.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isCreatingUser = false;
        });
      }
    }
  }

  Future<void> _deleteUser(ServerUserRow row) async {
    if (_deletingUserIds.contains(row.userId)) return;
    final confirmed = await showDeleteUserDialog(context, user: row);
    if (!confirmed) return;

    _setDashboardState(() {
      _deletingUserIds.add(row.userId);
    });

    try {
      await _apiClient.deleteUser(row.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted user ${row.username}'),
          backgroundColor: AppTheme.surfaceBlack,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadServerStats();
    } on WebApiException catch (e) {
      if (e.isAuthError) {
        final didRedirect =
            await _redirectToLoginIfSessionCannotRecover(e.code);
        if (didRedirect) return;
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
          content: Text('Failed to delete user.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _deletingUserIds.remove(row.userId);
        });
      }
    }
  }
}
