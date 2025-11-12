import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_state_service.dart';
import '../services/tailscale_service.dart';

/// Splash screen that performs startup checks and routes appropriately
/// - First time users go through full setup
/// - Returning users with valid setup go to dashboard with auto-started server
/// - Handles various failure scenarios gracefully
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusText = 'Initializing...';
  bool _hasError = false;
  Timer? _timeoutTimer;
  final AppStateService _appStateService = AppStateService();

  @override
  void initState() {
    super.initState();
    _performStartupChecks();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _performStartupChecks() async {
    // Set timeout to prevent infinite loading
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        debugPrint('[SplashScreen] Timeout reached, redirecting to welcome');
        Navigator.of(context).pushReplacementNamed('/welcome');
      }
    });

    try {
      // Step 1: Initialize AppStateService
      _updateStatus('Loading app state...');
      await _appStateService.initialize();

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Check if this is first time setup
      if (!_appStateService.hasCompletedSetup()) {
        debugPrint('[SplashScreen] First time setup required');
        _navigateTo('/welcome');
        return;
      }

      // Step 3: Check Tailscale connectivity
      _updateStatus('Checking Tailscale...');
      final tailscaleService = TailscaleService();
      final isTailscaleConnected = await tailscaleService.isConnected();

      if (!isTailscaleConnected) {
        debugPrint('[SplashScreen] Tailscale not connected');
        _showTailscaleErrorDialog();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 4: Check if music folder still exists
      _updateStatus('Verifying music folder...');
      final musicFolderValid = await _appStateService.isMusicFolderValid();

      if (!musicFolderValid) {
        debugPrint('[SplashScreen] Music folder missing or invalid');
        _showMusicFolderErrorDialog();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 5: All checks passed, go to dashboard
      debugPrint('[SplashScreen] All checks passed, going to dashboard');
      _updateStatus('Loading dashboard...');
      await Future.delayed(const Duration(milliseconds: 500));
      _navigateTo('/dashboard');
    } catch (e) {
      debugPrint('[SplashScreen] Error during startup: $e');
      setState(() {
        _hasError = true;
        _statusText = 'Error: $e';
      });

      // Show error for 2 seconds, then go to welcome
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _navigateTo('/welcome');
      }
    }
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _statusText = status;
      });
    }
    debugPrint('[SplashScreen] $status');
  }

  void _navigateTo(String route) {
    _timeoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  void _showTailscaleErrorDialog() {
    _timeoutTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tailscale Not Connected'),
        content: const Text(
          'BMA requires Tailscale to be connected to function. Please check your Tailscale connection and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performStartupChecks(); // Retry
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateTo('/tailscale-check');
            },
            child: const Text('Fix'),
          ),
        ],
      ),
    );
  }

  void _showMusicFolderErrorDialog() {
    _timeoutTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Music Folder Not Found'),
        content: const Text(
          'The previously selected music folder is no longer accessible. Please select a new folder.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateTo('/folder-selection');
            },
            child: const Text('Select Folder'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.7),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Icon
              Icon(
                Icons.music_note,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 20),

              // App Title
              Text(
                'BMA',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                'Basic Music App',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 60),

              // Loading indicator
              if (!_hasError) ...[
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                const SizedBox(height: 20),
              ],

              // Status text
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 16,
                  color: _hasError
                      ? Colors.red[200]
                      : Colors.white.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),

              // Error indicator
              if (_hasError) ...[
                const SizedBox(height: 20),
                Icon(
                  Icons.error_outline,
                  color: Colors.red[200],
                  size: 40,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
