part of 'dashboard_screen.dart';

extension _DashboardLibrary on _DashboardScreenState {
  Future<void> _showSpotifyImport() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SpotifyImportDialog(
          service: SpotifyImportService(_apiClient),
        ),
      );

  Future<void> _rescanLibrary() async {
    try {
      final success = await _setupService.startScan();

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Library rescan started'),
            backgroundColor: AppTheme.surfaceBlack,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadServerStats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start library rescan'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting rescan: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _viewQRCode() async {
    Navigator.pushNamed(context, '/qr-code');
  }

  Future<void> _loadPlaylistSuggestions() async {
    final suggestions = await _setupService.getPlaylistSuggestions();
    if (!mounted) return;
    _setDashboardState(() {
      _playlistSuggestions = suggestions;
    });
  }

  Future<void> _importPlaylistSuggestion(PlaylistSuggestion suggestion) =>
      _decidePlaylistSuggestion(
        suggestion,
        decision: 'import',
        successMessage:
            'Importing "${suggestion.name}" — rescanning the library',
      );

  Future<void> _ignorePlaylistSuggestion(PlaylistSuggestion suggestion) =>
      _decidePlaylistSuggestion(
        suggestion,
        decision: 'ignore',
        successMessage: '"${suggestion.name}" will not be suggested again',
      );

  Future<void> _decidePlaylistSuggestion(
    PlaylistSuggestion suggestion, {
    required String decision,
    required String successMessage,
  }) async {
    if (_decidingSuggestionPaths.contains(suggestion.folderPath)) return;
    _setDashboardState(() {
      _decidingSuggestionPaths.add(suggestion.folderPath);
    });

    try {
      final success = await _setupService.sendPlaylistSuggestionDecision(
        suggestion.folderPath,
        decision,
      );
      if (!mounted) return;

      if (success) {
        _setDashboardState(() {
          _playlistSuggestions = _playlistSuggestions
              .where((s) => s.folderPath != suggestion.folderPath)
              .toList(growable: false);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: AppTheme.surfaceBlack,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadServerStats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $decision "${suggestion.name}"'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        _setDashboardState(() {
          _decidingSuggestionPaths.remove(suggestion.folderPath);
        });
      }
    }
  }

  String _formatLastScanTime() {
    if (_lastScanTime == null) return 'Never';

    try {
      final scanTime = DateTime.parse(_lastScanTime!);
      final now = DateTime.now();
      final difference = now.difference(scanTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
