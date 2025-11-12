import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import '../services/server/server_manager.dart';
import '../services/app_state_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ServerManager _serverManager = ServerManager();
  final AppStateService _appStateService = AppStateService();
  bool _isLoading = true;
  bool _isServerStarting = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeServer();
  }

  Future<void> _initializeServer() async {
    setState(() {
      _isLoading = true;
      _isServerStarting = !_serverManager.isRunning;
      _errorMessage = '';
    });

    try {
      // Start the server if not already running
      if (!_serverManager.isRunning) {
        final success = await _serverManager.startServer();

        if (!success) {
          setState(() {
            _errorMessage = 'Could not start server.\nPlease ensure Tailscale is running and connected.';
            _isLoading = false;
            _isServerStarting = false;
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _isServerStarting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
        _isServerStarting = false;
      });
    }
  }

  String _generateQRData() {
    if (!_serverManager.isRunning) return '';

    // Create connection info as JSON
    final connectionInfo = {
      'server': _serverManager.tailscaleIp,
      'port': _serverManager.port,
    };

    return jsonEncode(connectionInfo);
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _isServerStarting ? 'Starting server...' : 'Loading...',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Column(
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
      );
    }

    if (_serverManager.isRunning) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Server Running',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'http://${_serverManager.tailscaleIp}:${_serverManager.port}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
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
              await _appStateService.initialize();
              await _appStateService.markSetupComplete();

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
      );
    }

    return const SizedBox.shrink();
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
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }
}
