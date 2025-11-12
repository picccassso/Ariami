import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state_service.dart';
import '../services/api/connection_service.dart';
import '../services/mobile_tailscale_service.dart';

/// Splash screen that performs startup checks and routes appropriately
/// - First time users go through full setup
/// - Returning users with Tailscale connected attempt auto-reconnect
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
      final appState = Provider.of<AppStateService>(context, listen: false);
      await appState.initialize();

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Check if this is first time setup
      if (!appState.hasCompletedSetup()) {
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
        _navigateTo('/setup/tailscale');
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 4: Check if we have stored server info
      final serverInfo = appState.getStoredServerInfo();
      if (serverInfo == null) {
        debugPrint('[SplashScreen] No stored server info, showing scanner');
        _navigateTo('/setup/scanner');
        return;
      }

      // Step 5: Attempt auto-reconnect
      _updateStatus('Connecting to server...');
      final connectionService =
          Provider.of<ConnectionService>(context, listen: false);

      final deviceId = await appState.getOrCreateDeviceId();
      final deviceName = await appState.getOrCreateDeviceName();

      final success = await connectionService.attemptAutoReconnect(
        ip: serverInfo.ip,
        port: serverInfo.port,
        deviceId: deviceId,
        deviceName: deviceName,
      );

      if (success) {
        debugPrint('[SplashScreen] Auto-reconnect successful');
        _updateStatus('Connected!');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateTo('/main');
      } else {
        debugPrint('[SplashScreen] Auto-reconnect failed, showing scanner');
        _navigateTo('/setup/scanner');
      }
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
