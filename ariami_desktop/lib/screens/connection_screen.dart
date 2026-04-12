import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ariami_core/ariami_core.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_state_service.dart';
import '../services/server_initialization_service.dart';
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
  final ServerInitializationService _serverInit = ServerInitializationService();

  String? _tailscaleIP;
  String? _lanIP;
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
      await _serverInit.configureLibraryCacheAndFeatureFlags(_httpServer);

      // Check if server is already running
      if (_httpServer.isRunning) {
        final serverInfo = _httpServer.getServerInfo();
        final existingIp = serverInfo['server'] as String?;

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
          _tailscaleIP = serverInfo['tailscaleServer'] as String?;
          _lanIP = serverInfo['lanServer'] as String?;
          _serverStarted = true;
          _isLoading = false;
        });
        return;
      }

      final tailscaleIp = await _tailscaleService.getTailscaleIp();
      final lanIp = await _tailscaleService.getLanIp();

      if (tailscaleIp == null && lanIp == null) {
        setState(() {
          _errorMessage =
              'No usable network address was found.\nPlease connect to your local network and try again.';
          _isLoading = false;
        });
        return;
      }

      final advertisedIp = tailscaleIp ?? lanIp!;

      await ServerInitializationService.initializeAuth(
          _httpServer, _stateService);
      await ServerInitializationService.applyDesktopDownloadLimits(_httpServer);

      // Start HTTP server (singleton will prevent double-start)
      await _httpServer.start(
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
        port: 8080,
      );

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
          _tailscaleIP = tailscaleIp;
          _lanIP = lanIp;
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
    if (!_serverStarted) return '';

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
            else if (_tailscaleIP != null || _lanIP != null) ...[
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
                              border:
                                  Border.all(color: const Color(0xFF2A2A2A)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Available Endpoints'.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white54,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_lanIP != null) ...[
                                  _EndpointDisplay(
                                    label: 'Local Network',
                                    value: _lanIP!,
                                    badgeLabel: 'LAN',
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_tailscaleIP != null)
                                  _EndpointDisplay(
                                    label: 'Tailscale',
                                    value: _tailscaleIP!,
                                    badgeLabel: 'REMOTE',
                                  ),
                                if (_tailscaleIP == null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Local setup is available now. Install Tailscale later for remote access.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _httpServer.authRequired
                                        ? Colors.orange.withValues(alpha: 0.2)
                                        : Colors.green.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _httpServer.authRequired
                                          ? Colors.orange.withValues(alpha: 0.5)
                                          : Colors.green.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    _httpServer.authRequired
                                        ? 'AUTH REQUIRED'
                                        : 'OPEN ACCESS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _httpServer.authRequired
                                          ? Colors.orange
                                          : Colors.green,
                                      letterSpacing: 0.5,
                                    ),
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
                  if (!context.mounted) return;
                  Navigator.pushReplacementNamed(context, '/dashboard');
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

class _EndpointDisplay extends StatelessWidget {
  const _EndpointDisplay({
    required this.label,
    required this.value,
    required this.badgeLabel,
  });

  final String label;
  final String value;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
