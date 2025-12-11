import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

class QRCodeScreen extends StatefulWidget {
  const QRCodeScreen({super.key});

  @override
  State<QRCodeScreen> createState() => _QRCodeScreenState();
}

class _QRCodeScreenState extends State<QRCodeScreen> {
  String _serverIp = 'Loading...';
  int _serverPort = 8080;
  String _serverName = 'Loading...';
  String? _qrData;
  bool _isLoading = true;
  String? _errorMessage;

  // Connection polling
  Timer? _connectionPollTimer;
  bool _isWaitingForConnection = false;

  @override
  void initState() {
    super.initState();
    _loadServerInfo();
  }

  @override
  void dispose() {
    _connectionPollTimer?.cancel();
    super.dispose();
  }

  /// Start polling for mobile app connections
  void _startConnectionPolling() {
    setState(() {
      _isWaitingForConnection = true;
    });

    // Poll every 2 seconds for connections
    _connectionPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkForConnections();
    });

    // Also check immediately
    _checkForConnections();
  }

  /// Check if any mobile clients have connected
  Future<void> _checkForConnections() async {
    try {
      final response = await http.get(Uri.parse('/api/stats'));

      if (response.statusCode == 200) {
        final stats = jsonDecode(response.body) as Map<String, dynamic>;
        final clients = stats['connectedClients'] as int? ?? 0;

        if (mounted) {
          // If a client connected, navigate to dashboard
          if (clients > 0) {
            _connectionPollTimer?.cancel();
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        }
      }
    } catch (e) {
      // Silently fail - we'll try again on next poll
      print('Error checking connections: $e');
    }
  }

  Future<void> _loadServerInfo() async {
    try {
      final response = await http.get(Uri.parse('/api/server-info'));

      if (response.statusCode == 200) {
        final serverInfo = jsonDecode(response.body) as Map<String, dynamic>;

        if (mounted) {
          setState(() {
            _serverIp = serverInfo['server'] as String? ?? 'Unknown';
            _serverPort = serverInfo['port'] as int? ?? 8080;
            _serverName = serverInfo['name'] as String? ?? 'BMA Server';

            // Encode server info as JSON string for QR code
            // This matches the format expected by mobile app
            _qrData = jsonEncode(serverInfo);
            _isLoading = false;
          });

          // Start polling for connections
          _startConnectionPolling();
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load server info';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading server info: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Mobile App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _loadServerInfo();
            },
            tooltip: 'Refresh QR Code',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_2, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              const Text(
                'Scan with BMA Mobile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Open the BMA mobile app and scan this QR code to connect',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_isLoading || _qrData == null)
                const SizedBox(
                  width: 250,
                  height: 250,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: _qrData!,
                        version: QrVersions.auto,
                        size: 250,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    if (_isWaitingForConnection) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Waiting for connection...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Server Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.dns, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Name: $_serverName',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.computer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'IP Address: $_serverIp',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.settings_ethernet, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Port: $_serverPort',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/dashboard');
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text(
                  'Go to Dashboard',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
