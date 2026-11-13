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
              backgroundColor: AppColors.danger,
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
              backgroundColor: AppColors.danger,
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
              backgroundColor: AppColors.danger,
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
              backgroundColor: AppColors.danger,
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

  Future<void> _curateUserLibrary(ServerUserRow row) async {
    if (!_hasOwnerAccount) {
      await _openOwnerSetup();
      return;
    }

    final info = _httpServer.getServerInfo();
    final host = (info['server'] as String?) ?? '127.0.0.1';
    final port = info['port'] as int? ?? 8080;
    final artworkClient = CurationArtworkClient(
      baseUrl: 'http://$host:$port',
      sessionToken: _adminApi.adminSessionToken,
    );
    var catalogSongs = const <CurationCatalogSong>[];

    final UserLibraryCuration? saved;
    try {
      saved = await showLibraryCurationPickerDialog(
        context,
        title: 'Curate Library · ${row.username}',
        artworkClient: artworkClient,
        loadBundle: () async {
          final curationRes = await _adminApi.sendAdminRequest(
            method: 'GET',
            path: '/api/admin/users/${Uri.encodeComponent(row.userId)}/curation',
          );
          if (curationRes == null ||
              !curationRes.isSuccess ||
              curationRes.jsonBody == null) {
            throw StateError(
              curationRes?.errorMessage ?? 'Could not load user curation.',
            );
          }
          final catalogRes = await _adminApi.sendAdminRequest(
            method: 'GET',
            path: '/api/admin/curation/catalog',
          );
          if (catalogRes == null ||
              !catalogRes.isSuccess ||
              catalogRes.jsonBody == null) {
            throw StateError(
              catalogRes?.errorMessage ?? 'Could not load server catalog.',
            );
          }
          artworkClient.sessionToken = _adminApi.adminSessionToken;
          final json = catalogRes.jsonBody!;
          final standaloneSongs =
              (json['standaloneSongs'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map>()
                  .map((m) => CurationCatalogSong.fromJson(
                      Map<String, dynamic>.from(m)))
                  .toList(growable: false);
          final parsedSongs =
              (json['songs'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map>()
                  .map((m) => CurationCatalogSong.fromJson(
                      Map<String, dynamic>.from(m)))
                  .toList(growable: false);
          catalogSongs = parsedSongs.isNotEmpty ? parsedSongs : standaloneSongs;
          return (
            curation: UserLibraryCuration.fromJson(
              curationRes.jsonBody!,
              fallbackUserId: row.userId,
            ),
            albums: (json['albums'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map((m) =>
                    CurationCatalogAlbum.fromJson(Map<String, dynamic>.from(m)))
                .toList(growable: false),
            playlists:
                (json['playlists'] as List<dynamic>? ?? const <dynamic>[])
                    .whereType<Map>()
                    .map((m) => CurationCatalogPlaylist.fromJson(
                        Map<String, dynamic>.from(m)))
                    .toList(growable: false),
            standaloneSongs: standaloneSongs,
          );
        },
        loadAllSongs: () => catalogSongs,
        loadAlbumSongs: (albumId) async {
          final uri = Uri(
            path: '/api/admin/curation/songs',
            queryParameters: <String, String>{'albumId': albumId},
          ).toString();
          final res = await _adminApi.sendAdminRequest(method: 'GET', path: uri);
          if (res == null || !res.isSuccess || res.jsonBody == null) {
            return const <CurationCatalogSong>[];
          }
          final raw =
              res.jsonBody!['songs'] as List<dynamic>? ?? const <dynamic>[];
          return raw
              .whereType<Map>()
              .map((m) =>
                  CurationCatalogSong.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false);
        },
        searchAllSongs: (query) async {
          final uri = Uri(
            path: '/api/admin/curation/songs',
            queryParameters: <String, String>{'q': query},
          ).toString();
          final res = await _adminApi.sendAdminRequest(method: 'GET', path: uri);
          if (res == null || !res.isSuccess || res.jsonBody == null) {
            return const <CurationCatalogSong>[];
          }
          final raw =
              res.jsonBody!['songs'] as List<dynamic>? ?? const <dynamic>[];
          return raw
              .whereType<Map>()
              .map((m) =>
                  CurationCatalogSong.fromJson(Map<String, dynamic>.from(m)))
              .toList(growable: false);
        },
        onSave: (mode, rules) async {
          final res = await _adminApi.sendAdminRequest(
            method: 'PUT',
            path: '/api/admin/users/${Uri.encodeComponent(row.userId)}/curation',
            body: <String, dynamic>{
              'mode': mode.wireName,
              'onboardingCompleted': true,
              'rules': rules.map((r) => r.toJson()).toList(growable: false),
            },
          );
          if (res == null || !res.isSuccess || res.jsonBody == null) {
            throw StateError(
              res?.errorMessage ?? 'Could not save user curation.',
            );
          }
          return UserLibraryCuration.fromJson(
            res.jsonBody!,
            fallbackUserId: row.userId,
          );
        },
      );
    } finally {
      artworkClient.dispose();
    }

    if (!mounted || saved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated library curation for ${row.username}'),
        duration: const Duration(seconds: 2),
      ),
    );
    await _refreshServerUsers(showLoading: false);
  }
}
