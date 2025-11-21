import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/desktop_tailscale_service.dart';
import '../services/server/http_server.dart';
import '../services/desktop_state_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final BmaHttpServer _httpServer = BmaHttpServer();
  final DesktopStateService _stateService = DesktopStateService();

  String? _tailscaleIP;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _serverStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  Future<void> _initializeServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Check if server is already running
      if (_httpServer.isRunning) {
        setState(() {
          _tailscaleIP = _httpServer.getServerInfo()['server'] as String?;
          _serverStarted = true;
          _isLoading = false;
        });
        return;
      }

      // Get Tailscale IP
      final ip = await _tailscaleService.getTailscaleIp();

      if (ip == null) {
        setState(() {
          _errorMessage = 'Could not find Tailscale IP.\nPlease ensure Tailscale is running and connected.';
          _isLoading = false;
        });
        return;
      }

      // Start HTTP server (singleton will prevent double-start)
      await _httpServer.start(tailscaleIp: ip, port: 8080);

      // Trigger library scan if music folder is set
      final prefs = await SharedPreferences.getInstance();
      final musicFolderPath = prefs.getString('music_folder_path');
      if (musicFolderPath != null && musicFolderPath.isNotEmpty) {
        print('[ConnectionScreen] Triggering library scan: $musicFolderPath');
        _httpServer.libraryManager.scanMusicFolder(musicFolderPath).then((_) {
          print('[ConnectionScreen] Library scan completed');
        }).catchError((e) {
          print('[ConnectionScreen] Library scan error: $e');
        });
      }

      setState(() {
        _tailscaleIP = ip;
        _serverStarted = true;
        _isLoading = false;
      });
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
    return jsonEncode(serverInfo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Mobile App'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.qr_code_2,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Connect Your Mobile App',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Starting server...',
                      style: TextStyle(fontSize: 16),
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Your Tailscale IP Address:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _tailscaleIP!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: QrImageView(
                    data: _generateQRData(),
                    version: QrVersions.auto,
                    size: 250.0,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Instructions:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Open BMA Mobile App\n'
                  '2. Scan this QR code\n'
                  '3. Wait for connection to establish',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    // Mark setup as complete
                    await _stateService.markSetupComplete();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/dashboard');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Continue to Dashboard',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
