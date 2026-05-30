part of '../dashboard_screen.dart';

extension _DashboardUserActions on _DashboardScreenState {
  Future<void> _kickClient(ConnectedClientRow row) async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to manage connected devices.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    if (_kickingDeviceIds.contains(row.deviceId)) return;
    _setDashboardState(() {
      _kickingDeviceIds.add(row.deviceId);
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/kick-client',
        body: <String, dynamic>{'deviceId': row.deviceId},
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response.errorMessage ?? 'Failed to disconnect device'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected ${row.deviceName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _kickingDeviceIds.remove(row.deviceId);
        });
      }
    }
  }

  Future<void> _promptCreateUser() async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set up the Owner account first to add users.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    final payload = await showCreateUserDialog(context);
    if (payload == null) return;

    _setDashboardState(() {
      _isCreatingUser = true;
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/create-user',
        body: payload.toRequestBody(),
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Failed to create user'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created user ${payload.username}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isCreatingUser = false;
        });
      }
    }
  }

  Future<void> _promptChangePassword({String? initialUsername}) async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to change passwords.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    final payload = await showChangePasswordDialog(
      context,
      initialUsername: initialUsername,
    );
    if (payload == null) return;

    _setDashboardState(() {
      _isChangingPassword = true;
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/change-password',
        body: <String, dynamic>{
          'username': payload.username,
          'newPassword': payload.newPassword,
        },
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response.errorMessage ?? 'Failed to change password'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password updated for ${payload.username}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _deleteUser(ServerUserRow row) async {
    if (!_hasOwnerAccount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up the Owner account first to manage users.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _openOwnerSetup();
      return;
    }

    if (_deletingUserIds.contains(row.userId)) return;
    final confirmed = await showDeleteUserDialog(context, user: row);
    if (!confirmed) return;

    _setDashboardState(() {
      _deletingUserIds.add(row.userId);
    });

    try {
      final response = await _adminApi.sendAdminRequest(
        path: '/api/admin/delete-user',
        body: <String, dynamic>{'userId': row.userId},
      );
      if (response == null) return;

      if (!response.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Failed to delete user'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (row.isAdmin) {
        _adminApi.clearAdminSessionToken();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted user ${row.username}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await _refreshOwnerState();
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);
      await _updateServerStatus();
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _deletingUserIds.remove(row.userId);
        });
      }
    }
  }
}
