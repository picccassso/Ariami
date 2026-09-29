part of '../dashboard_screen.dart';

extension _DashboardLibraryActions on _DashboardScreenState {
  /// Reloads the pending playlist suggestions. A failure leaves the current
  /// list alone rather than hiding suggestions the owner can still act on.
  Future<void> _refreshPlaylistSuggestions() async {
    try {
      final suggestions = await _dashboardData.loadPlaylistSuggestions();
      if (!mounted) return;
      _setDashboardState(() => _playlistSuggestions = suggestions);
    } catch (e) {
      print('[Dashboard] Failed to load playlist suggestions: $e');
    }
  }

  Future<void> _decidePlaylistSuggestion(
    PlaylistSuggestion suggestion, {
    required bool shouldImport,
  }) async {
    final folderPath = suggestion.folderPath;
    if (_decidingSuggestionPaths.contains(folderPath)) return;

    final store = _httpServer.libraryManager.playlistDecisionStore;
    if (store == null) {
      _showDashboardMessage(
        'Playlist decisions are not available yet.',
        isError: true,
      );
      return;
    }

    _setDashboardState(() => _decidingSuggestionPaths.add(folderPath));

    try {
      await store.ensureLoaded();
      await store.setDecision(
        folderPath,
        shouldImport
            ? PlaylistFolderDecision.import
            : PlaylistFolderDecision.ignore,
      );
      if (!mounted) return;

      _setDashboardState(() {
        _playlistSuggestions = _playlistSuggestions
            .where((s) => s.folderPath != folderPath)
            .toList(growable: false);
      });

      if (shouldImport) {
        final rescanStarted = _startRescanForPlaylistImport();
        _showDashboardMessage(
          rescanStarted
              ? 'Importing "${suggestion.name}" — rescanning the library'
              : 'Marked "${suggestion.name}" for import. It will appear '
                  'on the next library scan.',
        );
      } else {
        _showDashboardMessage(
          '"${suggestion.name}" will not be suggested again',
        );
      }
    } catch (e) {
      _showDashboardMessage(
        'Failed to ${shouldImport ? 'import' : 'ignore'} '
        '"${suggestion.name}": $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        _setDashboardState(() => _decidingSuggestionPaths.remove(folderPath));
      }
    }
  }

  /// Rescans in the background so an imported folder becomes a playlist
  /// without further action. False when a scan is already running or there is
  /// no scanned folder to rescan.
  bool _startRescanForPlaylistImport() {
    final library = _httpServer.libraryManager;
    final folderPath = library.lastScannedFolderPath ?? _musicFolderPath;
    if (folderPath == null || folderPath.isEmpty || library.isScanning) {
      return false;
    }
    unawaited(
      library.scanMusicFolder(folderPath).catchError((Object e) {
        print('[Dashboard] Rescan after playlist import failed: $e');
      }),
    );
    return true;
  }

  Future<void> _promptEditAlias({required bool isLan}) async {
    final address = isLan ? _lanIP : _tailscaleIP;
    if (address == null) return;

    final result = await showAliasDialog(
      context,
      title: isLan ? 'Rename Local Network Alias' : 'Rename Tailscale Alias',
      address: address,
      currentAlias: isLan ? _lanAlias : _tailscaleAlias,
    );
    if (result == null) return;

    final lanAlias = isLan ? result.alias : _lanAlias;
    final tailscaleAlias = isLan ? _tailscaleAlias : result.alias;

    try {
      await _httpServer.updateEndpointAliases(
        lanAlias: lanAlias,
        tailscaleAlias: tailscaleAlias,
      );
      // The server only persists through its callback once it has started, so
      // save here too — renaming must stick even before the server is up.
      await _stateService.setEndpointAliases(
        lanAlias: lanAlias,
        tailscaleAlias: tailscaleAlias,
      );
      await _updateServerStatus();
      _showDashboardMessage(
        result.alias == null ? 'Alias removed.' : 'Alias saved.',
      );
    } catch (e) {
      _showDashboardMessage('Failed to save alias: $e', isError: true);
    }
  }

  void _showDashboardMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
