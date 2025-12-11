import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bma_core/models/websocket_models.dart';
import '../services/web_setup_service.dart';
import '../services/web_websocket_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final WebSetupService _setupService = WebSetupService();
  final WebWebSocketService _wsService = WebWebSocketService();
  StreamSubscription<WsMessage>? _wsSubscription;

  bool _serverRunning = true;
  int _songCount = 0;
  int _albumCount = 0;
  int _connectedClients = 0;
  bool _isScanning = false;
  String? _lastScanTime;
  bool _isLoading = true;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadServerStats();

    // Reduce polling frequency (fallback only)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_wsService.isConnected) {
        _loadServerStats();
      }
    });

    _connectWebSocket();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsSubscription?.cancel();
    _wsService.dispose();
    super.dispose();
  }

  Future<void> _loadServerStats() async {
    try {
      // Add timestamp to bust browser cache
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await http.get(Uri.parse('/api/stats?_=$timestamp'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (mounted) {
          setState(() {
            _songCount = data['songCount'] as int? ?? 0;
            _albumCount = data['albumCount'] as int? ?? 0;
            _connectedClients = data['connectedClients'] as int? ?? 0;
            _isScanning = data['isScanning'] as bool? ?? false;
            _lastScanTime = data['lastScanTime'] as String?;
            _serverRunning = data['serverRunning'] as bool? ?? true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading server stats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _connectWebSocket() {
    _wsService.connect();

    _wsSubscription = _wsService.messages.listen((message) {
      switch (message.type) {
        case WsMessageType.clientConnected:
          final clientMessage = ClientConnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.clientDisconnected:
          final clientMessage = ClientDisconnectedMessage.fromWsMessage(message);
          _updateClientCount(clientMessage.clientCount);
          break;

        case WsMessageType.libraryUpdated:
          _loadServerStats();
          break;
      }
    });
  }

  void _updateClientCount(int count) {
    if (mounted) {
      setState(() {
        _connectedClients = count;
      });
    }
  }

  Future<void> _rescanLibrary() async {
    try {
      final success = await _setupService.startScan();

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library rescan started')),
        );
        // Immediately refresh stats to show scanning state
        _loadServerStats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start library rescan')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting rescan: $e')),
      );
    }
  }

  Future<void> _viewQRCode() async {
    Navigator.pushNamed(context, '/qr-code');
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
        return '${difference.inMinutes} minutes ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hours ago';
      } else {
        return '${difference.inDays} days ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('BMA Server Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadServerStats,
            tooltip: 'Refresh Stats',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            onPressed: _viewQRCode,
            tooltip: 'Show QR Code',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _serverRunning
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: _serverRunning ? Colors.green : Colors.red,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Server Status',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _serverRunning ? 'Running' : 'Stopped',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          _serverRunning ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_isScanning) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Library scan in progress...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Library Statistics
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Library Statistics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Last scan: ${_formatLastScanTime()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Icon(Icons.music_note, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  '$_songCount',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Songs',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Icon(Icons.album, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  '$_albumCount',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Albums',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Icon(Icons.devices, size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  '$_connectedClients',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Clients',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Actions
                  const Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _rescanLibrary,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_isScanning ? 'Scanning...' : 'Rescan Library'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _viewQRCode,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Show QR Code'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Server Information',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'The BMA server is running and ready to accept connections from mobile devices.',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Use the QR code to connect your mobile app, or access the server directly via its IP address and port.',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
