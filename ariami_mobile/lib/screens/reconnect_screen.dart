import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api/connection_service.dart';

class ReconnectScreen extends StatefulWidget {
  const ReconnectScreen({super.key});

  @override
  State<ReconnectScreen> createState() => _ReconnectScreenState();
}

class _ReconnectScreenState extends State<ReconnectScreen> {
  final ConnectionService _connectionService = ConnectionService();
  bool _isReconnecting = false;
  bool _isLoadingServerInfo = true;
  String? _errorMessage;
  StreamSubscription<bool>? _connectionSubscription;

  String get _serverName => _connectionService.serverInfo?.name ?? 'Unknown Server';
  String get _serverAddress => _connectionService.serverInfo?.server ?? 'Unknown Address';

  @override
  void initState() {
    super.initState();
    _loadServerInfo();
    _listenToConnectionChanges();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  /// Listen for connection state changes to auto-navigate when reconnected
  void _listenToConnectionChanges() {
    _connectionSubscription = _connectionService.connectionStateStream.listen(
      (isConnected) {
        if (isConnected && mounted) {
          // Connection restored automatically! Navigate to main app
          print('Connection restored automatically - navigating to main app');
          Navigator.pushReplacementNamed(context, '/main');
        }
      },
    );
  }

  /// Load server info from storage if not already loaded
  Future<void> _loadServerInfo() async {
    await _connectionService.loadServerInfoFromStorage();
    if (mounted) {
      setState(() {
        _isLoadingServerInfo = false;
      });
    }
  }

  Future<void> _attemptReconnect() async {
    setState(() {
      _isReconnecting = true;
      _errorMessage = null;
    });

    try {
      final success = await _connectionService.tryRestoreConnection();

      if (success && mounted) {
        // Connection restored! Navigate to main app
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        setState(() {
          _errorMessage = 'Server is offline. Please start the desktop server and try again.';
          _isReconnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed: ${e.toString()}';
        _isReconnecting = false;
      });
    }
  }

  Future<void> _scanNewQRCode() async {
    // Clear saved connection data
    await _connectionService.disconnect();

    if (mounted) {
      // Navigate back to setup flow
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/setup/tailscale',
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while fetching server info
    if (_isLoadingServerInfo) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Icon(
                  Icons.cloud_off_rounded,
                  size: 100,
                  color: Colors.white,
                ),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'Server Offline',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Description
                Text(
                  'Cannot connect to your desktop server',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Server Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF222222),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.computer, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Server:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _serverName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _serverAddress,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B4B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF4B4B).withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFFF4B4B), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFFFF4B4B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Instructions
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.05),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TO RECONNECT:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '1. Start the Ariami Desktop app\n'
                          '2. Wait for the server to start\n'
                          '3. Tap "Retry Connection" below',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),

                // Retry Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isReconnecting ? null : _attemptReconnect,
                    icon: _isReconnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _isReconnecting ? 'Reconnecting...' : 'Retry Connection',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Scan New QR Code Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isReconnecting ? null : _scanNewQRCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text(
                      'Scan New QR Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}