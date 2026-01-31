import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ariami_core/ariami_core.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_state_service.dart';
import 'scanning_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopStateService _stateService = DesktopStateService();

  String? _tailscaleIP;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _serverStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeServer();
    // Listen for client connections to auto-navigate to dashboard
    _httpServer.connectionManager.addListener(_onClientConnected);
  }

  @override
  void dispose() {
    _httpServer.connectionManager.removeListener(_onClientConnected);
    super.dispose();
  }

  void _onClientConnected() async {
    if (_httpServer.connectionManager.clientCount > 0 && mounted) {
      // Mark setup as complete and navigate to dashboard
      await _stateService.markSetupComplete();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    }
  }

  Future<void> _initializeServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Check if server is already running
      if (_httpServer.isRunning) {
        final existingIp = _httpServer.getServerInfo()['server'] as String?;

        // Validate that we have a valid IP
        if (existingIp == null || existingIp.isEmpty) {
          setState(() {
            _errorMessage =
                'Server is running but has no valid IP.\nPlease restart the application.';
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _tailscaleIP = existingIp;
          _serverStarted = true;
          _isLoading = false;
        });
        return;
      }

      // Get Tailscale IP
      final ip = await _tailscaleService.getTailscaleIp();

      if (ip == null) {
        setState(() {
          _errorMessage =
              'Could not find Tailscale IP.\nPlease ensure Tailscale is running and connected.';
          _isLoading = false;
        });
        return;
      }

      // Start HTTP server (singleton will prevent double-start)
      await _httpServer.start(advertisedIp: ip, port: 8080);

      // Check if we need to scan before showing the QR code
      final prefs = await SharedPreferences.getInstance();
      final musicFolderPath = prefs.getString('music_folder_path');

      if (musicFolderPath != null && musicFolderPath.isNotEmpty && mounted) {
        print(
            '[ConnectionScreen] Navigating to scanning screen: $musicFolderPath');
        // Replace with scanning screen, which will then navigate forward to /connection
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ScanningScreen(
              musicFolderPath: musicFolderPath,
              nextRoute: '/connection',
            ),
          ),
        );
        return; // Don't update state, we're navigating away
      }

      // No scan needed, just show QR code
      if (mounted) {
        setState(() {
          _tailscaleIP = ip;
          _serverStarted = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error starting server: $e';
        _isLoading = false;
      });
    }
  }

  String _generateQRData() {
    if (_tailscaleIP == null || !_serverStarted) return '';

    // Generate server info for QR code (matching Phase 4 spec)
    final serverInfo = _httpServer.getServerInfo();

    // Validate that server info has a valid IP before generating QR code
    final serverIp = serverInfo['server'];
    if (serverIp == null || serverIp.toString().isEmpty) {
      return '';
    }

    return jsonEncode(serverInfo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Mobile App'),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.qr_code_2_rounded,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              'Connect Your Mobile App',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Starting server...',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ],
              )
            else if (_errorMessage.isNotEmpty)
              Column(
                children: [
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initializeServer,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (_tailscaleIP != null) ...[
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Side: IP Address
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 32),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141414),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFF2A2A2A)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Your Tailscale IP Address'.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white54,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  _tailscaleIP!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    // Right Side: QR Code + Instructions
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: QrImageView(
                              data: _generateQRData(),
                              version: QrVersions.auto,
                              size: 200.0,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Instructions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. Open Ariami Mobile App\n'
                            '2. Scan this QR code\n'
                            '3. Wait for connection to establish',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () async {
                  await _stateService.markSetupComplete();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/dashboard');
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF333333)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 20,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Continue to Dashboard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}
