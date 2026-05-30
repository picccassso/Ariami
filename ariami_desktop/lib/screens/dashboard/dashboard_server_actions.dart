part of '../dashboard_screen.dart';

extension _DashboardServerActions on _DashboardScreenState {
  Future<void> _loadData() async {
    _setDashboardState(() {
      _isLoading = true;
    });

    await _serverInit.configureLibraryCacheAndFeatureFlags(_httpServer);
    await _serverInit.ensureTranscodingAndArtworkServices(_httpServer);
    ServerInitializationService.configureNetworkDiscovery(
      _httpServer,
      _tailscaleService,
    );

    final prefs = await SharedPreferences.getInstance();
    _musicFolderPath = prefs.getString('music_folder_path');

    if (_musicFolderPath != null &&
        _musicFolderPath!.startsWith('/Volumes/Macintosh HD')) {
      _musicFolderPath =
          _musicFolderPath!.replaceFirst('/Volumes/Macintosh HD', '');
      await prefs.setString('music_folder_path', _musicFolderPath!);
      print('[Dashboard] Fixed bad music folder path: $_musicFolderPath');
    }

    await _updateServerStatus();
    await _refreshOwnerState();
    await _refreshConnectedClientRows(showLoading: true);
    await _refreshServerUsers(showLoading: true);
    await _refreshUserActivity(showLoading: true);

    _transcodeSlotsSnapshot = await _transcodeSlotsService.getSnapshot();

    _setDashboardState(() {
      _isLoading = false;
    });

    if (!_httpServer.isRunning) {
      await _autoStartServer();
    }
  }

  Future<void> _autoStartServer() async {
    try {
      final launchResult = await _serverLifecycle.start();
      if (launchResult == null) {
        print('[Dashboard] Auto-start skipped: no network address available');
        return;
      }

      print('[Dashboard] Auto-starting server on ${launchResult.advertisedIp}');
      print(
          '[Dashboard] Server listening on port ${launchResult.serverStart.port}');
      if (launchResult.serverStart.fallbackMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(launchResult.serverStart.fallbackMessage!),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      if (Platform.isMacOS) {
        try {
          await _DashboardScreenState._dockChannel.invokeMethod(
            'preventAppNap',
          );
          print('[Dashboard] App Nap prevention enabled');
        } catch (e) {
          print('[Dashboard] Failed to prevent App Nap: $e');
        }
      }

      if (mounted) {
        _setDashboardState(() {});
      }
      await _refreshOwnerState();
      await _refreshConnectedClientRows(showLoading: false);
      await _refreshServerUsers(showLoading: false);
      await _refreshUserActivity(showLoading: false);

      if (_musicFolderPath != null &&
          _musicFolderPath!.isNotEmpty &&
          _httpServer.libraryManager.library == null &&
          mounted) {
        print(
            '[Dashboard] Auto-navigating to scanning screen: $_musicFolderPath');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ScanningScreen(musicFolderPath: _musicFolderPath!),
          ),
        );
      }
    } catch (e) {
      print('[Dashboard] Auto-start server failed: $e');
    }
  }

  String _formatAddressRefreshTime() {
    final value = _addressesUpdatedAt;
    if (value == null) {
      return 'Addresses have not been refreshed yet.';
    }

    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 5) {
      return 'Addresses updated just now.';
    }
    if (difference.inMinutes < 1) {
      return 'Addresses updated ${difference.inSeconds}s ago.';
    }
    if (difference.inHours < 1) {
      return 'Addresses updated ${difference.inMinutes}m ago.';
    }

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'Addresses updated at $hour:$minute.';
  }

  Future<void> _refreshServerAddresses() async {
    if (_isRefreshingAddresses) return;

    if (!_httpServer.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start the server before refreshing addresses.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _setDashboardState(() {
      _isRefreshingAddresses = true;
    });

    try {
      final serverInfo = await _httpServer.refreshAdvertisedEndpoints();
      if (!mounted) return;
      _setDashboardState(() {
        _tailscaleIP = serverInfo['tailscaleServer'] as String?;
        _lanIP = serverInfo['lanServer'] as String?;
        _connectedClients = _httpServer.connectionManager.clientCount;
        _addressesUpdatedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server addresses refreshed.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh addresses: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _isRefreshingAddresses = false;
        });
      }
    }
  }

  Future<void> _rescanLibrary() async {
    if (_musicFolderPath == null || _musicFolderPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a music folder first'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    print('[Dashboard] Manual rescan triggered: $_musicFolderPath');

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ScanningScreen(musicFolderPath: _musicFolderPath!),
        ),
      );
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
          ? await _transcodeSlotsService.setOverride(null)
          : await _transcodeSlotsService.setOverride(result.slots);

      if (!mounted) return;

      _setDashboardState(() {
        _transcodeSlotsSnapshot = updated;
      });

      await _restartServerForTranscodeSlotsChange();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transcode slots updated to ${updated.effective}.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update transcode slots: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
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

  Future<void> _restartServerForTranscodeSlotsChange() async {
    final wasRunning = _httpServer.isRunning;
    if (wasRunning) {
      await _httpServer.stop();
      _adminApi.clearAdminSessionToken();
    }

    await _serverInit.recreateTranscodingService(_httpServer);

    if (!wasRunning) {
      return;
    }

    final launchResult = await _serverLifecycle.start();
    if (launchResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Settings saved, but the server could not be restarted '
              'because no network address is available.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (launchResult.serverStart.fallbackMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(launchResult.serverStart.fallbackMessage!),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    if (mounted) {
      _setDashboardState(() {});
    }
  }

  Future<void> _toggleServer() async {
    if (_httpServer.isRunning) {
      await _httpServer.stop();
      _adminApi.clearAdminSessionToken();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      try {
        final launchResult = await _serverLifecycle.start();
        if (launchResult == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Cannot start server: no network address available'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        if (launchResult.serverStart.fallbackMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(launchResult.serverStart.fallbackMessage!),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        print('[Dashboard] Music folder path: "$_musicFolderPath"');
        print('[Dashboard] Is null: ${_musicFolderPath == null}');
        print('[Dashboard] Is empty: ${_musicFolderPath?.isEmpty ?? true}');

        if (_musicFolderPath != null && _musicFolderPath!.isNotEmpty) {
          print('[Dashboard] Triggering library scan: $_musicFolderPath');
          _httpServer.libraryManager
              .scanMusicFolder(_musicFolderPath!)
              .then((_) {
            print('[Dashboard] Library scan completed');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Music library scan completed'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }).catchError((e) {
            print('[Dashboard] Library scan error: $e');
          });
        } else {
          print(
              '[Dashboard] ERROR: Music folder path not set! Cannot scan library.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Warning: Music folder not set'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Server started'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        await _refreshConnectedClientRows(showLoading: false);
        await _refreshServerUsers(showLoading: false);
        await _refreshUserActivity(showLoading: false);
        await _refreshOwnerState();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is PortBindingException
                    ? e.toString()
                    : 'Failed to start server: $e',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }

    await _updateServerStatus();
    await _refreshOwnerState();
    await _refreshConnectedClientRows(showLoading: false);
    await _refreshServerUsers(showLoading: false);
    await _refreshUserActivity(showLoading: false);
  }
}
