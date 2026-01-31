import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class QRCodeScreen extends StatefulWidget {
  const QRCodeScreen({super.key});

  @override
  State<QRCodeScreen> createState() => _QRCodeScreenState();
}

class _QRCodeScreenState extends State<QRCodeScreen> with SingleTickerProviderStateMixin {
  String _serverIp = 'Loading...';
  int _serverPort = 8080;
  String _serverName = 'Loading...';
  String? _qrData;
  bool _isLoading = true;
  String? _errorMessage;

  Timer? _connectionPollTimer;
  bool _isWaitingForConnection = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadServerInfo();
  }

  @override
  void dispose() {
    _connectionPollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Start polling for mobile app connections
  void _startConnectionPolling() {
    setState(() {
      _isWaitingForConnection = true;
    });

    _connectionPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkForConnections();
    });

    _checkForConnections();
  }

  Future<void> _checkForConnections() async {
    try {
      final response = await http.get(Uri.parse('/api/stats'));

      if (response.statusCode == 200) {
        final stats = jsonDecode(response.body) as Map<String, dynamic>;
        final clients = stats['connectedClients'] as int? ?? 0;

        if (mounted) {
          if (clients > 0) {
            _connectionPollTimer?.cancel();
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking connections: $e');
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
            _serverName = serverInfo['name'] as String? ?? 'Ariami Server';
            _qrData = jsonEncode(serverInfo);
            _isLoading = false;
          });
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
      debugPrint('Error loading server info: $e');
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
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('CONNECT'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _loadServerInfo();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.qr_code_2_rounded, size: 48, color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'CONNECT MOBILE APP',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 28,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 48),
                      if (_errorMessage != null)
                        _buildErrorState()
                      else if (_isLoading || _qrData == null)
                        const Center(child: CircularProgressIndicator(color: Colors.white))
                      else
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left Side: Server Details
                              Expanded(
                                flex: 2,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      decoration: AppTheme.glassDecoration,
                                      padding: const EdgeInsets.all(32.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'SERVER INFORMATION',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.textSecondary,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          _buildInfoRow('NAME', _serverName),
                                          const SizedBox(height: 16),
                                          _buildInfoRow('IP ADDRESS', _serverIp),
                                          const SizedBox(height: 16),
                                          _buildInfoRow('PORT', '$_serverPort'),
                                          const SizedBox(height: 24),
                                          const Divider(color: Colors.white10),
                                          const SizedBox(height: 24),
                                          const Text(
                                            'INSTRUCTIONS',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.textSecondary,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            '1. Open Ariami Mobile App\n2. Scan the QR code\n3. Wait for connection',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white70,
                                              height: 1.6,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 48),
                              // Right Side: QR Code
                              Expanded(
                                flex: 1,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.1),
                                            blurRadius: 30,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: _qrData!,
                                        version: QrVersions.auto,
                                        size: 200,
                                        backgroundColor: Colors.white,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                    if (_isWaitingForConnection) ...[
                                      const SizedBox(height: 32),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          FadeTransition(
                                            opacity: _pulseController,
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'WAITING...',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.textSecondary,
                                              letterSpacing: 2.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 48),
                      SizedBox(
                        height: 60,
                        width: 280,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/dashboard');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.surfaceBlack,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppTheme.borderGrey),
                          ),
                          child: const Text('GO TO DASHBOARD'),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _loadServerInfo();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
